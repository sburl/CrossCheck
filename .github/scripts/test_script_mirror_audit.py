"""Regression tests for fail-closed security-hook mirror checks."""

from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
HOOK = "preuse-supply-chain-gate.sh"


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

    def test_non_executable_claude_hook_fails(self) -> None:
        fixture = self.make_fixture(ROOT)
        (fixture / "claude/scripts" / HOOK).chmod(0o644)

        result = run_audit(fixture)

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Missing or non-executable required Claude mirror", result.stdout)


if __name__ == "__main__":
    unittest.main()
