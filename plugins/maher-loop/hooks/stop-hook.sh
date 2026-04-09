#!/bin/bash

# Maher Loop Stop Hook
# Like Ralph's stop hook, but extracts <refine> blocks from Claude's output
# to evolve the prompt each iteration.
#
# Supports multiple concurrent loops — finds the state file matching
# the current session via session_id (lazy claiming on first invocation).
#
# Flow:
#   1. Find state file for this session (scan all, match by session_id)
#   2. Check max iterations
#   3. Read last assistant output from transcript (current turn only)
#   4. Check for <promise> -> stop if found, print summary
#   5. Check for <refine> -> update prompt if found
#   6. Block exit, feed current/refined prompt back

set -euo pipefail

# Read hook input from stdin
HOOK_INPUT=$(cat)
HOOK_SESSION=$(echo "$HOOK_INPUT" | jq -r '.session_id // ""')

# ============================================================
# Find the state file for this session
# ============================================================
# Scan all maher-loop state files, skip history/original files,
# find the one matching this session (or claim an unclaimed one).
STATE_FILE=""

for candidate in .claude/maher-loop-*.local.md; do
  [[ "$candidate" == *-history.local.md ]] && continue
  [[ "$candidate" == *-original.local.md ]] && continue
  [[ ! -f "$candidate" ]] && continue

  CANDIDATE_SESSION=$(sed -n '/^---$/,/^---$/{ /^---$/d; p; }' "$candidate" | grep '^session_id:' | sed 's/session_id: *//' | tr -d '[:space:]' || true)

  if [[ -z "$CANDIDATE_SESSION" ]] && [[ -n "$HOOK_SESSION" ]]; then
    # Unclaimed state file — claim it for this session (lazy claiming)
    TEMP_FILE="${candidate}.tmp.$$"
    sed "s/^session_id: .*/session_id: $HOOK_SESSION/" "$candidate" > "$TEMP_FILE"
    mv "$TEMP_FILE" "$candidate"
    STATE_FILE="$candidate"
    break
  elif [[ "$CANDIDATE_SESSION" == "$HOOK_SESSION" ]]; then
    # This state file belongs to our session
    STATE_FILE="$candidate"
    break
  fi
done

# No active loop for this session
if [[ -z "$STATE_FILE" ]]; then
  exit 0
fi

# ============================================================
# Parse state file
# ============================================================
FRONTMATTER=$(sed -n '/^---$/,/^---$/{ /^---$/d; p; }' "$STATE_FILE")
ITERATION=$(echo "$FRONTMATTER" | grep '^iteration:' | sed 's/iteration: *//')
MAX_ITERATIONS=$(echo "$FRONTMATTER" | grep '^max_iterations:' | sed 's/max_iterations: *//')
COMPLETION_PROMISE=$(echo "$FRONTMATTER" | grep '^completion_promise:' | sed 's/completion_promise: *//' | sed 's/^"\(.*\)"$/\1/')
LOOP_ID=$(echo "$FRONTMATTER" | grep '^loop_id:' | sed 's/loop_id: *//' || true)

# Derive history file path from state file
HISTORY_FILE="${STATE_FILE/.local.md/-history.local.md}"

# Validate numeric fields
if [[ ! "$ITERATION" =~ ^[0-9]+$ ]]; then
  echo "Maher loop [$LOOP_ID]: State file corrupted (iteration: '$ITERATION')" >&2
  rm "$STATE_FILE"
  exit 0
fi
if [[ ! "$MAX_ITERATIONS" =~ ^[0-9]+$ ]]; then
  echo "Maher loop [$LOOP_ID]: State file corrupted (max_iterations: '$MAX_ITERATIONS')" >&2
  rm "$STATE_FILE"
  exit 0
fi

# Check max iterations — but check for promise FIRST on the final iteration
# so completion via promise is preferred over max-iterations timeout
if [[ $MAX_ITERATIONS -gt 0 ]] && [[ $ITERATION -ge $MAX_ITERATIONS ]]; then
  # Give the promise check a chance before force-stopping
  MAX_ITER_REACHED=true
else
  MAX_ITER_REACHED=false
fi

# ============================================================
# Read transcript
# ============================================================
TRANSCRIPT_PATH=$(echo "$HOOK_INPUT" | jq -r '.transcript_path')

