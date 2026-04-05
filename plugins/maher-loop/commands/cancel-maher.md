---
description: "Cancel active Maher Loop"
allowed-tools: ["Bash(test -f .claude/maher-loop.local.md:*)", "Bash(rm .claude/maher-loop.local.md)", "Read(.claude/maher-loop.local.md)", "Read(.claude/maher-loop-history.local.md)"]
hide-from-slash-command-tool: "true"
---

# Cancel Maher Loop

To cancel the Maher loop:

1. Check if `.claude/maher-loop.local.md` exists using Bash: `test -f .claude/maher-loop.local.md && echo "EXISTS" || echo "NOT_FOUND"`

2. **If NOT_FOUND**: Say "No active Maher loop found."

3. **If EXISTS**:
   - Read `.claude/maher-loop.local.md` to get the current iteration number from the `iteration:` field
   - Read `.claude/maher-loop-history.local.md` to see how many refinements occurred
   - Remove the state file using Bash: `rm .claude/maher-loop.local.md`
   - Report: "Cancelled Maher loop at iteration N (M prompt refinements)" where N is the iteration and M is the number of refinement entries in the history file
   - Note: The history file and original prompt file are preserved for reference
