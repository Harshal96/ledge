from ledge_sdk import RunResult, run


def scan(ctx):
    state = dict(ctx.initial_state or {})
    events, rows, coverage = [], [], []
    for repo in ctx.config["repositories"]:
        event_start, row_start = len(events), len(rows)
        try:
            response = ctx.integration("github.actions.listRuns", repository=repo, branch=ctx.config["branch"], page=1)
            runs = response.get("data", {}).get("workflow_runs")
            if not isinstance(runs, list): raise ValueError("Incomplete workflow response")
            previous = state.get(repo)
            current = {}
            for item in runs[:100]:
                key = str(item["id"]) + ":" + str(item.get("run_attempt", 1))
                status = item.get("status", "unknown")
                current[key] = status
                conclusion = item.get("conclusion") or status
                if previous is not None and status == "completed" and previous.get(key) != "completed":
                    events.append({"sourceKey": "ci:" + repo + ":" + key, "title": (repo + " · " + str(item.get("name") or "Workflow"))[:200], "body": "Workflow " + conclusion, "sensitivity": "sensitive", "actions": [{"id": "open", "label": "View run", "url": item["html_url"]}]})
                if len(rows) < 20:
                    rows.append({"id": "run" + str(len(rows)), "kind": "text", "text": repo + " · " + str(item.get("name") or "Workflow")[:100] + " · " + conclusion})
            state[repo] = current
            coverage.append(repo + ": latest 100 runs checked" + ("; older runs outside coverage" if response.get("hasNext") else ""))
        except Exception as error:
            del events[event_start:]
            del rows[row_start:]
            coverage.append(repo + ": incomplete (" + type(error).__name__ + ")")
    snapshot = {"presentation": {"protocolVersion": 2, "instanceID": ctx.automation_id, "viewID": "main", "revision": ctx.state_revision + 1, "sensitivity": "sensitive", "root": {"id": "workflows", "kind": "section", "text": "Workflow runs", "children": rows or [{"id": "empty", "kind": "text", "text": "; ".join(coverage)}]}}, "checkedAt": ctx.now}
    return RunResult(events=events, state=state, summary="; ".join(coverage), view_snapshot=snapshot)


if __name__ == "__main__": run(scan)
