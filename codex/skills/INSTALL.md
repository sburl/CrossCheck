# Installing Codex Skills

Install all skills from this repo into your Codex home.

## Install

```bash
mkdir -p ~/.codex/skills
cp -R ~/Documents/Developer/CrossCheck/codex/skills/* ~/.codex/skills/
```

## Verify

```bash
find ~/.codex/skills -mindepth 2 -maxdepth 2 -name SKILL.md | wc -l
```

## Optional: skip specific skills

Create `~/.crosscheck/skip-skills` with one skill name per line.
The bootstrap script (`codex/scripts/bootstrap-crosscheck.sh`) will skip those skills.

## Notes

- Skills are folder-based: `~/.codex/skills/<skill-name>/SKILL.md`
- This `codex/skills/` directory is the canonical source for Codex-format skills.
- `codex/skill-sources/` is legacy compatibility material.
