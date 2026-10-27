"""Read-only contribution scouting. All credentials/networking belong to Ledge.

Upstream comments are evidence only, never instructions to execute. Ambiguous or
incomplete checks hold a candidate instead of manufacturing a recommendation.
"""
import hashlib
import re
from datetime import datetime, timedelta, timezone
from ledge_sdk import RunResult, run


def eligibility(evidence, config, pulls):
    issue = evidence.get("issue", {})
    reasons = []
    if issue.get("state") != "open" or issue.get("pull_request") or issue.get("locked"):
        return {"status": "fail", "reasons": ["Issue is closed, locked or a pull request"]}
    if issue.get("assignees") or evidence.get("assignedActors", {}).get("totalCount", 0) > 0:
        return {"status": "fail", "reasons": ["Issue already has an assigned actor"]}
    labels = {v.get("name", "").lower() if isinstance(v, dict) else v.lower() for v in issue.get("labels", [])}
    excluded = {v.lower() for v in config.get("excludeLabels", ["blocked", "needs triage", "in progress", "wontfix"])}
    if labels & excluded: return {"status": "fail", "reasons": ["Repository exclusion label"]}
    if evidence.get("complete") is not True or evidence.get("assignedActors", {}).get("totalCount") is None:
        return {"status": "unknown", "reasons": ["Assignment, comments or PR evidence incomplete"]}
    closure = evidence.get("closingPullRequests", {})
    if closure.get("pageInfo", {}).get("hasNextPage"):
        return {"status": "unknown", "reasons": ["Closing PR pagination incomplete"]}
    if any(pr.get("state", "").lower() == "open" for pr in closure.get("nodes", [])):
        return {"status": "fail", "reasons": ["An open pull request is linked to close this issue"]}
    for item in evidence.get("timeline", []):
        source = item.get("source", {}).get("issue", {})
        if source.get("pull_request") and source.get("state") == "open":
            return {"status": "unknown", "reasons": ["Related open PR needs overlap review"]}
    number = str(issue.get("number"))
    exact = re.compile(r"(?:close[sd]?|fix(?:e[sd])?|resolve[sd]?)\s+(?:https://github\.com/[^\s]+/issues/)?#?" + number + r"\b", re.I)
    if any(exact.search(pr.get("body") or "") for pr in pulls):
        return {"status": "fail", "reasons": ["Open PR references a fix for this issue"]}
    comments = evidence.get("comments", [])
    claim = re.compile(r"\b(i(?:'m| am)|we(?:'re| are))\s+(working on|taking|handling)\b|\bi(?:'ll| will)\s+(take|work on)\b", re.I)
    if any(claim.search(c.get("body") or "") for c in comments):
        return {"status": "unknown", "reasons": ["An informal work claim needs review"]}
    invited = labels & {v.lower() for v in config.get("labelsAny", ["good first issue", "help wanted"])}
    trusted = labels & {v.lower() for v in config.get("trustedTriageLabels", [])}
    accepted = re.compile(r"welcome|go ahead|approved|accepted|please.{0,40}pull request|happy.{0,30}contribut", re.I)
    handles = set(config.get("trustedMaintainers", []))
    affirmative = any(c.get("user", {}).get("login") in handles and accepted.search(c.get("body") or "") for c in comments)
    if not invited and not affirmative:
        return {"status": "fail", "reasons": ["No configured contribution invitation"]}
    if not trusted and not affirmative:
        return {"status": "unknown", "reasons": ["Configure trusted repository triage evidence"]}
    since = config.get("createdSince")
    if since and issue.get("created_at", "") < since:
        return {"status": "fail", "reasons": ["Older than the configured creation window"]}
    text = (issue.get("title", "") + " " + (issue.get("body") or "")).lower()
    if re.search(r"\b(meta issue|tracking issue|umbrella issue|epic)\b", text):
        return {"status": "fail", "reasons": ["Broad tracking scope"]}
    reasons.extend(["Unassigned, including agent assignments", "Repository triage evidence", "No known open PR overlap in checked sources"])
    return {"status": "pass", "reasons": reasons}


