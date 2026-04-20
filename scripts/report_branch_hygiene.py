#!/usr/bin/env python3
"""Report remote branch hygiene and optionally delete safe merged branches."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
import time
from dataclasses import asdict, dataclass
from datetime import UTC, datetime


PROTECTED_PREFIXES = ("keep/", "stack/", "release/", "hotfix/")


@dataclass
class PullRequestInfo:
    number: int
    title: str
    url: str
    head: str
    base: str
    state: str
    merged_at: str | None
    closed_at: str | None
    is_draft: bool


@dataclass
class BranchStatus:
    branch: str
    sha: str
    committer_date: str
    age_days: int
    classification: str
    action: str
    reason: str
    pr_number: int | None
    pr_url: str | None


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", default=None, help="Optional OWNER/REPO override for GitHub queries")
    parser.add_argument("--remote", default="origin", help="Git remote to inspect")
    parser.add_argument("--base", default="main", help="Default branch to compare against")
    parser.add_argument(
        "--stale-days",
        type=int,
        default=30,
        help="Age threshold for flagging unique no-PR branches as stale",
    )
    parser.add_argument(
        "--delete-merged",
        action="store_true",
        help="Delete only safe merged remote branches (merged PRs or merged branches with no PR)",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="Emit JSON instead of a text report",
    )
    return parser


def format_command_error(exc: subprocess.CalledProcessError) -> str:
    stdout = exc.stdout.strip() if exc.stdout else ""
    stderr = exc.stderr.strip() if exc.stderr else ""
    details = [f"Command {exc.cmd!r} returned non-zero exit status {exc.returncode}."]
    if stderr:
        details.append(f"stderr: {stderr}")
    if stdout:
        details.append(f"stdout: {stdout}")
    return " ".join(details)


def run(
    cmd: list[str],
    *,
    check: bool = True,
    retries: int = 0,
    retry_delay_seconds: float = 1.0,
) -> subprocess.CompletedProcess[str]:
    attempts = retries + 1
    last_exc: subprocess.CalledProcessError | None = None
    for attempt in range(1, attempts + 1):
        try:
            return subprocess.run(cmd, check=check, capture_output=True, text=True)
        except subprocess.CalledProcessError as exc:
            last_exc = exc
            if attempt >= attempts:
                raise subprocess.CalledProcessError(
                    exc.returncode,
                    exc.cmd,
                    output=exc.output,
                    stderr=format_command_error(exc),
                ) from exc
            time.sleep(retry_delay_seconds)
    assert last_exc is not None
    raise last_exc


def git(*args: str, check: bool = True) -> subprocess.CompletedProcess[str]:
    return run(["git", *args], check=check)


def gh(*args: str, check: bool = True) -> subprocess.CompletedProcess[str]:
    return run(["gh", *args], check=check, retries=2, retry_delay_seconds=1.5)


def parse_iso8601(value: str) -> datetime:
    normalized = value.strip().replace(" ", "T")
    if normalized.endswith("Z"):
        normalized = normalized[:-1] + "+00:00"
    return datetime.fromisoformat(normalized).astimezone(UTC)


def fetch_remote_branches(remote: str) -> list[tuple[str, str, str]]:
    result = git(
        "for-each-ref",
        "--format=%(refname:short)\t%(objectname)\t%(committerdate:iso8601-strict)",
        f"refs/remotes/{remote}",
    )
    branches: list[tuple[str, str, str]] = []
    prefix = f"{remote}/"
    for raw_line in result.stdout.splitlines():
        line = raw_line.strip()
        if not line:
            continue
        ref_name, sha, committer_date = line.split("\t")
        if ref_name == remote or ref_name == f"{remote}/HEAD":
            continue
        if not ref_name.startswith(prefix):
            continue
        branch = ref_name.removeprefix(prefix)
        branches.append((branch, sha, committer_date))
    return branches


def fetch_pull_requests(*, repo: str | None) -> list[PullRequestInfo]:
    cmd = [
        "pr",
        "list",
        "--state",
        "all",
        "--limit",
        "500",
        "--json",
        "number,title,url,headRefName,baseRefName,state,mergedAt,closedAt,isDraft",
    ]
    if repo:
        cmd.extend(["--repo", repo])
    result = gh(*cmd)
    payload = json.loads(result.stdout)
    return [
        PullRequestInfo(
            number=item["number"],
            title=item["title"],
            url=item["url"],
            head=item["headRefName"],
            base=item["baseRefName"],
            state=item["state"],
            merged_at=item.get("mergedAt"),
            closed_at=item.get("closedAt"),
            is_draft=bool(item.get("isDraft")),
        )
        for item in payload
    ]


def select_pull_request(prs: list[PullRequestInfo]) -> PullRequestInfo | None:
    if not prs:
        return None
    open_prs = [pr for pr in prs if pr.state.upper() == "OPEN"]
    if open_prs:
        return sorted(open_prs, key=lambda pr: pr.number)[-1]
    merged_prs = [pr for pr in prs if pr.merged_at]
    if merged_prs:
        return sorted(merged_prs, key=lambda pr: (pr.merged_at or "", pr.number))[-1]
    return sorted(prs, key=lambda pr: (pr.closed_at or "", pr.number))[-1]


def merged_into_base(remote: str, branch: str, base: str) -> bool:
    result = git("merge-base", "--is-ancestor", f"{remote}/{branch}", f"{remote}/{base}", check=False)
    return result.returncode == 0


def classify_branch(
    *,
    remote: str,
    base: str,
    branch: str,
    sha: str,
    committer_date: str,
    stale_days: int,
    prs_by_head: dict[str, list[PullRequestInfo]],
) -> BranchStatus:
    now = datetime.now(UTC)
    age_days = max(0, (now - parse_iso8601(committer_date)).days)
    pr = select_pull_request(prs_by_head.get(branch, []))

    if branch == base:
        classification = "keep/default-branch"
        action = "keep"
        reason = "default branch"
    elif branch.startswith(PROTECTED_PREFIXES):
        classification = "keep/protected-pattern"
        action = "keep"
        reason = "matches protected prefix"
    elif pr and pr.state.upper() == "OPEN":
        classification = "keep/open-pr"
        action = "keep"
        reason = f"open PR #{pr.number}"
    elif pr and pr.merged_at:
        classification = "delete/merged-pr"
        action = "delete"
        reason = f"merged PR #{pr.number}"
    elif pr and pr.state.upper() == "CLOSED":
        classification = "review/closed-unmerged-pr"
        action = "review"
        reason = f"closed unmerged PR #{pr.number}"
    elif merged_into_base(remote, branch, base):
        classification = "delete/merged-no-pr"
        action = "delete"
        reason = f"merged into {remote}/{base} with no PR record"
    elif age_days >= stale_days:
        classification = "review/stale-unique-no-pr"
        action = "review"
        reason = f"no PR and {age_days} days old"
    else:
        classification = "review/active-unique-no-pr"
        action = "review"
        reason = "no PR and not merged"

    return BranchStatus(
        branch=branch,
        sha=sha,
        committer_date=committer_date,
        age_days=age_days,
        classification=classification,
        action=action,
        reason=reason,
        pr_number=pr.number if pr else None,
        pr_url=pr.url if pr else None,
    )


def build_report(*, repo: str | None, remote: str, base: str, stale_days: int) -> list[BranchStatus]:
    prs = fetch_pull_requests(repo=repo)
    prs_by_head: dict[str, list[PullRequestInfo]] = {}
    for pr in prs:
        prs_by_head.setdefault(pr.head, []).append(pr)

    report: list[BranchStatus] = []
    for branch, sha, committer_date in fetch_remote_branches(remote):
        if branch == "HEAD":
            continue
        report.append(
            classify_branch(
                remote=remote,
                base=base,
                branch=branch,
                sha=sha,
                committer_date=committer_date,
                stale_days=stale_days,
                prs_by_head=prs_by_head,
            )
        )
    return sorted(report, key=lambda item: (item.action, item.classification, item.branch))


def delete_safe_branches(*, repo: str | None, statuses: list[BranchStatus]) -> list[str]:
    deleted: list[str] = []
    for status in statuses:
        if status.action != "delete":
            continue
        gh("api", "--method", "DELETE", f"repos/{repo}/git/refs/heads/{status.branch}")
        deleted.append(status.branch)
    return deleted


def format_report(statuses: list[BranchStatus]) -> str:
    lines = ["Remote branch hygiene report"]
    counts = {"keep": 0, "review": 0, "delete": 0}
    for status in statuses:
        counts[status.action] += 1
    lines.append(
        f"Summary: keep={counts['keep']} review={counts['review']} delete={counts['delete']} total={len(statuses)}"
    )
    for group in ("keep", "review", "delete"):
        lines.append("")
        lines.append(f"{group.upper()}:")
        group_items = [status for status in statuses if status.action == group]
        if not group_items:
            lines.append("  (none)")
            continue
        for status in group_items:
            pr_suffix = f" pr=#{status.pr_number}" if status.pr_number is not None else ""
            lines.append(
                f"- {status.branch} [{status.classification}] age={status.age_days}d reason={status.reason}{pr_suffix}"
            )
    return "\n".join(lines)


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        report = build_report(repo=args.repo, remote=args.remote, base=args.base, stale_days=args.stale_days)
    except (subprocess.CalledProcessError, json.JSONDecodeError, ValueError) as exc:
        detail = exc.stderr if isinstance(exc, subprocess.CalledProcessError) and exc.stderr else str(exc)
        print(f"Failed to build branch hygiene report: {detail}", file=sys.stderr)
        return 1

    if args.delete_merged:
        if not args.repo:
            print("--delete-merged requires --repo OWNER/REPO", file=sys.stderr)
            return 2
        try:
            deleted = delete_safe_branches(repo=args.repo, statuses=report)
        except subprocess.CalledProcessError as exc:
            detail = exc.stderr if exc.stderr else str(exc)
            print(f"Failed to delete safe merged branches: {detail}", file=sys.stderr)
            return 1
        print(json.dumps({"deleted": deleted}, indent=2))
        return 0

    if args.json:
        print(json.dumps([asdict(item) for item in report], indent=2))
        return 0

    print(format_report(report))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
