import json
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]


class EvidenceGateTests(unittest.TestCase):
    def invoke(self, script: str, option: str, document: dict) -> subprocess.CompletedProcess:
        with tempfile.TemporaryDirectory(prefix="ledge-gate-") as temporary:
            fixture = Path(temporary) / "fixture.json"
            fixture.write_text(json.dumps(document), encoding="utf-8")
            return subprocess.run(
                [str(ROOT / "Scripts" / script), option, str(fixture)],
                cwd=ROOT, text=True, capture_output=True, check=False,
            )

    @staticmethod
    def target(name: str, covered: int, executable: int) -> dict:
        return {
            "name": name, "coveredLines": covered, "executableLines": executable,
            "files": [{"name": f"{name}.swift", "coveredLines": covered,
                       "executableLines": executable}],
        }

    def test_coverage_uses_every_product_target(self):
        result = self.invoke("check-coverage.sh", "--report-json", {
            "targets": [self.target("Ledge.app", 10, 10),
                        self.target("LedgeKit", 0, 10)]
        })
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("LedgeKit: 0/10", result.stdout)

    def test_test_bundles_are_explicitly_excluded(self):
        result = self.invoke("check-coverage.sh", "--report-json", {
            "targets": [self.target("Ledge.app", 8, 10),
                        self.target("LedgeUITests.xctest", 0, 10)]
        })
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("EXCLUDED LedgeUITests.xctest", result.stdout)

    def test_mismatched_target_and_file_lines_fail_closed(self):
        target = self.target("Ledge.app", 10, 10)
        target["coveredLines"] = 9
        result = self.invoke("check-coverage.sh", "--report-json", {"targets": [target]})
        self.assertEqual(result.returncode, 2, result.stdout + result.stderr)

    def test_empty_test_run_fails_even_with_passed_status(self):
        result = self.invoke("verify-test-targets.sh", "--summary-json", {
            "totalTestCount": 0, "passedTests": 0, "failedTests": 0, "result": "Passed"
        })
        self.assertNotEqual(result.returncode, 0)

    def test_nonzero_passed_test_run_is_accepted(self):
        result = self.invoke("verify-test-targets.sh", "--summary-json", {
            "totalTestCount": 2, "passedTests": 2, "failedTests": 0, "result": "Passed"
        })
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
