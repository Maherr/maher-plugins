---
description: "Start Maher Loop with prompt refinement"
argument-hint: "PROMPT [--max-iterations N] [--completion-promise TEXT]"
allowed-tools: ["Bash(${CLAUDE_PLUGIN_ROOT}/scripts/setup-maher-loop.sh:*)"]
hide-from-slash-command-tool: "true"
---

# Maher Loop Command

Execute the setup script to initialize the Maher loop:

```!
"${CLAUDE_PLUGIN_ROOT}/scripts/setup-maher-loop.sh" $ARGUMENTS
```

You are now in a Maher Loop. This is an iterative loop where you work on a task across multiple iterations. The stop hook will block your exit and feed a prompt back to you.

## MANDATORY END-OF-ITERATION PROTOCOL

You MUST end EVERY iteration with one of the following. This is not optional. If you skip this, the loop breaks.

### If work remains — output a refine block:

<refine>
What was accomplished this iteration. What remains to be done.
Specific next steps with details learned. Constraints discovered.
This becomes the COMPLETE prompt for the next iteration.
</refine>

### If genuinely done — output the promise tag:

<promise>EXACT_PROMISE_TEXT</promise>

### Rules:

- You MUST output either a `<refine>` block OR a `<promise>` tag at the very end of your response. EVERY iteration. No exceptions.
- The `<refine>` and `<promise>` tags must appear in your TEXT output, not inside tool calls or code blocks.
- Do NOT just say "done" or "complete" in plain text. The stop hook ONLY reads XML tags. Plain text like "All done!" does NOTHING.
- Do NOT output `<promise>` in the same iteration where you fixed issues. Wait for a clean verification pass.
- Each `<refine>` must be self-contained. The next iteration only sees the refined prompt, not the previous one.
- If this is iteration 1, you almost certainly need a `<refine>` block, not a promise.

### What makes a good refine block:

1. Remove completed work so the next iteration does not redo it
2. Sharpen remaining tasks with specifics learned this iteration
3. Add discovered constraints, blockers, or insights
4. Adjust strategy if the current approach is not working
5. Include enough context for the next iteration to continue without history

## Reference Files

- `.claude/maher-loop.local.md` - Active state file with current prompt
- `.claude/maher-loop-original.local.md` - Original prompt (never changes)
- `.claude/maher-loop-history.local.md` - Log of all prompt refinements
