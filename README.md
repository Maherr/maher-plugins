# Maher Plugins

Claude Code plugins by Maher Bouhdid.

## Plugins

| Plugin | Description |
|--------|-------------|
| [maher-loop](plugins/maher-loop/) | Iterative AI loop with prompt refinement |

## Installation

```bash
/plugin marketplace add Maherr/maher-plugins
/plugin install maher-loop@maher-plugins
```

Or browse in `/plugin > Discover`.

## Structure

```
maher-plugins/
├── .claude-plugin/
│   └── marketplace.json    # Plugin registry
├── plugins/
│   └── maher-loop/         # Iterative loop with prompt refinement
│       ├── .claude-plugin/
│       │   └── plugin.json
│       ├── commands/
│       ├── hooks/
│       ├── scripts/
│       └── README.md
├── LICENSE
└── README.md
```

## Plugin Details

### Maher Loop

An evolution of the [Ralph Wiggum technique](https://ghuntley.com/ralph/) where the prompt **refines itself** each iteration instead of staying static.

Ralph feeds Claude the same prompt every time. Maher Loop adds a `<refine>` mechanism — at the end of each iteration, Claude outputs an improved version of the prompt that removes completed work, sharpens remaining tasks, and captures discoveries. The stop hook extracts it and feeds it back for the next round.

**Quick start:**

```bash
/maher-loop:maher-loop Build a REST API with tests --completion-promise DONE --max-iterations 15
```

See [plugins/maher-loop/README.md](plugins/maher-loop/README.md) for full documentation.

## Contributing

This is a personal plugin marketplace. Plugins are developed by Maher Bouhdid.

## License

MIT
