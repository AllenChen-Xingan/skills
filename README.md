# Skills

My public collection of agent skills for [Claude Code](https://claude.com/claude-code), shared for anyone to use, adapt and learn from.

Each skill lives in its own folder under [`skills/`](skills/): a `SKILL.md` with the instructions Claude follows, plus any `references/` or `scripts/` it loads on demand. Supporting material such as reading lists lives in [`resources/`](resources/).

## Install

Copy a skill folder into your personal skills directory, or into a project's `.claude/skills/` to scope it to that project:

```bash
git clone https://github.com/AllenChen-Xingan/skills.git
cp -R skills/skills/<skill-name> ~/.claude/skills/
```

Claude Code picks up new skills the next time a session starts.

## License

MIT — see [LICENSE](LICENSE).
