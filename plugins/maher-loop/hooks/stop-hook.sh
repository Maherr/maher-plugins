#!/bin/bash

# Maher Loop Stop Hook
# Like Ralph's stop hook, but extracts <refine> blocks from Claude's output
# to evolve the prompt each iteration.
#
# Flow:
#   1. Check state file exists + session isolation
#   2. Check max iterations
#   3. Read last assistant output from transcript
#   4. Check for <promise> -> stop if found
#   5. Check for <refine> -> update prompt if found (THE MAHER LOOP INNOVATION)
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

# Session isolation
STATE_SESSION=$(echo "$FRONTMATTER" | grep '^session_id:' | sed 's/session_id: *//' || true)
HOOK_SESSION=$(echo "$HOOK_INPUT" | jq -r '.session_id // ""')
if [[ -n "$STATE_SESSION" ]] && [[ "$STATE_SESSION" != "$HOOK_SESSION" ]]; then
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

if ! grep -q '"role":"assistant"' "$TRANSCRIPT_PATH"; then
  echo "Maher loop: No assistant messages in transcript" >&2
  rm "$STATE_FILE"
  exit 0
fi

# Extract the most recent assistant text block (capped at last 100 lines)
LAST_LINES=$(grep '"role":"assistant"' "$TRANSCRIPT_PATH" | tail -n 100)
if [[ -z "$LAST_LINES" ]]; then
  echo "Maher loop: Failed to extract assistant messages" >&2
  rm "$STATE_FILE"
  exit 0
fi

set +e
LAST_OUTPUT=$(echo "$LAST_LINES" | jq -rs '
  map(.message.content[]? | select(.type == "text") | .text) | last // ""
' 2>&1)
JQ_EXIT=$?
set -e

if [[ $JQ_EXIT -ne 0 ]]; then
  echo "Maher loop: Failed to parse transcript JSON" >&2
  rm "$STATE_FILE"
  exit 0
fi

# Check for completion promise
if [[ "$COMPLETION_PROMISE" != "null" ]] && [[ -n "$COMPLETION_PROMISE" ]]; then
  PROMISE_TEXT=$(echo "$LAST_OUTPUT" | perl -0777 -ne 'if(/<promise>(.*?)<\/promise>/s){$t=$1; $t=~s/^\s+|\s+$//g; $t=~s/\s+/ /g; print $t}' 2>/dev/null || echo "")

  if [[ -n "$PROMISE_TEXT" ]] && [[ "$PROMISE_TEXT" = "$COMPLETION_PROMISE" ]]; then
    echo "Maher loop: Detected <promise>$COMPLETION_PROMISE</promise>"
    rm "$STATE_FILE"
    exit 0
  fi
fi

# ============================================================
# MAHER LOOP INNOVATION: Extract <refine> block
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
  # Find the line number of the second --- (end of frontmatter)
  BODY_LINE=$(awk '/^---$/{count++; if(count==2){print NR; exit}}' "$STATE_FILE")

  if [[ -z "$BODY_LINE" ]]; then
    echo "Maher loop: Malformed state file (no closing ---)" >&2
    rm "$STATE_FILE"
    exit 0
  fi

  TEMP_FILE="${STATE_FILE}.tmp.$$"
  # Keep frontmatter (up to and including second ---), update iteration
  head -n "$BODY_LINE" "$STATE_FILE" | sed "s/^iteration: .*/iteration: $NEXT_ITERATION/" > "$TEMP_FILE"
  # Append blank line + refined prompt as new body
  printf '\n%s\n' "$REFINED_PROMPT" >> "$TEMP_FILE"
  mv "$TEMP_FILE" "$STATE_FILE"
else
  # Just update iteration (same as Ralph)
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
