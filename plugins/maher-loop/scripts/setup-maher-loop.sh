#!/bin/bash

# Maher Loop Setup Script
# Creates state file for in-session Maher loop with prompt refinement
#
# Input: reads from stdin (heredoc from go.md) to avoid shell metacharacter
# issues with parentheses, quotes, etc. Falls back to $@ for backward compat.
#
# Supports multiple concurrent loops via unique loop IDs in filenames.

set -euo pipefail

# ============================================================
# Read input: prefer stdin (heredoc), fall back to $@
# ============================================================
RAW_INPUT=""
if [[ ! -t 0 ]]; then
  RAW_INPUT=$(cat)
fi

if [[ -z "$RAW_INPUT" ]] && [[ $# -gt 0 ]]; then
  RAW_INPUT="$*"
fi

# Trim leading/trailing whitespace
RAW_INPUT=$(printf '%s' "$RAW_INPUT" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

# Strip surrounding double quotes if the user wrapped the whole prompt
if [[ "$RAW_INPUT" =~ ^\"(.*)\"$ ]]; then
  RAW_INPUT="${BASH_REMATCH[1]}"
fi

# ============================================================
# Check for help flag
# ============================================================
if [[ "$RAW_INPUT" =~ (^|[[:space:]])(-h|--help)([[:space:]]|$) ]]; then
  cat << 'HELP_EOF'
Maher Loop - Iterative loop with prompt refinement

USAGE:
  /maher-loop:go [PROMPT...] [OPTIONS]

ARGUMENTS:
  PROMPT...    Initial prompt to start the loop (can include any characters)

OPTIONS:
  --max-iterations <n>           Maximum iterations before auto-stop (default: 99)
  --completion-promise '<text>'  Promise phrase (default: DONE)
  -h, --help                     Show this help message

DESCRIPTION:
  Like Ralph Loop, but the prompt EVOLVES each iteration. At the end of each
  iteration, Claude outputs a <refine> block with an improved prompt that
  incorporates what was learned, removes completed work, and sharpens focus.

  Supports multiple concurrent loops — each loop gets a unique ID and runs
  independently in its own session.

  To signal completion, output: <promise>YOUR_PHRASE</promise>
  To refine the prompt, output: <refine>IMPROVED_PROMPT</refine>

EXAMPLES:
  /maher-loop:go Build a todo API --completion-promise DONE --max-iterations 20
  /maher-loop:go --max-iterations 10 Investigate and fix the auth bug

STOPPING:
  Only by reaching --max-iterations or detecting --completion-promise.
  Default: 99 max iterations, completion promise 'DONE'.

MONITORING:
  # List active loops:
  ls .claude/maher-loop-*.local.md 2>/dev/null | grep -v history | grep -v original

  # View current iteration for a loop:
  grep '^iteration:' .claude/maher-loop-LOOPID.local.md
HELP_EOF
  exit 0
fi

# ============================================================
# Parse options from the raw string
# ============================================================
MAX_ITERATIONS=99
COMPLETION_PROMISE="DONE"

if [[ "$RAW_INPUT" =~ --max-iterations[[:space:]]+([0-9]+) ]]; then
  MAX_ITERATIONS="${BASH_REMATCH[1]}"
  RAW_INPUT="${RAW_INPUT/--max-iterations ${BASH_REMATCH[1]}/}"
fi

if [[ "$RAW_INPUT" =~ --completion-promise[[:space:]]+\'([^\']*)\' ]]; then
  COMPLETION_PROMISE="${BASH_REMATCH[1]}"
  RAW_INPUT="${RAW_INPUT/--completion-promise \'${BASH_REMATCH[1]}\'/}"
elif [[ "$RAW_INPUT" =~ --completion-promise[[:space:]]+\"([^\"]*)\" ]]; then
  COMPLETION_PROMISE="${BASH_REMATCH[1]}"
  RAW_INPUT="${RAW_INPUT/--completion-promise \"${BASH_REMATCH[1]}\"/}"
elif [[ "$RAW_INPUT" =~ --completion-promise[[:space:]]+([^[:space:]]+) ]]; then
  COMPLETION_PROMISE="${BASH_REMATCH[1]}"
  RAW_INPUT="${RAW_INPUT/--completion-promise ${BASH_REMATCH[1]}/}"
fi

PROMPT=$(printf '%s' "$RAW_INPUT" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

if [[ -z "$PROMPT" ]]; then
  echo "Error: No prompt provided" >&2
  echo "" >&2
  echo "  Examples:" >&2
  echo "    /maher-loop:go Build a REST API for todos" >&2
  echo "    /maher-loop:go Fix the auth bug --max-iterations 20" >&2
  exit 1
fi

# ============================================================
# Generate unique loop ID and create state files
# ============================================================
mkdir -p .claude

# Generate 8-char random hex ID
LOOP_ID=$(head -c 4 /dev/urandom | od -A n -t x1 | tr -d ' \n')

STATE_FILE=".claude/maher-loop-${LOOP_ID}.local.md"
HISTORY_FILE=".claude/maher-loop-${LOOP_ID}-history.local.md"
ORIGINAL_FILE=".claude/maher-loop-${LOOP_ID}-original.local.md"

# Escape completion promise for safe YAML embedding
if [[ -n "$COMPLETION_PROMISE" ]] && [[ "$COMPLETION_PROMISE" != "null" ]]; then
  ESCAPED_PROMISE="${COMPLETION_PROMISE//\"/\\\"}"
  COMPLETION_PROMISE_YAML="\"$ESCAPED_PROMISE\""
else
  COMPLETION_PROMISE_YAML="null"
fi

STARTED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# Create state file
cat > "$STATE_FILE" <<STATEEOF
---
active: true
iteration: 1
loop_id: ${LOOP_ID}
session_id:
max_iterations: ${MAX_ITERATIONS}
completion_promise: ${COMPLETION_PROMISE_YAML}
started_at: "${STARTED_AT}"
---

STATEEOF
printf '%s\n' "$PROMPT" >> "$STATE_FILE"

# Save original prompt
{
  echo "# Maher Loop - Original Prompt"
  echo ""
  printf '**Loop ID:** %s\n' "$LOOP_ID"
  printf '**Started:** %s\n' "$STARTED_AT"
  echo ""
  printf '%s\n' "$PROMPT"
} > "$ORIGINAL_FILE"

# Initialize history file
{
  echo "# Maher Loop Refinement History"
  echo ""
  printf '**Loop ID:** %s\n' "$LOOP_ID"
  echo ""
  echo "**Original prompt:**"
  printf '%s\n' "$PROMPT"
  echo ""
  echo "---"
} > "$HISTORY_FILE"

# ============================================================
# Count active loops
# ============================================================
ACTIVE_COUNT=0
for f in .claude/maher-loop-*.local.md; do
  [[ "$f" == *-history.local.md ]] && continue
  [[ "$f" == *-original.local.md ]] && continue
  [[ -f "$f" ]] && ACTIVE_COUNT=$((ACTIVE_COUNT + 1))
done

# ============================================================
# Output setup message
# ============================================================
echo "Maher loop activated!"
echo ""
echo "Loop ID: $LOOP_ID"
echo "Iteration: 1"
if [[ $MAX_ITERATIONS -gt 0 ]]; then
  echo "Max iterations: $MAX_ITERATIONS"
else
  echo "Max iterations: unlimited"
fi
if [[ "$COMPLETION_PROMISE" != "null" ]]; then
  echo "Completion promise: $COMPLETION_PROMISE (ONLY output when TRUE)"
else
  echo "Completion promise: none (runs forever)"
fi
if [[ $ACTIVE_COUNT -gt 1 ]]; then
  echo "Active loops: $ACTIVE_COUNT (concurrent)"
fi

cat <<'MSGEOF'

Unlike Ralph which repeats the SAME prompt, Maher Loop REFINES the prompt
each iteration. At the end of each iteration, output a <refine> block to
sharpen the prompt for the next round.

MSGEOF

echo "Files created:"
echo "  $STATE_FILE"
echo "  $ORIGINAL_FILE"
echo "  $HISTORY_FILE"
echo ""

printf '%s\n' "$PROMPT"

# Display completion and refinement instructions
if [[ "$COMPLETION_PROMISE" != "null" ]]; then
  echo ""
  echo "==========================================================="
  echo "MAHER LOOP - Completion & Refinement Protocol"
  echo "==========================================================="
  echo ""
  echo "TO COMPLETE (stop the loop):"
  echo "  <promise>$COMPLETION_PROMISE</promise>"
  echo "  ONLY when the statement is completely TRUE."
  echo ""
  echo "TO REFINE (evolve the prompt for next iteration):"
  echo "  <refine>"
  echo "  Your improved prompt here..."
  echo "  </refine>"
  echo ""
  echo "The <refine> block should be the LAST thing you output"
  echo "before any <promise> tag. If you skip <refine>, the same"
  echo "prompt repeats (Ralph behavior)."
  echo "==========================================================="
else
  echo ""
  echo "==========================================================="
  echo "MAHER LOOP - Refinement Protocol"
  echo "==========================================================="
  echo ""
  echo "TO REFINE (evolve the prompt for next iteration):"
  echo "  <refine>"
  echo "  Your improved prompt here..."
  echo "  </refine>"
  echo ""
  echo "No completion promise set - loop runs until max iterations."
  echo "==========================================================="
fi
