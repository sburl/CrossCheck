"""Regression tests for fail-closed security-hook mirror checks."""

import json
import os
import re
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
HOOK = "preuse-supply-chain-gate.sh"
HOOK_INSTALLER = ROOT / "claude/scripts/install-supply-chain-hook.sh"
UPDATE_RECIPES = (
    "skill-sources/update-crosscheck.md",
    "claude/skill-sources/update-crosscheck.md",
    "codex/skill-sources/update-crosscheck.md",
    "codex/skills/update-crosscheck/SKILL.md",
)


def run_audit(fixture: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["bash", str(fixture / "scripts/check-script-mirrors.sh")],
        capture_output=True,
        check=False,
        text=True,
    )


class ScriptMirrorAuditTests(unittest.TestCase):
    def make_fixture(self, root: Path) -> Path:
        for relative in ("scripts", "codex/scripts", "claude/scripts"):
            shutil.copytree(root / relative, self.fixture / relative)
        return self.fixture

    def setUp(self) -> None:
        self.temp_dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp_dir.cleanup)
        self.fixture = Path(self.temp_dir.name)
        self.home = self.fixture / "home"
        self.home.mkdir()
        self.settings_dir = self.fixture / "settings"
        self.settings_dir.mkdir()
        self.home_patch = patch.dict(os.environ, {"HOME": str(self.home)})
        self.home_patch.start()
        self.addCleanup(self.home_patch.stop)

    def test_compatibility_bootstrap_preserves_custom_commands(self) -> None:
        root = self.fixture / "compat-repo"
        home = self.fixture / "compat-home"
        (root / "scripts").mkdir(parents=True)
        (root / "skill-sources").mkdir()
        shutil.copy(ROOT / "scripts/atomic-publish-file.py", root / "scripts/atomic-publish-file.py")
        source = root / "skill-sources/plan.md"
        source.write_text("current shipped command\n", encoding="utf-8")
        home_codex = home / ".codex/commands"
        home_gemini = home / ".gemini/agents"
        home_codex.mkdir(parents=True)
        home_gemini.mkdir(parents=True)

        git_env = {**os.environ, "GIT_CONFIG_NOSYSTEM": "1"}
        subprocess.run(["git", "-C", str(root), "init", "-q"], check=True, env=git_env)
        subprocess.run(
            ["git", "-C", str(root), "add", "skill-sources/plan.md"], check=True, env=git_env
        )
        subprocess.run(
            [
                "git", "-C", str(root), "-c", "user.name=CrossCheck test", "-c",
                "user.email=crosscheck-test@example.invalid", "commit", "-qm", "published command",
            ],
            check=True,
            env=git_env,
        )
        revision = subprocess.run(
            ["git", "-C", str(root), "rev-parse", "HEAD"],
            check=True,
            capture_output=True,
            text=True,
            env=git_env,
        ).stdout.strip()
        subprocess.run(
            ["git", "-C", str(root), "update-ref", "refs/remotes/origin/main", revision],
            check=True,
            env=git_env,
        )

        shipped_copy = home_codex / "plan.md"
        shipped_copy.write_text("current shipped command\n", encoding="utf-8")
        customized_copy = home_gemini / "plan.md"
        customized_copy.write_text("user customization\n", encoding="utf-8")

        def sync(target: Path) -> subprocess.CompletedProcess[str]:
            return subprocess.run(
                [
                    "python3", str(root / "scripts/atomic-publish-file.py"), "managed-symlink",
                    str(home), str(target.relative_to(home)), str(source), str(root), "skill-sources/plan.md",
                ],
                capture_output=True,
                check=False,
                text=True,
                env=git_env,
            )

        # A matching historical copy migrates, while a customized file stays intact.
        source.write_text("updated shipped command\n", encoding="utf-8")
        shipped_copy.write_text("current shipped command\n", encoding="utf-8")
        result = sync(shipped_copy)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(result.stdout.strip(), "updated")
        self.assertTrue(shipped_copy.is_symlink())
        self.assertEqual(shipped_copy.read_text(encoding="utf-8"), "updated shipped command\n")

        result = sync(customized_copy)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(result.stdout.strip(), "preserved")
        self.assertFalse(customized_copy.is_symlink())
        self.assertEqual(customized_copy.read_text(encoding="utf-8"), "user customization\n")

        guarded_parent = self.fixture / "guarded-parent"
        guarded_home = guarded_parent / "home"
        guarded_target_dir = guarded_home / ".codex/commands"
        guarded_target_dir.mkdir(parents=True)
        guarded_target = guarded_target_dir / "plan.md"
        guarded_target.write_text("current shipped command\n", encoding="utf-8")
        guarded_parent.chmod(0o555)
        try:
            guarded_env = {**git_env, "HOME": str(guarded_home)}
            result = subprocess.run(
                [
                    "python3", str(root / "scripts/atomic-publish-file.py"), "managed-symlink",
                    str(guarded_home), str(guarded_target.relative_to(guarded_home)), str(source),
                    str(root), "skill-sources/plan.md",
                ],
                capture_output=True,
                check=False,
                text=True,
                env=guarded_env,
            )
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertEqual(result.stdout.strip(), "updated")
            self.assertTrue(guarded_target.is_symlink())
            self.assertTrue(list((guarded_home / ".crosscheck-recovery").glob("snapshot-*.bak")))
        finally:
            guarded_parent.chmod(0o755)

        fresh_source = root / "skill-sources/fresh.md"
        fresh_source.write_text("new command\n", encoding="utf-8")
        fresh_target = home_codex / "fresh.md"
        result = subprocess.run(
            [
                "python3", str(root / "scripts/atomic-publish-file.py"), "managed-symlink",
                str(home), str(fresh_target.relative_to(home)), str(fresh_source), str(root),
                "skill-sources/fresh.md",
            ],
            capture_output=True,
            check=False,
            text=True,
            env=git_env,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(result.stdout.strip(), "created")
        self.assertTrue(fresh_target.is_symlink())

    def test_nightly_skill_mirror_gate_requires_codex_entrypoint(self) -> None:
        fixture = self.fixture / "skill-mirror"
        for relative in (
            "skill-sources",
            "claude/skill-sources",
            "codex/skill-sources",
            "codex/skills/example",
        ):
            (fixture / relative).mkdir(parents=True)
        for relative in (
            "skill-sources/example.md",
            "claude/skill-sources/example.md",
            "codex/skill-sources/example.md",
        ):
            (fixture / relative).write_text("# example\n", encoding="utf-8")
        (fixture / "codex/skills/example/README.md").write_text("not an entrypoint\n", encoding="utf-8")

        command = ["bash", str(ROOT / ".github/scripts/check-skill-mirrors.sh"), str(fixture)]
        result = subprocess.run(command, capture_output=True, check=False, text=True)
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("Missing required Codex skill entrypoint: codex/skills/example/SKILL.md", result.stdout)

        (fixture / "codex/skills/example/SKILL.md").write_text("# example\n", encoding="utf-8")
        result = subprocess.run(command, capture_output=True, check=False, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("All mirror directories match (1 skills)", result.stdout)

        outside_entrypoint = fixture / "outside-SKILL.md"
        outside_entrypoint.write_text("# outside\n", encoding="utf-8")
        entrypoint = fixture / "codex/skills/example/SKILL.md"
        entrypoint.unlink()
        entrypoint.symlink_to(outside_entrypoint)
        result = subprocess.run(command, capture_output=True, check=False, text=True)
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("Missing required Codex skill entrypoint", result.stdout)

    def test_codex_installer_skips_symlinked_skill_entrypoint(self) -> None:
        root = self.fixture / "codex-install"
        (root / "scripts").mkdir(parents=True)
        (root / "codex/skills/example").mkdir(parents=True)
        shutil.copy(ROOT / "scripts/atomic-publish-file.py", root / "scripts/atomic-publish-file.py")
        outside_entrypoint = self.fixture / "external-SKILL.md"
        outside_entrypoint.write_text("# outside\n", encoding="utf-8")
        (root / "codex/skills/example/SKILL.md").symlink_to(outside_entrypoint)
        target_home = self.fixture / "codex-install-home"
        target_home.mkdir()
        result = subprocess.run(
            ["bash", str(ROOT / "codex/scripts/sync-managed-codex-skills.sh"), str(root), str(target_home)],
            capture_output=True,
            check=False,
            text=True,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse((target_home / ".codex/skills/example/SKILL.md").exists())

    def test_supply_chain_gate_blocks_bare_install_commands(self) -> None:
        hook = ROOT / "claude/scripts/preuse-supply-chain-gate.sh"
        for command in (
            "npm install", "npm i", "pnpm install", "yarn install",
            "npm install;", "pnpm install && echo done", "yarn install | cat",
        ):
            with self.subTest(command=command):
                result = subprocess.run(
                    ["bash", str(hook)],
                    input=json.dumps({"tool_name": "Bash", "tool_input": {"command": command}}),
                    capture_output=True,
                    check=False,
                    text=True,
                )
                self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
                self.assertIn("direct package install blocked", result.stderr)

        for command in (
            "npm ci",
            "npm install --offline",
            "pnpm install --frozen-lockfile",
            "yarn install --frozen-lockfile",
        ):
            with self.subTest(command=command):
                result = subprocess.run(
                    ["bash", str(hook)],
                    input=json.dumps({"tool_name": "Bash", "tool_input": {"command": command}}),
                    capture_output=True,
                    check=False,
                    text=True,
                )
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_update_recipes_abort_when_git_refresh_steps_fail(self) -> None:
        fake_bin = self.fixture / "fake-bin"
        fake_bin.mkdir()
        fake_git = fake_bin / "git"
        fake_git.write_text(
            """#!/usr/bin/env bash
set -u
printf '%s\\n' "$1" >> "$GIT_CALL_LOG"
case "$1" in
    fetch)
        [ "${FAIL_GIT_COMMAND:-}" != fetch ] || exit 1
        ;;
    branch)
        printf 'main\\n'
        ;;
    rev-list)
        [ "${FAIL_GIT_COMMAND:-}" != rev-list ] || exit 1
        if [ "${FAIL_GIT_COMMAND:-}" = pull ]; then
            printf '1\\n'
        else
            printf '0\\n'
        fi
        ;;
    pull)
        [ "${FAIL_GIT_COMMAND:-}" != pull ] || exit 1
        ;;
esac
""",
            encoding="utf-8",
        )
        fake_git.chmod(0o755)
        repo = self.fixture / "repo"
        repo.mkdir()

        for relative in UPDATE_RECIPES:
            markdown = (ROOT / relative).read_text(encoding="utf-8")
            step = markdown.split("## Step 3: Pull Latest", maxsplit=1)[1]
            script_match = re.search(r"```bash\n(.*?)\n```", step, re.DOTALL)
            self.assertIsNotNone(script_match, relative)
            script = script_match.group(1)
            for failing_command in ("fetch", "rev-list", "pull"):
                with self.subTest(recipe=relative, failing_command=failing_command):
                    call_log = self.fixture / f"git-calls-{failing_command}.txt"
                    result = subprocess.run(
                        ["bash", "-c", script],
                        capture_output=True,
                        check=False,
                        env={
                            **os.environ,
                            "PATH": f"{fake_bin}:{os.environ['PATH']}",
                            "CROSSCHECK_DIR": str(repo),
                            "CURRENT": "test-version",
                            "FAIL_GIT_COMMAND": failing_command,
                            "GIT_CALL_LOG": str(call_log),
                        },
                        text=True,
                    )
                    self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
                    self.assertNotIn("✅ Pulled latest", result.stdout)
                    self.assertIn(failing_command, call_log.read_text(encoding="utf-8").splitlines())

    def test_update_recipes_sync_codex_native_skills(self) -> None:
        for relative in UPDATE_RECIPES:
            with self.subTest(recipe=relative):
                content = (ROOT / relative).read_text(encoding="utf-8")
                self.assertIn(
                    'if ! bash "$CROSSCHECK_DIR/codex/scripts/sync-managed-codex-skills.sh"',
                    content,
                )

    def test_update_recipes_abort_when_settings_or_hook_sync_fails(self) -> None:
        for relative in UPDATE_RECIPES:
            markdown = (ROOT / relative).read_text(encoding="utf-8")
            step = markdown.split("## Step 4: Sync Critical Deny Rules and the Claude Hook", maxsplit=1)[1]
            script_match = re.search(r"```bash\n(.*?)\n```", step, re.DOTALL)
            self.assertIsNotNone(script_match, relative)
            script = script_match.group(1)
            for failing_helper in ("settings", "hook"):
                with self.subTest(recipe=relative, failing_helper=failing_helper):
                    fixture = self.fixture / f"step4-{relative.replace('/', '-')}-{failing_helper}"
                    root = fixture / "repo"
                    home = fixture / "home"
                    (root / "scripts").mkdir(parents=True)
                    (root / "claude/scripts").mkdir(parents=True)
                    (home / ".claude").mkdir(parents=True)
                    (home / ".claude/settings.json").write_text("{}", encoding="utf-8")
                    call_log = fixture / "calls.txt"
                    settings_helper = root / "scripts/sync-critical-settings.sh"
                    settings_helper.write_text(
                        "#!/usr/bin/env bash\nprintf 'settings\\n' >> \"$SYNC_CALL_LOG\"\n"
                        "[ \"${FAIL_SYNC_HELPER:-}\" != settings ] || exit 42\n",
                        encoding="utf-8",
                    )
                    hook_helper = root / "claude/scripts/install-supply-chain-hook.sh"
                    hook_helper.write_text(
                        "#!/usr/bin/env bash\nprintf 'hook\\n' >> \"$SYNC_CALL_LOG\"\n"
                        "[ \"${FAIL_SYNC_HELPER:-}\" != hook ] || exit 42\n",
                        encoding="utf-8",
                    )
                    settings_helper.chmod(0o755)
                    hook_helper.chmod(0o755)
                    result = subprocess.run(
                        ["bash", "-c", script],
                        capture_output=True,
                        check=False,
                        env={
                            **os.environ,
                            "CROSSCHECK_DIR": str(root),
                            "HOME": str(home),
                            "FAIL_SYNC_HELPER": failing_helper,
                            "SYNC_CALL_LOG": str(call_log),
                        },
                        text=True,
                    )
                    self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
                    expected_calls = ["settings"] if failing_helper == "settings" else ["settings", "hook"]
                    self.assertEqual(call_log.read_text(encoding="utf-8").splitlines(), expected_calls)

    def test_update_recipes_abort_when_codex_native_sync_fails(self) -> None:
        for relative in UPDATE_RECIPES:
            with self.subTest(recipe=relative):
                markdown = (ROOT / relative).read_text(encoding="utf-8")
                step = markdown.split("## Step 6: Wire Any New Skills and Agents", maxsplit=1)[1]
                script_match = re.search(r"```bash\n(.*?)\n```", step, re.DOTALL)
                self.assertIsNotNone(script_match, relative)
                fixture = self.fixture / f"step6-{relative.replace('/', '-')}"
                root = fixture / "repo"
                home = fixture / "home"
                helper = root / "codex/scripts/sync-managed-codex-skills.sh"
                helper.parent.mkdir(parents=True)
                helper.write_text("#!/usr/bin/env bash\nexit 42\n", encoding="utf-8")
                helper.chmod(0o755)
                result = subprocess.run(
                    ["bash", "-c", script_match.group(1)],
                    capture_output=True,
                    check=False,
                    env={**os.environ, "CROSSCHECK_DIR": str(root), "HOME": str(home)},
                    text=True,
                )
                self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn("Codex-native skill sync failed", result.stderr)

    def test_missing_claude_hook_fails(self) -> None:
        fixture = self.make_fixture(ROOT)
        (fixture / "claude/scripts" / HOOK).unlink()

        result = run_audit(fixture)

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Missing or non-executable required Claude mirror", result.stdout)

    def test_missing_claude_hook_installer_fails(self) -> None:
        fixture = self.make_fixture(ROOT)
        (fixture / "claude/scripts/install-supply-chain-hook.sh").unlink()

        result = run_audit(fixture)

        self.assertNotEqual(result.returncode, 0)
        self.assertIn(
            "Missing or non-executable required Claude bootstrap dependency",
            result.stdout,
        )

    def test_non_executable_root_hook_fails(self) -> None:
        fixture = self.make_fixture(ROOT)
        (fixture / "scripts" / HOOK).chmod(0o644)

        result = run_audit(fixture)

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Missing or non-executable required source", result.stdout)

    def test_missing_root_hook_fails(self) -> None:
        fixture = self.make_fixture(ROOT)
        (fixture / "scripts" / HOOK).unlink()

        result = run_audit(fixture)

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Missing or non-executable required source", result.stdout)

    def test_agent_audit_entrypoints_delegate_to_root_audit(self) -> None:
        fixture = self.make_fixture(ROOT)

        for relative in (
            "codex/scripts/check-script-mirrors.sh",
            "claude/scripts/check-script-mirrors.sh",
        ):
            result = subprocess.run(
                ["bash", str(fixture / relative)],
                capture_output=True,
                check=False,
                text=True,
            )
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn("Script mirror audit passed", result.stdout)

    def test_claude_hook_installer_pins_checkout_and_preserves_other_hooks(self) -> None:
        fixture = self.make_fixture(ROOT)
        settings = fixture / "settings" / "settings.json"
        hook_file = fixture / "claude/scripts" / HOOK
        original = {
            "hooks": {"PreToolUse": [
                {
                    "matcher": "Bash",
                    "hooks": [
                        {
                            "type": "command",
                            "command": "for c in \"$HOME/.crosscheck/scripts/preuse-supply-chain-gate.sh\" \"$HOME/.claude/CrossCheck/scripts/preuse-supply-chain-gate.sh\"; do [ -x \"$c\" ] && exec bash \"$c\"; done; exit 0",
                        },
                        {
                            "type": "command",
                            "command": "for c in \"$HOME/Developer/CrossCheck/scripts/preuse-supply-chain-gate.sh\"; do [ -x \"$c\" ] && exec bash \"$c\"; done; echo 'CrossCheck supply-chain hook not found' >&2; exit 2",
                        },
                        {
                            "type": "command",
                            "command": "echo preuse-supply-chain-gate.sh in an audit log is unrelated",
                        },
                        {
                            "type": "command",
                            "command": "bash scripts/backup-preuse-supply-chain-gate.sh",
                        },
                    ],
                },
                {"matcher": "Write", "hooks": [{"type": "command", "command": "keep-this-hook"}]},
            ]},
            "custom": {"retained": True},
        }
        settings.write_text(json.dumps(original))

        result = subprocess.run(
            ["bash", str(HOOK_INSTALLER), str(settings), str(hook_file)],
            capture_output=True,
            check=False,
            text=True,
        )

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        for _ in range(3):
            result = subprocess.run(
                ["bash", str(HOOK_INSTALLER), str(settings), str(hook_file)],
                capture_output=True,
                check=False,
                text=True,
            )
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        updated = json.loads(settings.read_text())
        self.assertEqual(updated["custom"], {"retained": True})
        self.assertEqual(updated["hooks"]["PreToolUse"][1], original["hooks"]["PreToolUse"][1])
        bash_hooks = updated["hooks"]["PreToolUse"][0]["hooks"]
        command = next(
            hook["command"]
            for hook in bash_hooks
            if "CROSSCHECK_SUPPLY_CHAIN_GATE_V1=1" in hook["command"]
        )
        self.assertIn("bash -c", command)
        self.assertIn(r"exit\ 2", command)
        self.assertEqual(
            [hook for hook in bash_hooks if hook["command"] != command],
            original["hooks"]["PreToolUse"][0]["hooks"][2:],
        )
        self.assertEqual(
            sum("CROSSCHECK_SUPPLY_CHAIN_GATE_V1=1" in hook["command"] for hook in bash_hooks),
            1,
        )

        hook_file.write_text("#!/usr/bin/env bash\nexit 0\n")
        hook_file.chmod(0o755)
        successful_hook = subprocess.run(
            ["bash", "-c", command],
            capture_output=True,
            check=False,
            text=True,
        )
        self.assertEqual(successful_hook.returncode, 0, successful_hook.stdout + successful_hook.stderr)

        hook_file.unlink()
        missing_hook = subprocess.run(
            ["bash", "-c", command],
            capture_output=True,
            check=False,
            text=True,
        )
        self.assertEqual(missing_hook.returncode, 2, missing_hook.stdout + missing_hook.stderr)
        self.assertIn("unavailable or non-executable", missing_hook.stderr)

        hook_file.write_text("#!/usr/bin/env bash\nexit 7\n")
        hook_file.chmod(0o755)
        failing_hook = subprocess.run(
            ["bash", "-c", command],
            capture_output=True,
            check=False,
            text=True,
        )
        self.assertEqual(failing_hook.returncode, 2, failing_hook.stdout + failing_hook.stderr)
        self.assertIn("gate failed (7)", failing_hook.stderr)

        errexit_failure = subprocess.run(
            ["bash", "-c", command],
            capture_output=True,
            check=False,
            env={**os.environ, "SHELLOPTS": "errexit"},
            text=True,
        )
        self.assertEqual(
            errexit_failure.returncode,
            2,
            errexit_failure.stdout + errexit_failure.stderr,
        )
        self.assertIn("gate failed (7)", errexit_failure.stderr)

        fresh_settings = fixture / "settings" / "fresh-settings.json"
        fresh_settings.write_text("{}")
        result = subprocess.run(
            ["bash", str(HOOK_INSTALLER), str(fresh_settings), str(hook_file)],
            capture_output=True,
            check=False,
            text=True,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        fresh = json.loads(fresh_settings.read_text())
        self.assertEqual(fresh["hooks"]["PreToolUse"][0]["matcher"], "Bash")
        self.assertEqual(fresh["hooks"]["PreToolUse"][0]["hooks"][0]["command"], command)

    def test_filename_mentions_in_unrelated_hooks_are_preserved_and_bash_is_added(self) -> None:
        fixture = self.make_fixture(ROOT)
        settings = fixture / "settings" / "settings.json"
        hook_file = fixture / "claude/scripts" / HOOK
        write_hook = {
            "matcher": "Write",
            "hooks": [{
                "type": "command",
                "command": "echo preuse-supply-chain-gate.sh is unrelated here",
            }],
        }
        settings.write_text(json.dumps({"hooks": {"PreToolUse": [write_hook]}}))

        result = subprocess.run(
            ["bash", str(HOOK_INSTALLER), str(settings), str(hook_file)],
            capture_output=True,
            check=False,
            text=True,
        )

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        installed = json.loads(settings.read_text())["hooks"]["PreToolUse"]
        self.assertEqual(installed[0], write_hook)
        self.assertEqual(installed[1]["matcher"], "Bash")
        self.assertIn(
            "preuse-supply-chain-gate.sh",
            installed[1]["hooks"][0]["command"],
        )

    def test_filename_mentions_in_same_bash_matcher_are_not_migrated(self) -> None:
        fixture = self.make_fixture(ROOT)
        settings = fixture / "settings" / "settings.json"
        hook_file = fixture / "claude/scripts" / HOOK
        unrelated_hooks = [
            {"type": "command", "command": "echo preuse-supply-chain-gate.sh in an audit log"},
            {"type": "command", "command": "bash scripts/backup-preuse-supply-chain-gate.sh"},
        ]
        settings.write_text(
            json.dumps(
                {
                    "hooks": {
                        "PreToolUse": [
                            {"matcher": "Bash", "hooks": unrelated_hooks},
                        ],
                    },
                }
            )
        )

        result = subprocess.run(
            ["bash", str(HOOK_INSTALLER), str(settings), str(hook_file)],
            capture_output=True,
            check=False,
            text=True,
        )

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        installed = json.loads(settings.read_text())["hooks"]["PreToolUse"]
        self.assertEqual(len(installed), 1)
        self.assertEqual(installed[0]["matcher"], "Bash")
        self.assertEqual(installed[0]["hooks"][:2], unrelated_hooks)
        self.assertEqual(installed[0]["hooks"][2]["type"], "command")
        self.assertIn(HOOK, installed[0]["hooks"][2]["command"])

    def test_symlinked_settings_target_is_updated_without_replacing_symlink(self) -> None:
        fixture = self.make_fixture(ROOT)
        target = fixture / "settings-target.json"
        target.write_text("{}")
        target.chmod(0o640)
        settings = fixture / "settings" / "settings.json"
        settings.symlink_to(target)
        hook_file = fixture / "claude/scripts" / HOOK

        result = subprocess.run(
            ["bash", str(HOOK_INSTALLER), str(settings), str(hook_file)],
            capture_output=True,
            check=False,
            text=True,
        )

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertTrue(settings.is_symlink())
        self.assertEqual(target.stat().st_mode & 0o777, 0o640)
        updated = json.loads(target.read_text())
        self.assertIn("Bash", [entry["matcher"] for entry in updated["hooks"]["PreToolUse"]])

    def test_non_executable_claude_hook_fails(self) -> None:
        fixture = self.make_fixture(ROOT)
        (fixture / "claude/scripts" / HOOK).chmod(0o644)

        result = run_audit(fixture)

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Missing or non-executable required Claude mirror", result.stdout)

    def test_claude_supply_chain_hook_fails_closed_without_jq(self) -> None:
        fixture = self.make_fixture(ROOT)
        hook = fixture / "claude/scripts" / HOOK
        minimal_path = fixture / "bin"
        minimal_path.mkdir()
        minimal_path.joinpath("cat").symlink_to(shutil.which("cat"))

        result = subprocess.run(
            ["/bin/bash", str(hook)],
            capture_output=True,
            check=False,
            env={**os.environ, "PATH": str(minimal_path)},
            input='{"tool_name":"Bash","tool_input":{"command":"npm install untrusted-pkg"}}',
            text=True,
        )

        self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
        self.assertIn("jq is unavailable", result.stderr)

    def test_claude_supply_chain_hook_fails_closed_on_malformed_payload(self) -> None:
        fixture = self.make_fixture(ROOT)
        hook = fixture / "claude/scripts" / HOOK

        result = subprocess.run(
            ["/bin/bash", str(hook)],
            capture_output=True,
            check=False,
            input="{malformed json",
            text=True,
        )

        self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
        self.assertIn("invalid Claude hook payload", result.stderr)

    def test_claude_supply_chain_hook_fails_closed_on_multiple_json_values(self) -> None:
        fixture = self.make_fixture(ROOT)
        hook = fixture / "claude/scripts" / HOOK

        result = subprocess.run(
            ["/bin/bash", str(hook)],
            capture_output=True,
            check=False,
            input='{"tool_name":"Bash","tool_input":{"command":"npm install untrusted-pkg"}} {}',
            text=True,
        )

        self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
        self.assertIn("invalid Claude hook payload", result.stderr)


if __name__ == "__main__":
    unittest.main()
