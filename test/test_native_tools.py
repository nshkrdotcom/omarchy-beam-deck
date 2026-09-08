"""Native tool contracts; component/unit coverage, not native-run claims."""
import importlib.util
import tempfile
from pathlib import Path
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]

def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module

class NativeTools(unittest.TestCase):
    def test_failure_evidence_preserves_identity_before_cleanup_and_rejects_payloads(self):
        runner = load("native_acceptance", ROOT / "scripts/native-acceptance.py")
        status = {"panel_open": False, "session_id": "epoch", "at_ms": 1,
                  "raw": "DO_NOT_KEEP", "budget_trial": {"status": "rollback_failed", "arbitrary": "DO_NOT_KEEP"}}
        prior = {"helper": {"pid": 42, "start_ticks": 7}, "shell": {"pid": 43, "start_ticks": 8}}
        with patch.object(runner, "status", return_value=status), patch.object(runner, "proc_stat", return_value=None):
            evidence = runner.failure_context(prior)
        self.assertEqual(evidence["last_known"], prior)
        self.assertIsNone(evidence["current_helper"])
        self.assertFalse(evidence["status"]["panel_open"])
        self.assertNotIn("DO_NOT_KEEP", str(evidence))

    def test_soak_rejects_lost_panel_epoch_and_stale_samples(self):
        runner = load("native_acceptance_checks", ROOT / "scripts/native-acceptance.py")
        s = {"panel_open": True, "session_id": "one", "at_ms": 1000, "provider": {"jobs": {"active": 2, "queued": 16}}}
        runner.check_live(s, "one", 2000)
        for changed in ({**s, "panel_open": False}, {**s, "session_id": "two"}, {**s, "at_ms": -20000}):
            with self.assertRaises(AssertionError): runner.check_live(changed, "one", 2000)

    @unittest.skipUnless(Path("/usr/lib/qt6/bin/qmllint").exists() and Path("/usr/share/omarchy/shell").exists(), "installed Qt/Omarchy needed for native import lint")
    def test_native_lint_maps_real_qs_root_and_rejects_missing_import(self):
        lint = load("beam_lint", ROOT / "scripts/lint-qml.py")
        with tempfile.TemporaryDirectory(prefix="beam-deck-lint-check-") as folder:
            root = Path(folder)
            valid = root / "Valid.qml"
            valid.write_text("import QtQuick\nimport qs.Commons\nItem {}\n")
            executable = "/usr/lib/qt6/bin/qmllint"
            self.assertEqual(lint.run(executable, Path("/usr/share/omarchy/shell"), [str(valid)]), 0)
            invalid = root / "Missing.qml"
            invalid.write_text("import QtQuick\nimport qs.DoesNotExist\nItem {}\n")
            self.assertNotEqual(lint.run(executable, Path("/usr/share/omarchy/shell"), [str(invalid)]), 0)
