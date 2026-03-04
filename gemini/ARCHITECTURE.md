# Gemini CLI Architecture

**Created:** 2026-03-01-00-00
**Last Updated:** 2026-03-01-00-00

The Gemini CLI integration follows the same 6-phase development cycle as Claude and Codex.

For details, see:
- **[Main ARCHITECTURE.md](../ARCHITECTURE.md)** - Core CrossCheck design.
- **[GEMINI.md](GEMINI.md)** - Gemini-specific workflow and tools.

---

## Component Interaction for Gemini

### Gemini Tools

Unlike Claude Code, Gemini CLI includes powerful native tools:

- **codebase_investigator** - System-wide architectural mapping and analysis.
- **google_web_search** - Grounded search across the internet.
- **web_fetch** - Deep analysis and data extraction from URLs.
- **cli_help** - Direct access to Gemini CLI's own documentation and configuration.

### Multi-Layered Review with Gemini

Gemini's large context window makes it an exceptional reviewer. It can analyze entire projects at once, spotting cross-file inconsistencies that smaller-context models might miss.

---

## Security Model for Gemini CLI

Gemini CLI should be configured with the same security guardrails as Claude Code:
- Blocked commands: `rm`, `sudo`, `eval`, etc.
- Deny rules for sensitive files like `.env` and `.key`.
- Branch protection enforcement server-side.
