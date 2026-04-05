#!/bin/bash

# Cloud Loop Setup Script
# Creates state file for in-session Cloud loop with prompt refinement

set -euo pipefail

# Parse arguments
PROMPT_PARTS=()
MAX_ITERATIONS=0
COMPLETION_PROMISE="null"

while [[ $# -gt 0 ]]; do
  case $1 in
    -h|--help)
      cat << 'HELP_EOF'
Cloud Loop - Iterative loop with prompt refinement

USAGE:
  /cloud-loop [PROMPT...] [OPTIONS]

ARGUMENTS:
  PROMPT...    Initial prompt to start the loop (can be multiple words without quotes)

OPTIONS:
  --max-iterations <n>           Maximum iterations before auto-stop (default: unlimited)
  --completion-promise '<text>'  Promise phrase (USE QUOTES for multi-word)
  -h, --help                     Show this help message

DESCRIPTION:
  Like Ralph Loop, but the prompt EVOLVES each iteration. At the end of each
  iteration, Claude outputs a <refine> block with an improved prompt that
  incorporates what was learned, removes completed work, and sharpens focus.

  To signal completion, output: <promise>YOUR_PHRASE</promise>
  To refine the prompt, output: <refine>IMPROVED_PROMPT</refine>

EXAMPLES:
  /cloud-loop Build a todo API --completion-promise 'DONE' --max-iterations 20
  /cloud-loop --max-iterations 10 Investigate and fix the auth bug
  /cloud-loop Research best practices for caching --completion-promise 'RESEARCH_COMPLETE'

STOPPING:
  Only by reaching --max-iterations or detecting --completion-promise.
  No manual stop - Cloud runs infinitely by default!

MONITORING:
  # View current iteration:
  grep '^iteration:' .claude/cloud-loop.local.md

  # View current (refined) prompt:
  awk '/^---$/{i++; next} i>=2' .claude/cloud-loop.local.md

  # View refinement history:
  cat .claude/cloud-loop-history.local.md
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
  echo "    /cloud-loop Build a REST API for todos" >&2
  echo "    /cloud-loop Fix the auth bug --max-iterations 20" >&2
  echo "" >&2
  echo "  For all options: /cloud-loop --help" >&2
  exit 1
fi

# Create state directory
mkdir -p .claude

# Quote completion promise for YAML
if [[ -n "$COMPLETION_PROMISE" ]] && [[ "$COMPLETION_PROMISE" != "null" ]]; then
  COMPLETION_PROMISE_YAML="\"$COMPLETION_PROMISE\""
else
  COMPLETION_PROMISE_YAML="null"
fi

# Create state file
cat > .claude/cloud-loop.local.md <<EOF
---
active: true
iteration: 1
session_id: ${CLAUDE_CODE_SESSION_ID:-}
max_iterations: $MAX_ITERATIONS
completion_promise: $COMPLETION_PROMISE_YAML
started_at: "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
---

$PROMPT
EOF

# Save original prompt for reference (never modified)
cat > .claude/cloud-loop-original.local.md <<EOF
# Cloud Loop - Original Prompt

**Started:** $(date -u +%Y-%m-%dT%H:%M:%SZ)

$PROMPT
EOF

# Initialize history file
cat > .claude/cloud-loop-history.local.md <<EOF
# Cloud Loop Refinement History

**Original prompt:**
$PROMPT

---
EOF

# Output setup message
cat <<EOF
Cloud loop activated!

Iteration: 1
Max iterations: $(if [[ $MAX_ITERATIONS -gt 0 ]]; then echo $MAX_ITERATIONS; else echo "unlimited"; fi)
Completion promise: $(if [[ "$COMPLETION_PROMISE" != "null" ]]; then echo "${COMPLETION_PROMISE//\"/} (ONLY output when TRUE)"; else echo "none (runs forever)"; fi)

Unlike Ralph which repeats the SAME prompt, Cloud Loop REFINES the prompt
each iteration. At the end of each iteration, output a <refine> block to
sharpen the prompt for the next round.

Files created:
  .claude/cloud-loop.local.md          (active state + current prompt)
  .claude/cloud-loop-original.local.md (original prompt, read-only)
  .claude/cloud-loop-history.local.md  (refinement log)

EOF

echo "$PROMPT"

# Display completion and refinement instructions
if [[ "$COMPLETION_PROMISE" != "null" ]]; then
  echo ""
  echo "==========================================================="
  echo "CLOUD LOOP - Completion & Refinement Protocol"
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
  echo "CLOUD LOOP - Refinement Protocol"
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
