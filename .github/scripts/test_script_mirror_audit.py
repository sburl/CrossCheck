"""Regression tests for fail-closed security-hook mirror checks."""

import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
HOOK = "preuse-supply-chain-gate.sh"
HOOK_INSTALLER = ROOT / "claude/scripts/install-supply-chain-hook.sh"


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
        settings = fixture / "settings.json"
        hook_file = fixture / "claude/scripts" / HOOK
        original = {
            "hooks": {"PreToolUse": [
                {
                    "matcher": "Bash",
                    "hooks": [{"type": "command", "command": "bash old/preuse-supply-chain-gate.sh"}],
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
        updated = json.loads(settings.read_text())
        self.assertEqual(updated["custom"], {"retained": True})
        self.assertEqual(updated["hooks"]["PreToolUse"][1], original["hooks"]["PreToolUse"][1])
        command = updated["hooks"]["PreToolUse"][0]["hooks"][0]["command"]
        self.assertIn("bash -c", command)
        self.assertIn(r"exit\ 2", command)

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

        fresh_settings = fixture / "fresh-settings.json"
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

    def test_filename_mention_in_other_matcher_is_preserved_and_bash_is_added(self) -> None:
        fixture = self.make_fixture(ROOT)
        settings = fixture / "settings.json"
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

    def test_symlinked_settings_target_is_updated_without_replacing_symlink(self) -> None:
        fixture = self.make_fixture(ROOT)
        target = fixture / "settings-target.json"
        target.write_text("{}")
        target.chmod(0o640)
        settings = fixture / "settings.json"
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


if __name__ == "__main__":
    unittest.main()
