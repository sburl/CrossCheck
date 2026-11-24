# Installing Codex Skills

**Created:** 2026-02-24-14-56
**Last Updated:** 2026-11-24-00-39

Install all skills from this repo into your Codex home.

## Install

```bash
bash ~/Documents/Developer/CrossCheck/codex/scripts/sync-managed-codex-skills.sh ~/Documents/Developer/CrossCheck "$HOME"
```

## Verify

```bash
find ~/.codex/skills -mindepth 2 -maxdepth 2 -name SKILL.md | wc -l
```

## Optional: skip specific skills

Create `~/.crosscheck/skip-skills` with one skill name per line.
The bootstrap and managed sync scripts will skip those skills.

## Notes

- Skills are folder-based: `~/.codex/skills/<skill-name>/SKILL.md`
- This `codex/skills/` directory is the canonical source for Codex-format skills.
- `codex/skill-sources/` is legacy compatibility material.
- Existing files are refreshed only when repository history confirms they are unchanged shipped copies; customized or linked files are preserved.
