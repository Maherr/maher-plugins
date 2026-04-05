# Cloud Loop Plugin

Iterative AI loop with **prompt refinement** for Claude Code. An evolution of the Ralph Wiggum technique where the prompt evolves each iteration.

## Ralph vs Cloud

| Feature | Ralph Loop | Cloud Loop |
|---------|-----------|------------|
| Prompt between iterations | Same every time | Refined each iteration |
| Completed work tracking | Via file changes only | Removed from prompt |
| Discovery incorporation | Implicit (file state) | Explicit (in refined prompt) |
| Convergence speed | Linear | Accelerating (prompt sharpens) |
| Best for | Verification sweeps | Exploratory/multi-step tasks |

## Quick Start

```bash
/cloud-loop "Build a REST API for todos with CRUD, validation, and tests" --completion-promise "DONE" --max-iterations 15
```

Claude will:
1. Work on the task
2. Output a `<refine>` block with an improved prompt
3. Stop hook extracts the refinement
4. Next iteration receives the sharpened prompt
5. Repeat until completion promise or max iterations

## How Refinement Works

At the end of each iteration, Claude outputs:

```
<refine>
Improved prompt with:
- Completed items removed
- New discoveries added
- Remaining tasks sharpened
- Strategy adjusted based on this iteration
</refine>
```

The stop hook in `hooks/stop-hook.sh` extracts this block and updates the state file. If no `<refine>` block is output, the same prompt repeats (Ralph behavior).

## Commands

- `/cloud-loop <prompt> [--max-iterations N] [--completion-promise TEXT]` - Start loop
- `/cancel-cloud` - Cancel active loop
- `/cloud-help` - Show help

## Files

During a loop, these files are created in `.claude/`:

| File | Purpose |
|------|---------|
| `cloud-loop.local.md` | Active state + current prompt (updated each iteration) |
| `cloud-loop-original.local.md` | Original prompt (never modified) |
| `cloud-loop-history.local.md` | Log of every prompt refinement |

## Architecture

Same Stop hook mechanism as Ralph:

```
Claude works → tries to exit → stop hook fires → checks for:
  1. <promise> tag → stop loop
  2. <refine> tag → update prompt (CLOUD INNOVATION)
  3. Max iterations → stop loop
  4. Otherwise → block exit, feed prompt back
```

## Safety

- Always use `--max-iterations` as a safety net
- `--completion-promise` requires exact match in `<promise>` tags
- Session-isolated: only the originating session triggers the hook
- History file preserves the full refinement trajectory for debugging
