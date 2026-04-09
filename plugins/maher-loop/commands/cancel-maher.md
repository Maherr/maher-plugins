---
description: "Cancel active Maher Loop"
allowed-tools: ["Bash(ls .claude/maher-loop-*.local.md:*)", "Bash(rm .claude/maher-loop-*:*)", "Bash(test -f:*)", "Bash(grep:*)", "Bash(cat:*)", "Read"]
hide-from-slash-command-tool: "true"
---

# Cancel Maher Loop

To cancel Maher loop(s):

1. List active state files using Bash: `ls .claude/maher-loop-*.local.md 2>/dev/null | grep -v history | grep -v original`

2. **If no files found**: Say "No active Maher loops found."

3. **If one or more files found**:
   - For each state file, read the frontmatter to get the `iteration:`, `loop_id:`, `session_id:`, and `started_at:` fields
   - Report each loop: "Loop {loop_id} — iteration N, started {time}, session {session_id}"
   - Remove ALL state files using Bash: `rm .claude/maher-loop-*.local.md` (this removes state + history + original files for all loops)
   - If the user only wants to cancel a specific loop, remove just that loop's files: `rm .claude/maher-loop-{ID}.local.md .claude/maher-loop-{ID}-history.local.md .claude/maher-loop-{ID}-original.local.md`
   - Report: "Cancelled N Maher loop(s)"
