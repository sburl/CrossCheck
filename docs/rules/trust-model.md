**Created:** 2026-02-11-00-00
**Last Updated:** 2026-05-20-00-00

# Security (Boundary-Based Trust)

**Philosophy:** Feature branches = permissive. Main = requires separate identity.

## Feature branches (client-side - permissive)

- Can rebase, force-push, experiment freely
- Agents have full control
- Still block: `rm`, `git reset --hard`, sensitive file reads (`.env`, `.ssh`, `.aws`, `.pem`, `.key` via Read tool + cat/head/tail/sed/awk/grep), `sudo`, `docker`, `while read` loops, data-sending `curl` (POST/PUT/PATCH/-d/-F/-T/--json/--upload), `git config` for hooks/aliases, `git commit -n` (--no-verify short form)

## Main branch (server-side - strict)

GitHub enforces identity-based rules:

- No force-push to main
- No direct commits to main
- PR required with external approval
- Can't self-approve (account that pushed can't approve)
- Squash-only merge
- Linear history only
- **Need separate account** to approve PRs you create

## Absolute prohibitions

**NEVER bypass branch protections.** These are hard rules that no agent may violate under any circumstances:

- **NEVER use `--admin` flag** on `gh pr merge` or any `gh` command. This bypasses branch protection rules and defeats the entire trust model.
- **NEVER modify GitHub rulesets** via `gh api` or any other mechanism. Rulesets are configured once by the human via `/setup-automation` and must not be weakened, relaxed, or changed by agents.
- **NEVER modify branch protection settings** via the GitHub API. This includes changing `required_approving_review_count`, `require_last_push_approval`, `require_code_owner_review`, or any other protection parameter.
- If a PR is blocked by branch protection, **that is working as intended**. The correct response is to get a legitimate review from a separate account, not to bypass the protection.

These are enforced by deny rules in `settings.json` (`gh*--admin*`, `*--admin*`, `gh api*rulesets*`, `gh api*branches/*/protection*`, `*graphql*BranchProtection*`, `*graphql*Ruleset*`), but the prohibition is absolute regardless of settings. The `*--admin*` catch-all prevents command-prefixing bypasses (e.g. `cd . && gh pr merge --admin`). The GraphQL patterns prevent ruleset mutation via the GitHub GraphQL API.

## Required merge convention: `gh pr merge --auto`

**ALWAYS use `gh pr merge --auto`** (not bare `gh pr merge`) when merging PRs.

**Why:** Bare `gh pr merge` attempts the merge immediately. Parallel merge invocations against the same base branch race; GitHub creates the merge commit but only one fast-forward succeeds, leaving the loser reported as "MERGED" with a `mergeCommit.oid` that is **not in main's ancestry**. We hit this on 2026-05-20 — PR #2340 was reported merged but its commit never landed, and a historical audit found 3 prior occurrences (#2096, #1670, #1434).

`--auto` queues the merge to fire only when checks pass and the base is current, eliminating the race entirely. It also waits for branch-protection conditions instead of failing outright.

**Pattern:**
```bash
gh pr merge $PR_NUMBER --auto --squash --delete-branch
```

The `--squash` matches the squash-only ruleset; `--delete-branch` keeps the branch list clean; `--auto` is what prevents the lost-race class.

## Why this works

- Agents work freely on feature branches
- Main requires genuine external review
- Builder != Reviewer (different accounts required)

## Zero Trust Details

**Mindset:** Builder + Adversary simultaneously

Every change:

1. Code + tests together
2. Question assumptions
3. Run tests
4. Pass = continue

**Unfamiliar behavior?** Run tests to find out, don't assume.

## Deny List Limitations

The deny list is defense-in-depth, not a sandbox. Known limitations:

- **General-purpose runtimes bypass all deny rules.** `python3`, `node`, and similar runtimes can execute arbitrary system commands internally. The deny list only pattern-matches the top-level bash command.
- **`gh api` requires human approval** (ask list) but specific `gh` subcommands (pr, issue, run) are auto-allowed.
- **`source` requires human approval** (ask list) since sourced scripts can execute denied commands.
- **CLAUDE.md and docs/rules/ modifications require approval** (ask list) to prevent silent self-modification of agent constraints.

The real security boundary is server-side: GitHub branch protection, PR approval requirements, and the two-account model.

## Supply Chain

**Threat model.** npm, PyPI, RubyGems, crates.io, and Go modules are push-once-published-everywhere registries. A compromised maintainer account or a typosquat ships malware to millions of installs within minutes. Recent examples: `ua-parser-js` (Oct 2021), `coa`/`rc` (Nov 2021), `colors`/`faker` sabotage (Jan 2022), `ctx` PyPI takeover (May 2022), `chalk`/`debug` ecosystem attacks (Sep 2025). Typical exploit path: `postinstall` script during `npm install`.