def ranking(issue, config):
    text = (issue.get("title", "") + " " + (issue.get("body") or "")).lower()
    score = 30  # explicit contribution invitation (20) + selected repository (10)
    reasons = ["Configured invitation +20", "Selected repository +10"]
    if any(keyword.lower() in text for keyword in config.get("keywords", [])):
        score += 35; reasons.append("Your configured domain keywords +35")
    if any(word in text for word in ("reproduce", "regression test", "expected", "steps")):
        score += 25; reasons.append("Concrete reproduction/test guidance +25")
    return score, reasons


def _collection(repository):
    return "issues." + hashlib.sha256(repository.encode()).hexdigest()[:16]


def _records(ctx, collection):
    values, after = {}, ""
    for _ in range(500):
        page = ctx.query_records(collection, after=after)
        if not page: break
        for item in page: values[item["key"]] = item.get("value") or {}
        after = page[-1]["key"]
        # The host may end a page early at its byte budget. Only an empty page
        # proves exhaustion; count alone would silently drop later records.
    return values


def scan(ctx):
    repositories = ctx.config.get("repositories", [])
    if not repositories or len(repositories) > 10: raise ValueError("Choose 1–10 repositories")
    state = {"repositories": dict(ctx.initial_state.get("repositories", {}))}
    events, mutations, coverage = [], [], []
    enriched = 0
    for repo in repositories:
        if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", repo): raise ValueError("Invalid repository")
        checkpoint = dict(state["repositories"].get(repo, {}))
        checkpoint.setdefault("baselineComplete", False)
        baseline = not checkpoint.get("baselineComplete", False)
        collection = _collection(repo)
        records = _records(ctx, collection)
        event_start = len(events)
        try:
            params = {"repository": repo, "page": checkpoint.get("page", 1)}
            if checkpoint.get("watermark"):
                watermark = datetime.fromisoformat(checkpoint["watermark"].replace("Z", "+00:00")) - timedelta(minutes=5)
                params["since"] = watermark.isoformat().replace("+00:00", "Z")
            response = ctx.integration("github.issues.listUpdated", **params)
            checkpoint.setdefault("scanStartedAt", ctx.now)
            discovered = response.get("data")
            if not isinstance(discovered, list): raise ValueError("Incomplete issue discovery")
            offset = checkpoint.get("offset", 0)
            budget = max(0, 50 - len(mutations))
            chunk = discovered[offset:offset + budget]
            changed = {}
            for issue in chunk:
                if "pull_request" in issue: continue
                key = issue.get("node_id") or str(issue["number"])
                previous = records.get(key, {})
                record = dict(previous, number=issue["number"], pending=True)
                record.setdefault("firstSeenDuringBaseline", baseline)
                records[key] = record; changed[key] = record
            if offset + len(chunk) < len(discovered):
                checkpoint["offset"] = offset + len(chunk)
            elif response.get("hasNext"):
                checkpoint["page"] = params["page"] + 1; checkpoint["offset"] = 0
            else:
                checkpoint.update(baselineComplete=True, watermark=checkpoint.pop("scanStartedAt"), page=1, offset=0)
            pulls, complete = [], True
            for page in range(1, 6):
                result = ctx.integration("github.pullRequests.findOverlap", repository=repo, page=page)
                pulls.extend(result.get("data", []))
                if not result.get("hasNext"): break
            else: complete = False
            for key, record in records.items():
                if not record.get("pending") or enriched >= 20 or (key not in changed and len(changed) + len(mutations) >= 50): continue
                evidence = ctx.integration("github.issues.getEvidence", repository=repo, number=record["number"])
                enriched += 1
                if not complete: evidence = dict(evidence, complete=False)
                decision = eligibility(evidence, ctx.config, pulls)
                first_evaluation = not record.get("evaluated")
                record.update(evaluated=bool(record.get("evaluated")) or decision["status"] != "unknown", status=decision["status"], reason="; ".join(decision["reasons"]))
                record["pending"] = decision["status"] == "unknown"
                issue = evidence.get("issue", {})
                score, score_reasons = ranking(issue, ctx.config)
                suppressed = first_evaluation and record.get("firstSeenDuringBaseline") and ctx.config.get("firstRun", "baseline") == "baseline"
                if decision["status"] == "pass" and score >= ctx.config.get("minimumScore", 70):
                    if suppressed: record["notified"] = True
                    elif not record.get("notified"):
                        url = issue.get("html_url", "")
                        events.append({"sourceKey": f"github:{repo}:{key}", "title": f"{repo} #{record['number']} · {issue.get('title', '')[:180]}", "body": f"Match {score}/100 · " + "; ".join(decision["reasons"] + score_reasons) + f" · Checked {evidence.get('checkedAt', ctx.now)}", "sensitivity": "sensitive", "actions": [{"id": "open", "label": "Review on GitHub", "url": url}], "evidence": [url]})
                        record["notified"] = True
                changed[key] = record
            for key, value in changed.items(): mutations.append({"collection": collection, "key": key, "value": value})
            state["repositories"][repo] = checkpoint
            coverage.append(repo + (": watching" if checkpoint.get("baselineComplete") else ": initializing"))
        except Exception as error:
            # Preserve the previous partition checkpoint on failure. Other complete
            # repositories may commit; the summary never calls partial data empty.
            del events[event_start:]
            coverage.append(repo + ": incomplete (" + type(error).__name__ + ")")
        if len(mutations) >= 50: break
    return RunResult(events=events, state=state, record_mutations=mutations, summary="; ".join(coverage))




