#!/bin/bash

# Maher Loop Setup Script
# Creates state file for in-session Maher loop with prompt refinement

set -euo pipefail

# Parse arguments
PROMPT_PARTS=()
MAX_ITERATIONS=99
COMPLETION_PROMISE="DONE"

while [[ $# -gt 0 ]]; do
  case $1 in
    -h|--help)
      cat << 'HELP_EOF'
Maher Loop - Iterative loop with prompt refinement

USAGE:
  /maher-loop:go [PROMPT...] [OPTIONS]

ARGUMENTS:
  PROMPT...    Initial prompt to start the loop (can be multiple words without quotes)

OPTIONS:
  --max-iterations <n>           Maximum iterations before auto-stop (default: 99)
  --completion-promise '<text>'  Promise phrase (USE QUOTES for multi-word, default: DONE)
  -h, --help                     Show this help message

DESCRIPTION:
  Like Ralph Loop, but the prompt EVOLVES each iteration. At the end of each
  iteration, Claude outputs a <refine> block with an improved prompt that
  incorporates what was learned, removes completed work, and sharpens focus.

  To signal completion, output: <promise>YOUR_PHRASE</promise>
  To refine the prompt, output: <refine>IMPROVED_PROMPT</refine>

EXAMPLES:
  /maher-loop:go Build a todo API --completion-promise 'DONE' --max-iterations 20
  /maher-loop:go --max-iterations 10 Investigate and fix the auth bug
  /maher-loop:go Research best practices for caching --completion-promise 'RESEARCH_COMPLETE'

STOPPING:
  Only by reaching --max-iterations or detecting --completion-promise.
  No manual stop - Maher Loop runs infinitely by default!

MONITORING:
  # View current iteration:
  grep '^iteration:' .claude/maher-loop.local.md

  # View current (refined) prompt:
  awk '/^---$/{i++; next} i>=2' .claude/maher-loop.local.md

  # View refinement history:
  cat .claude/maher-loop-history.local.md
HELP_EOF
      exit 0
      ;;
    --max-iterations)
      if [[ -z "${2:-}" ]]; then
        echo "Error: --max-iterations requires a number argument" >&2
        exit 1
      fi
      if ! [[ "$2" =~ ^[0-9]+$ ]]; then
        echo "Error: --max-iterations must be a positive integer or 0, got: $2" >&2
        exit 1
      fi
      MAX_ITERATIONS="$2"
      shift 2
      ;;
    --completion-promise)
      if [[ -z "${2:-}" ]]; then
        echo "Error: --completion-promise requires a text argument" >&2
        exit 1
      fi
      COMPLETION_PROMISE="$2"
      shift 2
      ;;
    *)
      PROMPT_PARTS+=("$1")
      shift
      ;;
  esac
done

# Join all prompt parts
PROMPT="${PROMPT_PARTS[*]:-}"

if [[ -z "$PROMPT" ]]; then
  echo "Error: No prompt provided" >&2
  echo "" >&2
  echo "  Examples:" >&2
  echo "    /maher-loop:go Build a REST API for todos" >&2
  echo "    /maher-loop:go Fix the auth bug --max-iterations 20" >&2
  echo "" >&2
  echo "  For all options: /maher-loop:go --help" >&2
  exit 1
fi

# Check for existing active loop
if [[ -f .claude/maher-loop.local.md ]]; then
  EXISTING_ITER=$(sed -n '/^---$/,/^---$/{ /^---$/d; p; }' .claude/maher-loop.local.md | grep '^iteration:' | sed 's/iteration: *//')
  echo "Error: Maher loop already active (iteration ${EXISTING_ITER:-?})" >&2
  echo "  Run /maher-loop:cancel-maher first, or delete .claude/maher-loop.local.md" >&2
  exit 1
fi

# Create state directory
mkdir -p .claude

# Escape completion promise for safe YAML embedding
# Replace internal double quotes with escaped versions
if [[ -n "$COMPLETION_PROMISE" ]] && [[ "$COMPLETION_PROMISE" != "null" ]]; then
  ESCAPED_PROMISE="${COMPLETION_PROMISE//\"/\\\"}"
  COMPLETION_PROMISE_YAML="\"$ESCAPED_PROMISE\""
else
  COMPLETION_PROMISE_YAML="null"
fi

# Create state file using quoted heredoc to prevent expansion of prompt content.
# Frontmatter fields are written separately via sed to inject variables safely.
cat > .claude/maher-loop.local.md <<'STATEEOF'
---
active: true
iteration: 1
session_id: __SESSION_ID__
max_iterations: __MAX_ITER__
completion_promise: __PROMISE__
started_at: "__STARTED__"
---

STATEEOF
# Append prompt as literal text (no expansion)
printf '%s\n' "$PROMPT" >> .claude/maher-loop.local.md
# Replace placeholders with actual values
STARTED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)
sed -i "s|__SESSION_ID__|${CLAUDE_CODE_SESSION_ID:-}|" .claude/maher-loop.local.md
sed -i "s|__MAX_ITER__|$MAX_ITERATIONS|" .claude/maher-loop.local.md
sed -i "s|__PROMISE__|$COMPLETION_PROMISE_YAML|" .claude/maher-loop.local.md
sed -i "s|__STARTED__|$STARTED_AT|" .claude/maher-loop.local.md

# Save original prompt for reference (never modified)
{
  echo "# Maher Loop - Original Prompt"
  echo ""
  printf '**Started:** %s\n' "$STARTED_AT"
  echo ""
  printf '%s\n' "$PROMPT"
} > .claude/maher-loop-original.local.md

# Initialize history file
{
  echo "# Maher Loop Refinement History"
  echo ""
  echo "**Original prompt:**"
  printf '%s\n' "$PROMPT"
  echo ""
  echo "---"
} > .claude/maher-loop-history.local.md

# Output setup message
cat <<'MSGEOF'
Maher loop activated!
MSGEOF

echo ""
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

cat <<'MSGEOF'

Unlike Ralph which repeats the SAME prompt, Maher Loop REFINES the prompt
each iteration. At the end of each iteration, output a <refine> block to
sharpen the prompt for the next round.

Files created:
  .claude/maher-loop.local.md          (active state + current prompt)
  .claude/maher-loop-original.local.md (original prompt, read-only)
  .claude/maher-loop-history.local.md  (refinement log)

MSGEOF

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
