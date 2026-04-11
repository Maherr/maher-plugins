---
description: "Start Maher Loop with prompt refinement"
argument-hint: "PROMPT [--max-iterations N] [--completion-promise TEXT]"
allowed-tools: ["Bash(${CLAUDE_PLUGIN_ROOT}/scripts/setup-maher-loop.sh:*)"]
hide-from-slash-command-tool: "true"
---

# Maher Loop Command

Execute the setup script to initialize the Maher loop:

```!
"${CLAUDE_PLUGIN_ROOT}/scripts/setup-maher-loop.sh" <<MAHER_LOOP_ARGS_EOF
$ARGUMENTS
MAHER_LOOP_ARGS_EOF
```

On iteration 1 only, before doing any work, output this exact line to confirm the loop started:

**Maher Loop started — iteration 1. Working on it.**

You are now in a Maher Loop. This is an iterative loop where you work on a task across multiple iterations. The stop hook will block your exit and feed a prompt back to you.

## MANDATORY END-OF-ITERATION PROTOCOL

You MUST end EVERY iteration with one of the following. This is not optional. If you skip this, the loop breaks.

### If work remains — output a refine block:

<refine>
What was accomplished this iteration. What remains to be done.
Specific next steps with details learned. Constraints discovered.
Files touched: [list every file created, modified, or deleted]
This becomes the COMPLETE prompt for the next iteration.
</refine>

### If you think you are done — DO NOT output promise yet. Enter sweep mode:

You are NEVER allowed to output `<promise>` in the same iteration where you did the work. When you believe the task is complete, you MUST output a refine block that triggers a **sweep iteration**:

<refine>
SWEEP MODE: All work is believed complete. This is a convergence sweep.

Files touched during this loop: [list ALL files created or modified across all iterations]

Instructions for this sweep iteration:
1. Re-read EVERY file listed above end-to-end (not just targeted greps — full reads catch what you don't think to look for)
2. Cross-check numbers, counts, prices, and references between files for consistency
3. Look for: stale data, duplicate sections, broken cross-references, arithmetic errors, outdated claims
4. Verify every deliverable from the original task exists and meets requirements

If ANY issues are found: fix them and output another <refine> with SWEEP MODE again.
If ZERO issues found: output a <refine> with CLEAN SWEEP to trigger the verification pass.
</refine>

### After a clean sweep — trigger the verification pass:

<refine>
CLEAN SWEEP: Zero issues found in the previous sweep. This is the verification pass.

Re-read the key output files one more time. Confirm nothing was broken by previous sweep fixes.
If still clean: output the completion promise.
If any issues: fix and return to SWEEP MODE.
</refine>

### Only in a verification pass — if everything confirmed clean:

<promise>EXACT_PROMISE_TEXT</promise>

### Rules:

- You MUST output either a `<refine>` block OR a `<promise>` tag at the very end of your response when doing loop work. The `<refine>` and `<promise>` tags must appear in your TEXT output, not inside tool calls or code blocks.
- **⚠️ CRITICAL: The stop hook ONLY matches LITERAL XML TAGS with angle brackets.** Writing `DONE` or `**DONE**` or `## DONE` or any other plain-text/markdown variant DOES NOTHING. You must write the exact string `<promise>DONE</promise>` (or whatever the configured completion phrase is) with the angle brackets visible in your output. If the loop has looped 2+ iterations with the same refined prompt and you keep writing "DONE" and nothing happens, CHECK your output — you are almost certainly missing the `<promise></promise>` angle brackets. Fix by typing the literal characters `<`, `p`, `r`, `o`, `m`, `i`, `s`, `e`, `>`, `D`, `O`, `N`, `E`, `<`, `/`, `p`, `r`, `o`, `m`, `i`, `s`, `e`, `>`.
- **NEVER output `<promise>` in an iteration where you created, wrote, or fixed anything.** Always refine into a sweep iteration first.
- `<promise>` is ONLY allowed after TWO consecutive clean passes (one sweep + one verification) where you verified everything and changed nothing.
- Each `<refine>` must be self-contained. The next iteration only sees the refined prompt, not the previous one.
- If this is iteration 1, you almost certainly need a `<refine>` block, not a promise.
- **The loop runs autonomously to completion.** Do not stop mid-loop to ask for user confirmation, check in, or pause for conversation. Drive the work forward through sweep → verification → promise without asking permission. The user should only see the final result.
- **If the user sends a message mid-loop**, treat it as context for the loop work, not as a reason to stop. Continue driving to completion. The user can explicitly stop the loop with `/maher-loop:cancel-maher` if they need to interrupt — do not try to infer "the user wants to pause" from conversational messages.
- **Always output a `<refine>` or `<promise>` tag** at the end of every response while the loop is active. If you don't, the loop re-feeds the current prompt to force forward progress.

### What makes a good refine block:

1. Remove completed work so the next iteration does not redo it
2. Sharpen remaining tasks with specifics learned this iteration
3. Add discovered constraints, blockers, or insights
4. Adjust strategy if the current approach is not working
5. Include enough context for the next iteration to continue without history
6. Always include `Files touched:` so sweep iterations know what to cross-check

### Task tracking for complex work:

For tasks with 3 or more distinct steps, use TaskCreate at the start of iteration 1 to decompose the work into trackable items. Update task statuses as you progress (in_progress when starting a step, completed when done). During sweep mode, use the task list as your verification checklist. For simple or short tasks, skip this — the overhead isn't worth it.

### Use agents aggressively for complex work:

For research, multi-angle investigations, debugging, or whenever sequential thinking has stalled, launch multiple agents in parallel using the Agent tool. Spawn agents for independent sub-questions (different search queries, different hypotheses, different code areas) and synthesize their results in the main context. A stuck loop burning iterations of sequential guessing costs far more than parallel agents that resolve the problem in one iteration. Don't delegate understanding — agents gather, you synthesize. **Important: always run agents in the foreground (the default) during a loop — never use `run_in_background: true`, because the stop hook may fire before background agents return, losing their results.**

### Rate-limited APIs:

When using rate-limited external APIs (Consensus, web search, etc.), call them **sequentially, not in parallel**. Parallel calls frequently hit rate limits and waste iterations on retries.

## Reference Files

Each loop gets a unique ID. Files are named with that ID:

- `.claude/maher-loop-{ID}.local.md` - Active state file with current prompt
- `.claude/maher-loop-{ID}-original.local.md` - Original prompt (never changes)
- `.claude/maher-loop-{ID}-history.local.md` - Log of all prompt refinements
