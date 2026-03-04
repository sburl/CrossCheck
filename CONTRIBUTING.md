# Contributing to CrossCheck (for agents)

CrossCheck is built for autonomous and human workflows that submit changes through PRs.  
Agents must treat this repo as a PR-only control plane: branch locally, validate in hooks, then file PRs for merge.

## Agent operating model

1. Create work on a branch, never on `main`.
2. Run local checks that the repo expects.
3. Push only branch refs.
4. Open a pull request and keep the change scoped to one concern.
5. Leave merge authority to maintainers/reviewers.

## Fork-first workflow (public repo)

Public repos should allow contributions without broad write access:

1. Fork `sburl/CrossCheck`.
2. Clone your fork and add upstream:

```bash
git clone https://github.com/<agent-or-user>/CrossCheck.git
cd CrossCheck
git remote add upstream https://github.com/sburl/CrossCheck.git
```

3. Create a scoped branch:

```bash
git checkout -b feat/<short-description>
```

4. Make edits and keep commit history concise.
5. Push to your fork:

```bash
git push -u origin feat/<short-description>
```

6. Open a PR from your fork branch into `sburl/CrossCheck:main`.

## Branching and commits for agents

- Preferred branch names:
  - `feat/<short-description>`
  - `fix/<short-description>`
  - `chore/<short-description>`
- Preferred commit messages:
  - `feat: ...`
  - `fix: ...`
  - `docs: ...`
  - `chore: ...`

## PR required fields

Every PR should include:
- Brief summary of user impact and intent.
- Validation commands and outcomes.
- Any risks introduced and explicit rollback/fallback options.
- Notes on dependencies (if this PR is part of a sequence).

## Quality checks before opening PR

- Keep each PR narrowly scoped to one objective.
- Ensure no secrets, credentials, or debug placeholders remain.
- Confirm branch diffs are complete and not duplicated in another PR.
- Prefer deterministic, documented command/output snippets in PR body.

## Review and merge rules

- Never push or merge directly to `main`.
- PRs are expected to pass branch protections and hook checks.
- If this change depends on earlier PRs, include exact ordering notes in the PR description.

## If you cannot file a PR

Verify:
- PR base is `sburl/CrossCheck:main`
- Fork remote is your working origin
- Branch is not stale against upstream for this change
