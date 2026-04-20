# Branch Hygiene

**Created:** 2026-04-20-00-00
**Last Updated:** 2026-04-20-00-00

Remote branches are workflow refs, not long-term storage. CrossCheck treats them as disposable unless they still serve a current workflow.

## Policy

Classify every non-`main` remote branch into one of three buckets:

- `active`
  - open PR head
  - known stacked branch
  - explicit keeper branch (for example `keep/*`, `stack/*`, `release/*`, `hotfix/*`)
- `historical but useful`
  - rare short-term hold branch you still need for archaeology or rollback context
  - should usually become an issue, PR note, or doc instead of living forever as a branch
- `dead`
  - merged PR branch
  - merged branch with no surviving PR
  - closed/unmerged stale branch
  - old agent/worktree/scratch branch

The default assumption is: if a remote branch is not helping a live workflow, it should disappear.

## Safe Automation

### 1. Turn on GitHub auto-delete-on-merge

This is the highest-value hygiene control because it prevents new merged PR heads from piling up.

Verify:

```bash
gh api repos/OWNER/REPO --jq .delete_branch_on_merge
```

Enable:

```bash
gh api --method PATCH repos/OWNER/REPO -f delete_branch_on_merge=true
```

### 2. Run the branch hygiene report

From the repo you want to audit:

```bash
python3 ~/Documents/Developer/CrossCheck/scripts/report_branch_hygiene.py \
  --repo OWNER/REPO
```

This classifies remote branches into:

- `keep/open-pr`
- `keep/protected-pattern`
- `delete/merged-pr`
- `delete/merged-no-pr`
- `review/closed-unmerged-pr`
- `review/stale-unique-no-pr`
- `review/active-unique-no-pr`

### 3. Delete only safe merged branches

If the report looks right:

```bash
python3 ~/Documents/Developer/CrossCheck/scripts/report_branch_hygiene.py \
  --repo OWNER/REPO \
  --delete-merged
```

That only deletes:

- `delete/merged-pr`
- `delete/merged-no-pr`

It does not touch open PR branches, protected prefixes, or stale unique branches.

## Reusable Workflow

CrossCheck ships a reusable workflow at `.github/workflows/branch-hygiene.yml`.

To use it in another repo, add a small wrapper workflow like:

```yaml
name: Branch Hygiene

on:
  workflow_dispatch:
    inputs:
      stale_days:
        type: string
        default: "30"
      delete_merged:
        type: boolean
        default: false
  schedule:
    - cron: "17 12 * * 1"

jobs:
  audit:
    uses: sburl/CrossCheck/.github/workflows/branch-hygiene.yml@main
    with:
      stale_days: ${{ inputs.stale_days || '30' }}
      delete_merged: ${{ inputs.delete_merged || false }}
```

## Agent Rollout Playbook

When an agent is applying CrossCheck to another repo, use this sequence:

1. Enable GitHub auto-delete-on-merge:

```bash
gh api --method PATCH repos/OWNER/REPO -f delete_branch_on_merge=true
```

2. Install the reusable workflow or copy the local workflow file:

- preferred: add a thin wrapper that `uses: sburl/CrossCheck/.github/workflows/branch-hygiene.yml@main`
- fallback: copy `.github/workflows/branch-hygiene.yml` into the target repo

3. Add or update any repo-local docs that describe branch retention exceptions:

- protected prefixes such as `keep/*`, `stack/*`, `release/*`, `hotfix/*`
- any team-specific review cadence
- any repo-specific long-lived branch rules

4. Run a report-only audit first:

```bash
python3 ~/.crosscheck/scripts/report_branch_hygiene.py --repo OWNER/REPO
```

5. Do not auto-delete `review/*` candidates during rollout:

- open or update PRs for branches that still matter
- archive or document any intentionally retained long-lived branches
- delete only safe merged branches once the report looks correct

6. Validate the repo configuration:

```bash
bash ~/.crosscheck/scripts/validate-github-protection.sh
```

The expected outcome is:

- GitHub auto-delete-on-merge enabled
- scheduled branch-hygiene report available
- optional manual merged-branch deletion available
- no destructive automation touching unique or closed-unmerged branches

## Operational Rules

- keep `main` as the only always-live branch
- use `keep/*` only when a branch truly must survive cleanup
- use `stack/*` for known stacked PR lines and keep stack documentation current
- do not use remote branches as personal bookmarks
- review `review/*` candidates before deleting:
  - if still needed, open or update a PR
  - if not needed, delete them explicitly

## Suggested Cadence

- on every merged PR: rely on GitHub auto-delete-on-merge
- weekly: scheduled report review
- monthly or after a large multi-agent session: manual `--delete-merged` run plus review of stale unique branches
