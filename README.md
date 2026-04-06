# Maher Plugins

A Claude Code plugin marketplace by [Maher Bouhdid](https://github.com/maherbouhdid).

## Plugins

### Maher Loop

**Iterative AI loop with prompt refinement for Claude Code.**

An evolution of the [Ralph Wiggum technique](https://ghuntley.com/ralph/) where the prompt evolves each iteration instead of staying static.

#### The Problem with Static Prompts

Ralph Loop feeds Claude the **same prompt** every iteration. This works for simple verification sweeps, but for complex tasks — research, multi-step builds, debugging — the prompt becomes stale fast. Claude wastes tokens re-reading completed work and lacks context about what it discovered along the way.

#### The Fix: Self-Refining Prompts

Maher Loop adds a `<refine>` mechanism. At the end of each iteration, Claude outputs a refined version of the prompt that:

- **Removes completed work** so it's not re-read or re-done
- **Sharpens remaining tasks** with specifics learned from attempting them
- **Captures discoveries** — constraints, bugs, approach changes the original prompt couldn't have known
- **Adjusts strategy** when something isn't working

The stop hook extracts the `<refine>` block and feeds it as the next iteration's prompt. Each round starts from a more informed position.

#### Example: How the Prompt Evolves

```
Iteration 1 prompt:
  "Build a REST API for todos with CRUD, validation, and tests"

Iteration 2 prompt (after Claude built the skeleton):
  "Continue todo API. Structure at src/api/. Remaining: validation
   middleware for POST/PUT, integration tests for 4 endpoints,
   404 handling for missing IDs. Note: Express 5 Router API changed."

Iteration 3 prompt (after validation done, one test failing):
  "Fix DELETE /todos/:id — returns 500 not 404 for missing IDs.
   Add concurrent PUT test. All other tests green."
```

Each iteration is shorter, sharper, and more focused than the last.

#### Quick Start

Install:

```bash
# In Claude Code
/plugin marketplace add github:maherbouhdid/maher-plugins
/plugin install maher-loop@maher-plugins
```

Use:

```bash
/maher-loop Build a REST API with auth and tests --completion-promise DONE --max-iterations 15
```

#### Options

| Flag | Description |
|------|-------------|
| `--max-iterations <n>` | Safety limit. Always set this. |
| `--completion-promise '<text>'` | Exact phrase Claude outputs in `<promise>` tags when genuinely done |

#### Commands

| Command | Description |
|---------|-------------|
| `/maher-loop <prompt> [options]` | Start a loop |
| `/cancel-maher` | Cancel active loop |
| `/maher-loop:help` | Show documentation |

#### When to Use Maher Loop vs Ralph

| Maher Loop | Ralph Loop |
|------------|------------|
| Exploratory / research tasks | Verification sweeps |
| Multi-step builds where early steps inform later ones | Same check repeated each pass |
| Debugging where the problem sharpens as you dig | Prompt is already perfect |
| Anything beyond 3-4 iterations | Quick 1-3 iteration jobs |

#### How It Works

Same Stop hook architecture as Ralph, with one addition:

```
Claude works → tries to exit → stop hook fires:
  1. Check for <promise> tag → stop loop if found
  2. Check for <refine> tag → update prompt if found ← new
  3. Check max iterations → stop if reached
  4. Block exit, feed current prompt back
```

All refinements are logged to `.claude/maher-loop-history.local.md` so you can trace how the prompt evolved.

#### Shell Safety

Same rules as Ralph — avoid these characters in prompts:

- Parentheses `()`, dollar signs `$`, backticks `` ` ``
- Curly braces `{}`, exclamation marks `!`
- Quotes within quotes

## License

MIT
