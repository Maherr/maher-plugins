#!/bin/bash

# Maher Loop Stop Hook
# Like Ralph's stop hook, but extracts <refine> blocks from Claude's output
# to evolve the prompt each iteration.
#
# Flow:
#   1. Check state file exists + session isolation
#   2. Check max iterations
#   3. Read last assistant output from transcript (current turn only)
#   4. Check for <promise> -> stop if found
#   5. Check for <refine> -> update prompt if found
#   6. Block exit, feed current/refined prompt back

set -euo pipefail

# Read hook input from stdin
HOOK_INPUT=$(cat)

# Check if maher-loop is active
STATE_FILE=".claude/maher-loop.local.md"

if [[ ! -f "$STATE_FILE" ]]; then
  exit 0
fi

# Parse markdown frontmatter
FRONTMATTER=$(sed -n '/^---$/,/^---$/{ /^---$/d; p; }' "$STATE_FILE")
ITERATION=$(echo "$FRONTMATTER" | grep '^iteration:' | sed 's/iteration: *//')
MAX_ITERATIONS=$(echo "$FRONTMATTER" | grep '^max_iterations:' | sed 's/max_iterations: *//')
COMPLETION_PROMISE=$(echo "$FRONTMATTER" | grep '^completion_promise:' | sed 's/completion_promise: *//' | sed 's/^"\(.*\)"$/\1/')

# Session isolation: only the session that started the loop can trigger it.
# The setup script can't capture session_id (env var not available), so we
# use lazy claiming: first hook invocation writes the session_id to the state
# file, and all subsequent invocations from other sessions are rejected.
STATE_SESSION=$(echo "$FRONTMATTER" | grep '^session_id:' | sed 's/session_id: *//' | tr -d '[:space:]' || true)
HOOK_SESSION=$(echo "$HOOK_INPUT" | jq -r '.session_id // ""')

if [[ -z "$STATE_SESSION" ]] && [[ -n "$HOOK_SESSION" ]]; then
  # First invocation: claim this session as the loop owner
  TEMP_FILE="${STATE_FILE}.tmp.$$"
  sed "s/^session_id: .*/session_id: $HOOK_SESSION/" "$STATE_FILE" > "$TEMP_FILE"
  mv "$TEMP_FILE" "$STATE_FILE"
  STATE_SESSION="$HOOK_SESSION"
  # Re-read frontmatter after modification
  FRONTMATTER=$(sed -n '/^---$/,/^---$/{ /^---$/d; p; }' "$STATE_FILE")
elif [[ -n "$STATE_SESSION" ]] && [[ "$STATE_SESSION" != "$HOOK_SESSION" ]]; then
  # Different session: don't interfere
  exit 0
fi

# Validate numeric fields
if [[ ! "$ITERATION" =~ ^[0-9]+$ ]]; then
  echo "Maher loop: State file corrupted (iteration: '$ITERATION')" >&2
  rm "$STATE_FILE"
  exit 0
fi
if [[ ! "$MAX_ITERATIONS" =~ ^[0-9]+$ ]]; then
  echo "Maher loop: State file corrupted (max_iterations: '$MAX_ITERATIONS')" >&2
  rm "$STATE_FILE"
  exit 0
fi

# Check max iterations
if [[ $MAX_ITERATIONS -gt 0 ]] && [[ $ITERATION -ge $MAX_ITERATIONS ]]; then
  echo "Maher loop: Max iterations ($MAX_ITERATIONS) reached."
  rm "$STATE_FILE"
  exit 0
fi

# Read transcript
TRANSCRIPT_PATH=$(echo "$HOOK_INPUT" | jq -r '.transcript_path')

if [[ ! -f "$TRANSCRIPT_PATH" ]]; then
  echo "Maher loop: Transcript not found" >&2
  rm "$STATE_FILE"
  exit 0
fi

# Extract assistant text from the CURRENT TURN only.
# A "turn" starts after the last HUMAN user message (not tool_result).
# We MUST use jq (not grep) to structurally check message content type,
# because grep matches string literals inside JSON content fields too.
# Only check the last 20 user-type lines for efficiency.
LAST_USER_LINENO=0
while IFS=: read -r num rest; do
  is_human=$(echo "$rest" | jq -r '.message.content[0].type // ""' 2>/dev/null || true)
  if [[ "$is_human" == "text" ]]; then
    LAST_USER_LINENO=$num
  fi
done < <(grep -n '"type":"user"' "$TRANSCRIPT_PATH" | tail -20)

