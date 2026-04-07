# Maher Loop Plugin

Iterative AI loop with **prompt refinement**, **built-in sweep protocol**, and **two-pass verification** for Claude Code. An evolution of the Ralph Wiggum technique where the prompt evolves each iteration and quality sweeps are built in.

## Ralph vs Maher

| Feature | Ralph Loop | Maher Loop |
|---------|-----------|------------|
| Prompt between iterations | Same every time | Refined each iteration |
| Completed work tracking | Via file changes only | Removed from prompt |
| Discovery incorporation | Implicit (file state) | Explicit (in refined prompt) |
| Convergence speed | Linear | Accelerating (prompt sharpens) |
| File tracking | No | Yes (`Files touched:` in every refine) |
| Quality sweeps | No (must launch separately) | Built-in (sweep + verification) |
| Review before completion | No | Yes (two consecutive clean passes required) |

## Installation

```bash
/plugin marketplace add Maherr/maher-plugins
/plugin install maher-loop@maher-plugins
```

## Quick Start

```bash
/maher-loop:go Build a REST API for todos with CRUD, validation, and tests
```

Claude will:
1. Work on the task
2. Output a `<refine>` block with an improved prompt (including `Files touched:`)
3. Stop hook extracts the refinement
4. Next iteration receives the sharpened prompt
5. When done, enters **SWEEP MODE** — re-reads all modified files end-to-end
6. After clean sweep, enters **verification pass** (second clean check)
7. After two consecutive clean passes, outputs completion promise
8. Loop exits

Default settings: `--completion-promise DONE --max-iterations 99`

## How Refinement Works

At the end of each iteration, Claude outputs:

```
<refine>
Improved prompt with:
- Completed items removed
- New discoveries added
- Remaining tasks sharpened
- Strategy adjusted based on this iteration
Files touched: [list of files modified this iteration]
</refine>
```

The stop hook in `hooks/stop-hook.sh` extracts this block and updates the state file. If no `<refine>` block is output, the same prompt repeats (Ralph behavior).

## Built-in Sweep Protocol

When Claude believes the task is complete, it enters a multi-phase end sequence instead of immediately exiting:

### Phase 1: Sweep Mode
Claude re-reads **every modified file end-to-end** (not just targeted greps). Cross-checks numbers, references, and data between files. Looks for stale data, duplicate sections, arithmetic errors, and broken cross-references. The `Files touched:` list from refine blocks tells the sweep exactly what to check.

### Phase 2: Clean Sweep
If the sweep found zero issues, Claude outputs a `CLEAN SWEEP` refine to trigger the verification pass.

### Phase 3: Verification Pass
One final re-read of key output files to confirm that any fixes made during sweep didn't introduce new issues. Only after this second consecutive clean pass can Claude output `<promise>DONE</promise>`.

If issues are found at any phase, Claude fixes them and returns to Sweep Mode. This creates a convergence loop that runs until the output is genuinely clean.

**Why this matters:** In practice, review iterations that only check what you think to look for miss issues that full file re-reads catch (stale data, duplicate sections, inconsistent numbers between files). The sweep protocol was added after observing that a separate Ralph Loop sweep consistently found 5-10 additional issues after Maher Loop's original review mode declared "done."

## Rate-Limited APIs

When using rate-limited external APIs (Consensus, web search, etc.), the loop instructions advise calling them **sequentially, not in parallel**. Parallel calls frequently hit rate limits and waste iterations on retries.

## Commands

- `/maher-loop:go <prompt> [--max-iterations N] [--completion-promise TEXT]` - Start loop
- `/maher-loop:cancel-maher` - Cancel active loop
- `/maher-loop:help` - Show help

## Files

During a loop, these files are created in `.claude/`:

| File | Purpose |
|------|---------|
| `maher-loop.local.md` | Active state + current prompt (updated each iteration) |
| `maher-loop-original.local.md` | Original prompt (never modified) |
| `maher-loop-history.local.md` | Log of every prompt refinement |

## Architecture

Same Stop hook mechanism as Ralph:

```
Claude works -> tries to exit -> stop hook fires -> checks for:
  1. <promise> tag -> stop loop
  2. <refine> tag -> update prompt
  3. Max iterations -> stop loop
  4. Otherwise -> block exit, feed prompt back
```

## Safety

- Default `--max-iterations 99` as a safety net
- Default `--completion-promise DONE` requires exact match in `<promise>` tags
- Session-isolated: only the originating session triggers the hook
- History file preserves the full refinement trajectory for debugging
- Existing loop check prevents accidental overwrites
- Race condition retry limit (5 retries) prevents infinite retry loops
