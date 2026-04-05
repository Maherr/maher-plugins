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

Please work on the task. Unlike Ralph which feeds the SAME prompt every time, Maher Loop REFINES the prompt each iteration based on what you learn.

## How Prompt Refinement Works

At the END of each iteration, after completing your work, output a `<refine>` block containing an improved version of the prompt for the next iteration. The stop hook extracts it and feeds it back instead of the original.

### Writing the refine Block

```
<refine>
Your refined prompt here. This becomes the FULL prompt for the next iteration.
</refine>
```

### What to Include in Refined Prompts

1. **Preserve the core objective** - Never lose sight of the original goal
2. **Remove completed work** - Cross off what is done so you do not redo it
3. **Sharpen remaining tasks** - Be more specific about what is left
4. **Incorporate discoveries** - Add constraints, blockers, or insights learned this iteration
5. **Adjust strategy** - If an approach is not working, pivot
6. **Be self-contained** - The next iteration only sees the refined prompt, not the previous one

### Example Prompt Evolution

**Iteration 1 receives:** "Build a REST API for todos with CRUD, validation, and tests"

After iteration 1, Claude creates structure and basic routes, then outputs:

```
<refine>
Continue building the REST API for todos. Project structure is in place at src/api/.
Basic CRUD routes exist but need: 1. Input validation middleware for POST/PUT, 2. Integration tests for all 4 endpoints, 3. Error handling for non-existent IDs returning 404.
Discovered: Using Express 5 which changed Router API - use express.Router not express.router.
</refine>
```

After iteration 2, validation is done, some tests pass:

```
<refine>
REST API nearly complete. Validation working. Two issues remain:
1. DELETE /todos/:id returns 500 instead of 404 for non-existent IDs - the findById call needs a try/catch
2. No test for concurrent PUT requests - add a test that sends 2 PUTs simultaneously
All other tests passing. Fix these two items then verify all tests green.
</refine>
```

### When NOT to Refine

If the current prompt is already optimal and nothing new was learned, skip the `<refine>` block. The same prompt will repeat (Ralph behavior). This is fine for early iterations where you are still exploring.

## Critical Rules

1. **Completion promise**: If a completion promise is set, you may ONLY output it when the statement is completely and unequivocally TRUE. Do not output false promises to escape the loop.

2. **No promise after fixes**: Do NOT output the completion promise in the same iteration where you fixed issues. End without a promise, let the loop re-trigger, verify everything is clean, THEN output the promise.

3. **Refine block placement**: The `<refine>` block should be the LAST thing you output (before any `<promise>` tag if completing). The stop hook extracts it from your final text output.

4. **Self-contained refinements**: Each refined prompt must stand alone. The next iteration does not see the previous prompt - only the refined one. Include enough context to continue without prior history.

5. **Do not refine AND promise simultaneously**: If you are outputting a `<promise>` tag because the work is genuinely done, you do not need a `<refine>` block. The loop will end.

## Reference Files

- `.claude/maher-loop.local.md` - Active state file with current prompt
- `.claude/maher-loop-original.local.md` - Original prompt (never changes)
- `.claude/maher-loop-history.local.md` - Log of all prompt refinements