if [[ ! -f "$TRANSCRIPT_PATH" ]]; then
  echo "Maher loop [$LOOP_ID]: Transcript not found" >&2
  rm "$STATE_FILE"
  exit 0
fi

# Brief delay to ensure the current turn's assistant output is flushed
# to the transcript file. Without this, the hook reads the previous
# turn's output (one iteration behind), causing stale refine extraction.
sleep 0.5

# Extract assistant text from the CURRENT TURN only.
LAST_USER_LINENO=0
while IFS=: read -r num rest; do
  is_human=$(echo "$rest" | jq -r '.message.content[0].type // ""' 2>/dev/null || true)
  if [[ "$is_human" == "text" ]]; then
    LAST_USER_LINENO=$num
  fi
done < <(grep -n '"type":"user"' "$TRANSCRIPT_PATH" | tail -20)

LAST_LINES=$(tail -n +"$((LAST_USER_LINENO + 1))" "$TRANSCRIPT_PATH" | grep '"role":"assistant"' || true)

if [[ -z "$LAST_LINES" ]]; then
  # Race condition: transcript not yet flushed. Retry up to 5 times.
  RETRY_COUNT=$(echo "$FRONTMATTER" | grep '^retry_count:' | sed 's/retry_count: *//' || true)
  if [[ ! "$RETRY_COUNT" =~ ^[0-9]+$ ]]; then
    RETRY_COUNT=0
  fi

  if [[ $RETRY_COUNT -ge 5 ]]; then
    echo "Maher loop [$LOOP_ID]: Transcript flush failed after 5 retries" >&2
    rm "$STATE_FILE"
    exit 0
  fi

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
    echo "Maher loop [$LOOP_ID]: No prompt in state file" >&2
    rm "$STATE_FILE"
    exit 0
  fi
  jq -n \
    --arg prompt "$CURRENT_PROMPT" \
    --arg msg "Maher iteration $ITERATION [$LOOP_ID] | transcript not yet flushed, retry $NEXT_RETRY/5" \
    '{"decision": "block", "reason": $prompt, "systemMessage": $msg}'
  exit 0
fi

# Reset retry count on successful transcript read
if grep -q '^retry_count:' "$STATE_FILE"; then
  TEMP_FILE="${STATE_FILE}.tmp.$$"
  sed '/^retry_count:/d' "$STATE_FILE" > "$TEMP_FILE"
  mv "$TEMP_FILE" "$STATE_FILE"
  FRONTMATTER=$(sed -n '/^---$/,/^---$/{ /^---$/d; p; }' "$STATE_FILE")
fi

