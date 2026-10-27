"""Offline app fixtures: no credentials, real HTTP or arbitrary commands."""
import importlib.util
from pathlib import Path
from types import SimpleNamespace
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]


def load(name):
    spec = importlib.util.spec_from_file_location(name.replace('-', '_'), ROOT / name / 'main.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def context(**overrides):
    values = dict(config={}, initial_state={}, state_revision=7, automation_id='fixture',
                  now='2026-10-27T00:00:00Z', mode='preview', command='run', arguments={})
    values.update(overrides)
    return SimpleNamespace(**values)


class AppTests(unittest.TestCase):
    def test_command_preview_does_not_execute_and_revision_uses_host_clock(self):
        app = load('command-result')
        with patch.object(app.subprocess, 'Popen', side_effect=AssertionError('No external command')):
            result = app.execute(context(config={'executable': '/bin/echo', 'arguments': ['hello']}))
        self.assertIn('no external program', result.view_snapshot['presentation']['root']['children'][1]['text'])
        self.assertEqual(result.view_snapshot['presentation']['revision'], 8)

    def test_ci_quiet_baseline_then_one_completion(self):
        app = load('github-ci')
        runs = [{'id': 1, 'name': 'Tests', 'status': 'in_progress', 'html_url': 'https://github.com/o/r/actions/runs/1'}]
        ctx = context(config={'repositories': ['o/r'], 'branch': 'main'}, integration=lambda *a, **k: {'data': {'workflow_runs': runs}})
        baseline = app.scan(ctx)
        self.assertEqual(baseline.events, [])
        ctx.initial_state = baseline.state
        runs[0]['status'] = 'completed'
        runs[0]['conclusion'] = 'success'
        result = app.scan(ctx)
        self.assertEqual(len(result.events), 1)
        ctx.initial_state = result.state
        self.assertEqual(app.scan(ctx).events, [])
        self.assertEqual(result.view_snapshot['presentation']['revision'], 8)

    def test_ci_incomplete_partition_cannot_emit_or_advance(self):
        app = load('github-ci')
        runs = [{'id': 1, 'status': 'completed', 'conclusion': 'success', 'html_url': 'https://github.com/o/r/actions/runs/1'}, {'broken': True}]
        previous = {'o/r': {'1:1': 'in_progress'}}
        result = app.scan(context(config={'repositories': ['o/r'], 'branch': ''}, initial_state=previous, integration=lambda *a, **k: {'data': {'workflow_runs': runs}}))
        self.assertEqual(result.events, [])
        self.assertEqual(result.state, previous)
        self.assertIn('incomplete', result.summary)

    def test_opportunity_review_rechecks_and_rejects_foreign_repositories(self):
        app = load('github-opportunities')
        calls = []
        def integration(operation, **params):
            calls.append(operation)
            if operation == 'github.issues.getEvidence':
                return {'issue': {'state': 'closed'}}
            return {'data': [], 'hasNext': False}
        ctx = context(command='review', config={'repositories': ['o/r']}, arguments={'repository': 'o/r', 'number': 1}, integration=integration)
        result = app.app_scan(ctx)
        self.assertEqual(result.summary, 'fail')
        self.assertEqual(calls, ['github.issues.getEvidence', 'github.pullRequests.findOverlap'])
        self.assertEqual(result.view_snapshot['presentation']['revision'], 8)
        ctx.arguments['repository'] = 'other/repo'
        calls.clear()
        with self.assertRaises(ValueError): app.app_scan(ctx)
        self.assertEqual(calls, [])


if __name__ == '__main__': unittest.main()