LAST_LINES=$(tail -n +"$((LAST_USER_LINENO + 1))" "$TRANSCRIPT_PATH" | grep '"role":"assistant"' || true)

if [[ -z "$LAST_LINES" ]]; then
  # Race condition: hook fired before assistant text was flushed to transcript.
  # Don't kill the loop — just block exit and re-feed the current prompt.
  # Cap retries at 5 to prevent infinite retry loops.
  RETRY_COUNT=$(echo "$FRONTMATTER" | grep '^retry_count:' | sed 's/retry_count: *//' || true)
  if [[ ! "$RETRY_COUNT" =~ ^[0-9]+$ ]]; then
    RETRY_COUNT=0
  fi

  if [[ $RETRY_COUNT -ge 5 ]]; then
    echo "Maher loop: Transcript flush failed after 5 retries" >&2
    rm "$STATE_FILE"
    exit 0
  fi

  # Increment retry count in state file
  NEXT_RETRY=$((RETRY_COUNT + 1))
  TEMP_FILE="${STATE_FILE}.tmp.$$"
  if grep -q '^retry_count:' "$STATE_FILE"; then
    sed "s/^retry_count: .*/retry_count: $NEXT_RETRY/" "$STATE_FILE" > "$TEMP_FILE"
  else
    sed "/^started_at:/a retry_count: $NEXT_RETRY" "$STATE_FILE" > "$TEMP_FILE"
  fi
  mv "$TEMP_FILE" "$STATE_FILE"

  CURRENT_PROMPT=$(awk '/^---$/{i++; next} i>=2' "$STATE_FILE")
  if [[ -z "$CURRENT_PROMPT" ]]; then
    echo "Maher loop: No prompt in state file" >&2
    rm "$STATE_FILE"
    exit 0
  fi
  jq -n \
    --arg prompt "$CURRENT_PROMPT" \
    --arg msg "Maher iteration $ITERATION | transcript not yet flushed, retry $NEXT_RETRY/5" \
    '{"decision": "block", "reason": $prompt, "systemMessage": $msg}'
  exit 0
fi

# Reset retry count on successful transcript read
if grep -q '^retry_count:' "$STATE_FILE"; then
  TEMP_FILE="${STATE_FILE}.tmp.$$"
  sed '/^retry_count:/d' "$STATE_FILE" > "$TEMP_FILE"
  mv "$TEMP_FILE" "$STATE_FILE"
  # Re-read frontmatter after modification
  FRONTMATTER=$(sed -n '/^---$/,/^---$/{ /^---$/d; p; }' "$STATE_FILE")
fi