def app_scan(ctx):
    from dataclasses import replace
    import time
    if ctx.command == "review":
        repo, number = ctx.arguments["repository"], ctx.arguments["number"]
        if repo not in ctx.config["repositories"]: raise ValueError("Repository not configured")
        evidence = ctx.integration("github.issues.getEvidence", repository=repo, number=number)
        pulls = ctx.integration("github.pullRequests.findOverlap", repository=repo, page=1)
        if pulls.get("hasNext"): evidence = dict(evidence, complete=False)
        decision = eligibility(evidence, ctx.config, pulls.get("data", []))
        result = RunResult(summary=decision["status"])
        rows = [{"id": "decision", "kind": "badge", "text": decision["status"]},
                {"id": "reason", "kind": "text", "text": "; ".join(decision["reasons"])},
                {"id": "url", "kind": "text", "text": f"https://github.com/{repo}/issues/{number}"}]
    else:
        result = scan(ctx)
        # A durable historical alert must not imply the issue is still free.
        # Actions fetch fresh evidence instead of directly opening an old URL.
        for event in result.events:
            url = (event.get("actions") or [{}])[0].get("url", "")
            match = re.fullmatch(r"https://github\.com/([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)/issues/([0-9]+)", url)
            event["actions"] = ([{"id": "review", "label": "Recheck eligibility", "command": "review", "arguments": {"repository": match[1], "number": int(match[2])}}] if match and match[1] in ctx.config["repositories"] else [])
        rows = [{"id": "coverage", "kind": "text", "text": result.summary or "No completed coverage"}]
        repositories = {_collection(repo): repo for repo in ctx.config["repositories"]}
        for mutation in result.record_mutations:
            value = mutation.get("value") or {}
            if value.get("status") != "pass" or len(rows) >= 35: continue
            repo = repositories.get(mutation["collection"])
            rows.append({"id": "issue" + str(len(rows)), "kind": "section", "text": f"{repo} #{value['number']}", "children": [
                {"id": "reason" + str(len(rows)), "kind": "text", "text": value.get("reason", "")},
                {"id": "review" + str(len(rows)), "kind": "button", "text": "Recheck contribution status", "command": "review", "arguments": {"repository": repo, "number": value["number"]}}]})
    presentation = {"protocolVersion": 2, "instanceID": ctx.automation_id, "viewID": "main", "revision": ctx.state_revision + 1, "sensitivity": "sensitive", "root": {"id": "opportunities", "kind": "section", "text": "Contribution opportunities", "children": rows}}
    return replace(result, view_snapshot={"presentation": presentation, "checkedAt": ctx.now})

if __name__ == "__main__": run(app_scan)
