"""Regression tests for fail-closed security-hook mirror checks."""

import json
import shlex
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
        self.assertEqual(command, f"bash {shlex.quote(str(hook_file))}")

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

    def test_non_executable_claude_hook_fails(self) -> None:
        fixture = self.make_fixture(ROOT)
        (fixture / "claude/scripts" / HOOK).chmod(0o644)

        result = run_audit(fixture)

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Missing or non-executable required Claude mirror", result.stdout)


if __name__ == "__main__":
    unittest.main()
