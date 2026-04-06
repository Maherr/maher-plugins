---
description: "Explain Maher Loop plugin and available commands"
---

# Maher Loop Plugin Help

Please explain the following to the user:

## What is Maher Loop?

Maher Loop is an evolution of the Ralph Wiggum technique. Like Ralph, it runs Claude in an iterative loop using a Stop hook. The key difference: **the prompt evolves each iteration**.

**Ralph Loop:** Same prompt every time. Claude sees file changes but gets identical instructions.

**Maher Loop:** Prompt refines itself. Claude outputs a `<refine>` block at the end of each iteration, and the stop hook feeds the improved prompt back for the next round.

### Why Prompt Refinement Matters

- **Removes completed work** so Claude does not waste time re-reading or re-doing finished tasks
- **Sharpens focus** on what actually remains, with specifics learned from attempting it
- **Captures discoveries** like constraints, bugs, or approach changes that the original prompt could not have known
- **Reduces drift** by giving Claude a clear, updated picture instead of a stale original prompt
- **Converges faster** because each iteration starts from a more informed position

### How It Works

```
Iteration 1: Claude receives original prompt, works, outputs <refine> block
Iteration 2: Claude receives refined prompt, works, outputs <refine> block (review mode)
Iteration 3: Claude verifies everything, outputs <promise>DONE</promise> (done!)
```

Each `<refine>` block becomes the FULL prompt for the next iteration. The stop hook extracts it automatically.

If Claude skips the `<refine>` block, the same prompt repeats (Ralph behavior). This graceful fallback means Maher Loop works even if refinement is not needed every iteration.

### Mandatory Review Mode

When Claude thinks it is done, it cannot immediately output `<promise>`. It must first refine into a review iteration where it re-reads files, re-checks requirements, and verifies outputs. Only after a clean review pass (nothing changed) can it output the completion promise.

## Available Commands

### /maher-loop:go <PROMPT> [OPTIONS]

Start a Maher loop in your current session.

**Usage:**
```
/maher-loop:go Refactor the cache layer
/maher-loop:go Add tests --completion-promise 'TESTS_COMPLETE' --max-iterations 10
```

**Options:**
- `--max-iterations <n>` - Max iterations before auto-stop (default: 99)
- `--completion-promise <text>` - Promise phrase to signal completion (default: DONE)

**Files created:**
- `.claude/maher-loop.local.md` - Active state with current prompt
- `.claude/maher-loop-original.local.md` - Original prompt (preserved)
- `.claude/maher-loop-history.local.md` - Refinement log

### /maher-loop:cancel-maher

Cancel an active Maher loop. Preserves history and original prompt files for reference.

## Key Concepts

### Prompt Refinement with refine Tags

At the end of each iteration, Claude outputs:
```
<refine>
Improved prompt with completed items removed, new discoveries added,
and remaining tasks sharpened based on this iteration's work.
</refine>
```

The stop hook extracts this and uses it as the next prompt.

### Completion Promises

Output `<promise>YOUR_PHRASE</promise>` when genuinely done (default phrase: DONE).

### Refinement History

Every refinement is logged to `.claude/maher-loop-history.local.md` so you can trace how the prompt evolved. Useful for debugging and understanding the problem-solving trajectory.

## When to Use Maher Loop vs Ralph

**Use Maher Loop when:**
- Tasks are exploratory or research-heavy (prompt needs to adapt to findings)
- Multi-step tasks where early steps inform later ones
- Debugging where the problem definition sharpens as you investigate
- Any task longer than 3-4 iterations (prompt staleness becomes costly)

**Use Ralph when:**
- Simple verification/sweep loops (same check repeated)
- The prompt is already perfect and self-correcting
- You want maximum simplicity

## Example

### Adaptive Bug Investigation

```
/maher-loop:go Investigate why the payment endpoint returns 500 errors intermittently. Check logs, trace the request path, identify the root cause, and fix it.
```

Maher Loop will:
- Iteration 1: Check logs, find error pattern, refine prompt to focus on specific error
- Iteration 2: Trace the specific code path identified, discover race condition, refine to target fix
- Iteration 3: Implement fix, refine to focus on testing the fix
- Iteration 4: Verify fix works, enter review mode
- Iteration 5: Clean review pass, output promise