# Extract all text blocks from recent assistant messages and join them.
# join("\n") ensures we scan ALL text blocks (not just the last one),
# so <promise> and <refine> tags are found regardless of which text block
# they appear in.
set +e
LAST_OUTPUT=$(echo "$LAST_LINES" | jq -rs '
  map(.message.content[]? | select(.type == "text") | .text) | join("\n")
' 2>&1)
JQ_EXIT=$?
set -e

if [[ $JQ_EXIT -ne 0 ]]; then
  # Fallback to single-block extraction
  LAST_OUTPUT=$(echo "$LAST_LINES" | jq -rs '
    map(.message.content[]? | select(.type == "text") | .text) | last // ""
  ' 2>/dev/null || echo "")
  if [[ -z "$LAST_OUTPUT" ]]; then
    echo "Maher loop: Failed to parse transcript JSON" >&2
    rm "$STATE_FILE"
    exit 0
  fi
fi

# Check for completion promise
if [[ "$COMPLETION_PROMISE" != "null" ]] && [[ -n "$COMPLETION_PROMISE" ]]; then
  PROMISE_TEXT=$(echo "$LAST_OUTPUT" | perl -0777 -ne 'if(/<promise>(.*?)<\/promise>/s){$t=$1; $t=~s/^\s+|\s+$//g; $t=~s/\s+/ /g; print $t}' 2>/dev/null || echo "")

  if [[ -n "$PROMISE_TEXT" ]] && [[ "$PROMISE_TEXT" = "$COMPLETION_PROMISE" ]]; then
    # Completion summary with elapsed time
    STARTED_AT=$(echo "$FRONTMATTER" | grep '^started_at:' | sed 's/started_at: *//' | sed 's/"//g')
    START_EPOCH=$(date -d "$STARTED_AT" +%s 2>/dev/null || echo "")
    if [[ -n "$START_EPOCH" ]]; then
      ELAPSED=$(( $(date +%s) - START_EPOCH ))
      MINS=$((ELAPSED / 60))
      SECS=$((ELAPSED % 60))
      echo "Maher loop: Complete — $ITERATION iterations, ${MINS}m ${SECS}s"
    else
      echo "Maher loop: Complete — $ITERATION iterations"
    fi
    rm "$STATE_FILE"
    exit 0
  fi
fi

# ============================================================
# Extract <refine> block
# ============================================================
# Claude outputs <refine>improved prompt</refine> at the end of
# each iteration. We extract it and use it as the next prompt.
# If no <refine> block, we reuse the current prompt (Ralph behavior).

REFINED_PROMPT=""
PROMPT_WAS_REFINED=false

if echo "$LAST_OUTPUT" | grep -q '<refine>'; then
  # Extract the LAST <refine> block (greedy .* before tag ensures last match)
  REFINED_PROMPT=$(echo "$LAST_OUTPUT" | perl -0777 -ne '
    if(/.*<refine>(.*?)<\/refine>/s){
      $t=$1;
      $t=~s/^\s+|\s+$//g;
      print $t
    }
  ' 2>/dev/null || echo "")
fi

# Get the current prompt from state file body (everything after closing ---)
CURRENT_PROMPT=$(awk '/^---$/{i++; next} i>=2' "$STATE_FILE")

if [[ -n "$REFINED_PROMPT" ]]; then
  PROMPT_TEXT="$REFINED_PROMPT"
  PROMPT_WAS_REFINED=true

  # Log refinement to history file
  HISTORY_FILE=".claude/maher-loop-history.local.md"
  if [[ ! -f "$HISTORY_FILE" ]]; then
    printf '# Maher Loop Refinement History\n\n---\n' > "$HISTORY_FILE"
  fi

  {
    printf '\n## Iteration %d -> %d\n' "$ITERATION" "$((ITERATION + 1))"
    printf '**Refined at:** %s\n\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf '%s\n' "$REFINED_PROMPT"
    printf '\n---\n'
  } >> "$HISTORY_FILE"

else
  PROMPT_TEXT="$CURRENT_PROMPT"
fi

if [[ -z "$PROMPT_TEXT" ]]; then
  echo "Maher loop: No prompt text found in state file" >&2
  rm "$STATE_FILE"
  exit 0
fi

# Update state file
NEXT_ITERATION=$((ITERATION + 1))

if [[ "$PROMPT_WAS_REFINED" = true ]]; then
  # Replace body with refined prompt AND update iteration
  BODY_LINE=$(awk '/^---$/{count++; if(count==2){print NR; exit}}' "$STATE_FILE")

  if [[ -z "$BODY_LINE" ]]; then
    echo "Maher loop: Malformed state file (no closing ---)" >&2
    rm "$STATE_FILE"
    exit 0
  fi

  TEMP_FILE="${STATE_FILE}.tmp.$$"
  head -n "$BODY_LINE" "$STATE_FILE" \
    | sed "s/^iteration: .*/iteration: $NEXT_ITERATION/" \
    > "$TEMP_FILE"
  printf '\n%s\n' "$REFINED_PROMPT" >> "$TEMP_FILE"
  mv "$TEMP_FILE" "$STATE_FILE"
else
  # Just update iteration
  TEMP_FILE="${STATE_FILE}.tmp.$$"
  sed "s/^iteration: .*/iteration: $NEXT_ITERATION/" "$STATE_FILE" > "$TEMP_FILE"
  mv "$TEMP_FILE" "$STATE_FILE"
fi

# Build system message
if [[ "$PROMPT_WAS_REFINED" = true ]]; then
  REFINE_STATUS="prompt REFINED"
else
  REFINE_STATUS="prompt unchanged"
fi

if [[ "$COMPLETION_PROMISE" != "null" ]] && [[ -n "$COMPLETION_PROMISE" ]]; then
  SYSTEM_MSG="Maher iteration $NEXT_ITERATION | $REFINE_STATUS | To stop: output <promise>$COMPLETION_PROMISE</promise> ONLY when TRUE"
else
  SYSTEM_MSG="Maher iteration $NEXT_ITERATION | $REFINE_STATUS | No completion promise set"
fi

# Block exit and feed prompt back
jq -n \
  --arg prompt "$PROMPT_TEXT" \
  --arg msg "$SYSTEM_MSG" \
  '{
    "decision": "block",
    "reason": $prompt,
    "systemMessage": $msg
  }'

exit 0
