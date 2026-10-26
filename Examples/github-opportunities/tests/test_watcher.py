import importlib.util
import pathlib
import sys
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path[:0] = [str(ROOT), str(ROOT.parents[1] / "SDKs/python")]
from watch import eligibility, scan


def evidence(**changes):
    value = {
        "issue": {"node_id": "I_1", "number": 1, "title": "Fix parser validation", "state": "open", "assignees": [], "labels": [{"name": "good first issue"}], "html_url": "https://github.com/owner/repo/issues/1", "body": "Steps to reproduce. Add a focused regression test."},
        "comments": [], "timeline": [], "complete": True,
        "assignedActors": {"totalCount": 0},
        "closingPullRequests": {"nodes": [], "pageInfo": {"hasNextPage": False}},
    }
    value.update(changes)
    return value


class Context:
    now = "2026-10-26T10:00:00Z"
    mode = "preview"
    command = "scan"
    config = {"repositories": ["owner/repo"], "labelsAny": ["good first issue"], "trustedTriageLabels": ["good first issue"], "keywords": ["parser"], "minimumScore": 70}
    def __init__(self, state=None, records=None):
        self.initial_state = state or {}
        self.records = records or []
    def query_records(self, collection, after=""):
        return [r for r in self.records if r["collection"] == collection and r["key"] > after][:100]
    def integration(self, operation, **params):
        if operation == "github.issues.getEvidence": return evidence()
        if operation == "github.pullRequests.findOverlap": return {"data": [], "hasNext": False}
        return {"data": [evidence()["issue"]], "hasNext": False}


class WatcherTests(unittest.TestCase):
    def test_unknown_assignment_or_truncated_evidence_is_held(self):
        self.assertEqual(eligibility(evidence(complete=False), Context.config, [])["status"], "unknown")
        self.assertEqual(eligibility(evidence(assignedActors={}), Context.config, [])["status"], "unknown")
    def test_agent_assignment_and_open_pr_veto(self):
        self.assertEqual(eligibility(evidence(assignedActors={"totalCount": 1}), Context.config, [])["status"], "fail")
        self.assertEqual(eligibility(evidence(closingPullRequests={"nodes": [{"state": "OPEN"}]}), Context.config, [])["status"], "fail")
    def test_labels_need_explicit_trusted_triage_policy(self):
        self.assertEqual(eligibility(evidence(), {"labelsAny": ["good first issue"]}, [])["status"], "unknown")
        self.assertEqual(eligibility(evidence(), Context.config, [])["status"], "pass")
    def test_informal_claim_holds_candidate(self):
        self.assertNotEqual(eligibility(evidence(comments=[{"body": "I am working on this issue", "user": {"login": "someone"}}]), Context.config, [])["status"], "pass")
    def test_first_scan_baselines_quietly_then_new_match_alerts_once(self):
        baseline = scan(Context())
        self.assertEqual(baseline.events, [])
        second = scan(Context(state=baseline.state, records=baseline.record_mutations))
        self.assertEqual(second.events, [])
        new_context = Context(state=baseline.state)
        fresh = scan(new_context)
        self.assertEqual(len(fresh.events), 1)
        again = scan(Context(state=fresh.state, records=fresh.record_mutations))
        self.assertEqual(again.events, [])
    def test_incomplete_baseline_keeps_watermark(self):
        class Paged(Context):
            def integration(self, operation, **params):
                response = super().integration(operation, **params)
                if operation == "github.issues.listUpdated": response["hasNext"] = True
                return response
        result = scan(Paged())
        self.assertFalse(result.state["repositories"]["owner/repo"]["baselineComplete"])
        self.assertNotIn("watermark", result.state["repositories"]["owner/repo"])

    def test_unknown_baseline_resolves_quietly(self):
        class Incomplete(Context):
            def integration(self, operation, **params):
                if operation == "github.issues.getEvidence": return evidence(complete=False)
                return super().integration(operation, **params)
        first = scan(Incomplete())
        later = scan(Context(state=first.state, records=first.record_mutations))
        self.assertEqual(first.events, [])
        self.assertEqual(later.events, [])

if __name__ == "__main__": unittest.main()
