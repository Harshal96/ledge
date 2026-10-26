from ledge_sdk import RunResult, run


def handler(ctx):
    response = ctx.integration("github.issues.listUpdated", repository="owner/repo", page=1)
    ctx.log("fixture run")
    return RunResult(
        events=[{"sourceKey": "issue/1", "title": response["data"][0]["title"]}],
        state={"last": 1},
        record_mutations=[{"collection": "issues", "key": "1", "value": {"seen": True}}],
        summary=ctx.mode,
    )


if __name__ == "__main__":
    run(handler)
