"""An optional trusted app, not a command-execution feature in the Ledge GUI."""
import os
import selectors
import subprocess
import time
from ledge_sdk import RunResult, run


def execute(ctx):
    executable = ctx.config.get("executable", "")
    arguments = ctx.config.get("arguments", [])
    if not os.path.isabs(executable) or not isinstance(arguments, list) or not all(isinstance(v, str) for v in arguments):
        raise ValueError("Choose an absolute executable and argument array")
    if ctx.mode != "live":
        output, code = "Fixture preview: no external program was executed.", 0
    else:
        child = subprocess.Popen([executable] + arguments, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        chunks, size, deadline = [], 0, time.monotonic() + 100
        selector = selectors.DefaultSelector()
        selector.register(child.stdout, selectors.EVENT_READ)
        try:
            while selector.get_map():
                if time.monotonic() >= deadline: raise TimeoutError("Program exceeded 100 seconds")
                for key, _ in selector.select(timeout=0.25):
                    chunk = os.read(key.fd, 8192)
                    if not chunk: selector.unregister(key.fileobj); continue
                    size += len(chunk)
                    if size > 1_048_576: raise ValueError("Program output exceeded 1 MiB")
                    chunks.append(chunk)
            code = child.wait(timeout=max(0.1, deadline - time.monotonic()))
            output = b"".join(chunks).decode("utf-8", errors="replace")[-6000:]
        finally:
            selector.close(); child.stdout.close()
            if child.poll() is None: child.kill()
            child.wait(timeout=3)
    snapshot = {"presentation": {"protocolVersion": 2, "instanceID": ctx.automation_id, "viewID": "main", "revision": ctx.state_revision + 1, "sensitivity": "sensitive", "root": {"id": "result", "kind": "section", "text": "Program result", "children": [{"id": "status", "kind": "badge", "text": "Exit " + str(code)}, {"id": "output", "kind": "text", "text": output or "No output."}]}}, "checkedAt": ctx.now}
    return RunResult(summary="Program exited " + str(code), view_snapshot=snapshot)


if __name__ == "__main__": run(execute)
