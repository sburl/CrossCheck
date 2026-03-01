import glob

agent_files = glob.glob('agents/**/*.md', recursive=True) + glob.glob('claude/agents/**/*.md', recursive=True) + glob.glob('codex/agents/**/*.md', recursive=True)

for filepath in agent_files:
    if 'README' in filepath or 'claude_critic' in filepath or 'codex_critic' in filepath or 'coach' in filepath:
        continue

    with open(filepath, 'r') as f:
        content = f.read()

    # ensure timestamp exists
    if '**Created:**' not in content:
        parts = content.split('---', 2)
        if len(parts) >= 3:
            body = parts[2]
            body = "\n**Created:** 2026-03-01-00-00\n**Last Updated:** 2026-03-01-00-00\n" + body.lstrip()
            content = '---' + parts[1] + '---' + body

    with open(filepath, 'w') as f:
        f.write(content)