**Defense layers** (each partial; together effective):

1. **PATH shim** (strongest, single source of truth). A user-controlled `npm`/`npx`/`pnpm`/`yarn` shim at `~/bin/safe-shims/` earlier in `$PATH` than the real binary. For `npm install <pkg>`, the shim composes **both** layers in sequence: (1) resolve `<pkg>` to the newest version ≥`SHIM_AGE_DAYS` old (default 7) by querying the registry, then (2) hand off to `socket` (if installed) for static-analysis malware scan on that specific resolved version. User-pinned versions skip step 1. Scoped packages handled. Lockfile-only commands (`npm ci`, `--offline`, `--frozen-lockfile`) pass through unchanged. `npx` routes through socket only (no age resolution — npx args too variable to reliably extract package name; use `npm-safe-install -g <tool>` instead if you want the age guarantee for a CLI). pnpm/yarn `add` are blocked by default since socket doesn't wrap them — `SAFE_INSTALL_OVERRIDE=1` to override. Works for every tool that inherits the user's environment — Claude, Codex, Cursor, plain shell. Survives agent updates.
2. **PreToolUse hook** — `scripts/preuse-supply-chain-gate.sh`. Runs on every Bash tool call from Claude Code. Pattern-matches install verbs (`npm install`, `pnpm add`, `pip install`, `uv add`, `cargo install`, etc.) and exits 2 — Claude Code surfaces the stderr message back to the model so it self-corrects to the safe variant. Allows `npm ci`, `uv sync`, lockfile-only installs, anything prefixed by `socket ` or `npm-safe-install`, or env-prefixed `SAFE_INSTALL_OVERRIDE=1`.
3. **`settings.json` ask list** for install verbs. If the hook is missing/bypassed, the agent still has to request human approval.
4. **Pre-commit / pre-push scan** — `scripts/scan-supply-chain.sh`. Runs at git-hook time on changes to `package.json`, `requirements.txt`, `pyproject.toml`, `Gemfile`, `Cargo.toml`, `composer.json`, `go.mod`. Checks against a known-bad list, flags unpinned ranges, optionally queries the npm registry to enforce a minimum release age. Exit 2 = malicious (always blocks); exit 1 = warning (pre-commit allows, pre-push blocks).
5. **`npm config set ignore-scripts true`** as a global default. Kills the postinstall path, where almost all real npm attacks land. Override per-install with `--ignore-scripts=false` when a package legitimately needs build steps. Pip equivalent: `pip install --only-binary=:all:`.
6. **Dependabot cooldown** in `.github/dependabot.yml`. Public repos use 7-day default / 15-day major cooldown; private/org repos use 10/20. Configures Dependabot to wait N days after a version is released before opening a version-bump PR. Catches the supply-chain attack window where a bad release is live but hasn't been pulled yet. Security advisories bypass cooldown — CVE patches still fire immediately. Bulk-rollout: `scripts/install-dependabot-cooldown.sh`.
7. **Template repositories**: [`sburl/template`](https://github.com/sburl/template) (public, 7/15) and [`sqburl/template`](https://github.com/sqburl/template) (private, 10/20) — GitHub template repos preconfigured with the right cooldown defaults. New repos created from these templates ship with supply-chain protection on day one. Drift across existing repos is caught by `scripts/gh-repo-setup-cron.sh`, which re-runs the cooldown installer daily as part of the standard repo-setup workflow.

**Bypass paths (documented):**

- `node -e '<code>'` or `python -c '<code>'` can `child_process.exec` an install. The hook does not inspect runtime contents — only the literal command. Same general-runtime-bypass acknowledged in *Deny List Limitations*; mitigation is the PATH shim catching the `npm` invocation from inside Node.
- `SAFE_INSTALL_OVERRIDE=1` env prefix bypasses the PreToolUse hook by design (so humans can override). It is visible in the transcript.
- Direct registry HTTP fetch (`curl https://registry.npmjs.org/...`) is not blocked. Agents have no reason to do this, so it appears in transcript review.

**Agent guidance.** When asked to install a dependency, agents should default to plain `npm install <pkg>`. If the PATH shim is installed (the normal case on these machines), it transparently applies the age-resolution + socket-scan dual layer. The agent doesn't need to know the policy — the shim enforces it. If the install fails with the shim's policy message, the agent should:

```
npm ci                                       # if restoring from lockfile
SAFE_INSTALL_OVERRIDE=1 npm install <pkg>    # if the user has confirmed the package is trusted
SHIM_AGE_DAYS=N npm install <pkg>            # if the user wants a different cutoff
```

The agent should never recommend `--no-verify`-style escapes; if blocked, that's the system working as designed.