# ============================================================
# Extract assistant output
# ============================================================
set +e
LAST_OUTPUT=$(echo "$LAST_LINES" | jq -rs '
  map(.message.content[]? | select(.type == "text") | .text) | join("\n")
' 2>&1)
JQ_EXIT=$?
set -e

if [[ $JQ_EXIT -ne 0 ]]; then
  LAST_OUTPUT=$(echo "$LAST_LINES" | jq -rs '
    map(.message.content[]? | select(.type == "text") | .text) | last // ""
  ' 2>/dev/null || echo "")
  if [[ -z "$LAST_OUTPUT" ]]; then
    echo "Maher loop [$LOOP_ID]: Failed to parse transcript JSON" >&2
    rm "$STATE_FILE"
    exit 0
  fi
fi

# ============================================================
# Check for completion promise
# ============================================================
if [[ "$COMPLETION_PROMISE" != "null" ]] && [[ -n "$COMPLETION_PROMISE" ]]; then
  PROMISE_TEXT=$(echo "$LAST_OUTPUT" | perl -0777 -ne 'if(/<promise>(.*?)<\/promise>/s){$t=$1; $t=~s/^\s+|\s+$//g; $t=~s/\s+/ /g; print $t}' 2>/dev/null || echo "")

  if [[ -n "$PROMISE_TEXT" ]] && [[ "$PROMISE_TEXT" = "$COMPLETION_PROMISE" ]]; then
    # Completion summary — write to /dev/tty to bypass Claude Code output handling
    STARTED_AT=$(echo "$FRONTMATTER" | grep '^started_at:' | sed 's/started_at: *//' | sed 's/"//g')
    START_EPOCH=$(date -d "$STARTED_AT" +%s 2>/dev/null || echo "")
    if [[ -n "$START_EPOCH" ]]; then
      ELAPSED=$(( $(date +%s) - START_EPOCH ))
      MINS=$((ELAPSED / 60))
      SECS=$((ELAPSED % 60))
      SUMMARY="Maher loop [$LOOP_ID]: Complete — $ITERATION iterations, ${MINS}m ${SECS}s"
    else
      SUMMARY="Maher loop [$LOOP_ID]: Complete — $ITERATION iterations"
    fi
    echo "$SUMMARY" > /dev/tty 2>/dev/null || echo "$SUMMARY" >&2
    rm "$STATE_FILE"
    exit 0
  fi
fi

# If max iterations reached and promise wasn't found, force-stop
if [[ "$MAX_ITER_REACHED" = true ]]; then
  STARTED_AT=$(echo "$FRONTMATTER" | grep '^started_at:' | sed 's/started_at: *//' | sed 's/"//g')
  START_EPOCH=$(date -d "$STARTED_AT" +%s 2>/dev/null || echo "")
  if [[ -n "$START_EPOCH" ]]; then
    ELAPSED=$(( $(date +%s) - START_EPOCH ))
    MINS=$((ELAPSED / 60))
    SECS=$((ELAPSED % 60))
    SUMMARY="Maher loop [$LOOP_ID]: Max iterations ($MAX_ITERATIONS) reached. ${MINS}m ${SECS}s elapsed."
  else
    SUMMARY="Maher loop [$LOOP_ID]: Max iterations ($MAX_ITERATIONS) reached."
  fi
  echo "$SUMMARY" > /dev/tty 2>/dev/null || echo "$SUMMARY" >&2
  rm "$STATE_FILE"
  exit 0
fi

# ============================================================
# Extract <refine> block
# ============================================================
REFINED_PROMPT=""
PROMPT_WAS_REFINED=false

if echo "$LAST_OUTPUT" | grep -q '<refine>'; then
  REFINED_PROMPT=$(echo "$LAST_OUTPUT" | perl -0777 -ne '
    if(/.*<refine>(.*?)<\/refine>/s){
      $t=$1;
      $t=~s/^\s+|\s+$//g;
      print $t
    }
  ' 2>/dev/null || echo "")
fi

CURRENT_PROMPT=$(awk '/^---$/{i++; next} i>=2' "$STATE_FILE")

if [[ -n "$REFINED_PROMPT" ]]; then
  PROMPT_TEXT="$REFINED_PROMPT"
  PROMPT_WAS_REFINED=true

  # Log refinement to history file
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
  echo "Maher loop [$LOOP_ID]: No prompt text found in state file" >&2
  rm "$STATE_FILE"
  exit 0
fi

# ============================================================
# Update state file
# ============================================================
NEXT_ITERATION=$((ITERATION + 1))

if [[ "$PROMPT_WAS_REFINED" = true ]]; then
  BODY_LINE=$(awk '/^---$/{count++; if(count==2){print NR; exit}}' "$STATE_FILE")

  if [[ -z "$BODY_LINE" ]]; then
    echo "Maher loop [$LOOP_ID]: Malformed state file (no closing ---)" >&2
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
  TEMP_FILE="${STATE_FILE}.tmp.$$"
  sed "s/^iteration: .*/iteration: $NEXT_ITERATION/" "$STATE_FILE" > "$TEMP_FILE"
  mv "$TEMP_FILE" "$STATE_FILE"
fi

# ============================================================
# Block exit and feed prompt back
# ============================================================
if [[ "$PROMPT_WAS_REFINED" = true ]]; then
  REFINE_STATUS="prompt REFINED"
else
  REFINE_STATUS="prompt unchanged"
fi

if [[ "$COMPLETION_PROMISE" != "null" ]] && [[ -n "$COMPLETION_PROMISE" ]]; then
  SYSTEM_MSG="Maher iteration $NEXT_ITERATION [$LOOP_ID] | $REFINE_STATUS | To stop: output <promise>$COMPLETION_PROMISE</promise> ONLY when TRUE"
else
  SYSTEM_MSG="Maher iteration $NEXT_ITERATION [$LOOP_ID] | $REFINE_STATUS | No completion promise set"
fi

jq -n \
  --arg prompt "$PROMPT_TEXT" \
  --arg msg "$SYSTEM_MSG" \
  '{
    "decision": "block",
    "reason": $prompt,
    "systemMessage": $msg
  }'

exit 0
