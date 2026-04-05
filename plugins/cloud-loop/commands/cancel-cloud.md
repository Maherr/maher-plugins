---
description: "Cancel active Cloud Loop"
allowed-tools: ["Bash(test -f .claude/cloud-loop.local.md:*)", "Bash(rm .claude/cloud-loop.local.md)", "Read(.claude/cloud-loop.local.md)", "Read(.claude/cloud-loop-history.local.md)"]
hide-from-slash-command-tool: "true"
---

# Cancel Cloud Loop

To cancel the Cloud loop:

1. Check if `.claude/cloud-loop.local.md` exists using Bash: `test -f .claude/cloud-loop.local.md && echo "EXISTS" || echo "NOT_FOUND"`

2. **If NOT_FOUND**: Say "No active Cloud loop found."

3. **If EXISTS**:
   - Read `.claude/cloud-loop.local.md` to get the current iteration number from the `iteration:` field
   - Read `.claude/cloud-loop-history.local.md` to see how many refinements occurred
   - Remove the state file using Bash: `rm .claude/cloud-loop.local.md`
   - Report: "Cancelled Cloud loop at iteration N (M prompt refinements)" where N is the iteration and M is the number of refinement entries in the history file
   - Note: The history file and original prompt file are preserved for reference
