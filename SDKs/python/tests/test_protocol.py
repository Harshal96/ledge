import json
import os
from pathlib import Path
import subprocess
import sys
import unittest


SDK = Path(__file__).resolve().parents[1]
PROGRAM = Path(__file__).with_name("echo_program.py")


class ProtocolTests(unittest.TestCase):
    def launch(self):
        environment = dict(os.environ, PYTHONPATH=str(SDK))
        child = subprocess.Popen(
            [sys.executable, str(PROGRAM)], stdin=subprocess.PIPE,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, env=environment,
        )
        def cleanup():
            if child.poll() is None:
                child.kill()
            child.wait(timeout=5)
            for pipe in (child.stdin, child.stdout, child.stderr):
                pipe.close()
        self.addCleanup(cleanup)
        return child

    def test_bidirectional_run_uses_real_line_protocol(self):
        child = self.launch()
        child.stdin.write(json.dumps({
            "jsonrpc": "2.0", "id": "run", "method": "run",
            "params": {"runID": "r1", "automationID": "a1", "command": "scan",
                       "config": {}, "state": {}, "mode": "dryRun", "now": "2026-10-26T00:00:00Z",
                       "hostProtocol": "1"}
        }) + "\n")
        child.stdin.flush()
        integration_call = json.loads(child.stdout.readline())
        self.assertEqual(integration_call["method"], "host.integration.call")
        self.assertEqual(integration_call["params"], {
            "operation": "github.issues.listUpdated", "params": {"repository": "owner/repo", "page": 1}
        })
        child.stdin.write(json.dumps({"jsonrpc": "2.0", "id": integration_call["id"],
                                      "result": {"data": [{"title": "Useful issue"}], "hasNext": False,
                                                 "checkedAt": "2026-10-26T00:00:00Z"}}) + "\n")
        child.stdin.flush()
        log_call = json.loads(child.stdout.readline())
        self.assertEqual(log_call["method"], "host.log")
        child.stdin.write(json.dumps({"jsonrpc": "2.0", "id": log_call["id"], "result": True}) + "\n")
        child.stdin.flush()
        final = json.loads(child.stdout.readline())
        self.assertEqual(final["id"], "run")
        self.assertEqual(final["result"]["events"][0]["title"], "Useful issue")
        self.assertEqual(final["result"]["recordMutations"][0]["collection"], "issues")
        self.assertEqual(final["result"]["summary"], "dryRun")
        self.assertEqual(child.wait(timeout=5), 0)

    def test_unsupported_protocol_fails_without_result(self):
        child = self.launch()
        output, _ = child.communicate(json.dumps({
            "jsonrpc": "2.0", "id": "run", "method": "run",
            "params": {"hostProtocol": "2"}
        }) + "\n", timeout=5)
        frames = [json.loads(line) for line in output.splitlines()]
        self.assertNotEqual(child.returncode, 0)
        self.assertEqual(frames[0]["id"], "run")
        self.assertIn("error", frames[0])

    def test_oversize_host_frame_fails_closed(self):
        child = self.launch()
        output, _ = child.communicate("x" * 262_145 + "\n", timeout=5)
        self.assertNotEqual(child.returncode, 0)
        self.assertNotIn("\"result\"", output)


if __name__ == "__main__":
    unittest.main()
