"""Protocol v1 over newline-delimited, bidirectional JSON-RPC 2.0.

The host owns identity, grants, persistence, scheduling, and credentials. This
module only transports one invocation and its scoped read requests.
"""

from __future__ import annotations

from dataclasses import dataclass, field
import json
import sys
from typing import Any, Callable, Mapping, TextIO


MAX_FRAME_BYTES = 262_144
MAX_CHILD_OUTPUT_BYTES = 2_097_152


class ProtocolError(Exception):
    pass


class HostError(ProtocolError):
    pass


def _unique_pairs(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise ProtocolError(f"duplicate JSON key: {key}")
        result[key] = value
    return result


class Channel:
    def __init__(self, source=None, destination=None):
        self.source = source or sys.stdin.buffer
        self.destination = destination or sys.stdout.buffer
        self.written = 0

    def read(self) -> dict[str, Any]:
        line = self.source.readline(MAX_FRAME_BYTES + 2)
        if not line or len(line) > MAX_FRAME_BYTES + 1 or not line.endswith(b"\n"):
            raise ProtocolError("missing, oversized, or unterminated JSON-RPC frame")
        if len(line) - 1 > MAX_FRAME_BYTES:
            raise ProtocolError("JSON-RPC frame exceeds 256 KiB")
        try:
            frame = json.loads(line, object_pairs_hook=_unique_pairs)
        except (UnicodeError, ValueError) as error:
            raise ProtocolError("invalid JSON-RPC JSON") from error
        if not isinstance(frame, dict) or frame.get("jsonrpc") != "2.0":
            raise ProtocolError("expected JSON-RPC 2.0 object")
        return frame

    def write(self, frame: Mapping[str, Any]) -> None:
        data = json.dumps(frame, separators=(",", ":"), ensure_ascii=False,
                          allow_nan=False).encode("utf-8")
        if len(data) > MAX_FRAME_BYTES:
            raise ProtocolError("JSON-RPC frame exceeds 256 KiB")
        self.written += len(data) + 1
        if self.written > MAX_CHILD_OUTPUT_BYTES:
            raise ProtocolError("child protocol output exceeds 2 MiB")
        self.destination.write(data + b"\n")
        self.destination.flush()


@dataclass(frozen=True)
class RunResult:
    events: list[dict[str, Any]] = field(default_factory=list)
    state: Any = None
    record_mutations: list[dict[str, Any]] = field(default_factory=list)
    summary: str | None = None
    view_snapshot: dict[str, Any] | None = None

    def to_wire(self) -> dict[str, Any]:
        result: dict[str, Any] = {
            "events": self.events, "recordMutations": self.record_mutations,
        }
        if self.state is not None:
            result["state"] = self.state
        if self.summary is not None:
            result["summary"] = self.summary
        if self.view_snapshot is not None:
            result["viewSnapshot"] = self.view_snapshot
        return result


class Context:
    def __init__(self, params: dict[str, Any], channel: Channel):
        if params.get("hostProtocol") not in ("1", "2"):
            raise ProtocolError("unsupported host protocol")
        for name in ("runID", "automationID", "command", "mode", "now"):
            if not isinstance(params.get(name), str):
                raise ProtocolError(f"missing {name}")
        if not isinstance(params.get("config"), dict):
            raise ProtocolError("config must be an object")
        self.run_id: str = params["runID"]
        self.automation_id: str = params["automationID"]
        self.command: str = params["command"]
        self.mode: str = params["mode"]
        self.now: str = params["now"]
        self.config: dict[str, Any] = params["config"]
        self.initial_state: Any = params.get("state", {})
        self.arguments: dict[str, Any] = params.get("arguments", {})
        revision = params.get("stateRevision", 0)
        if type(revision) is not int or revision < 0:
            raise ProtocolError("stateRevision must be a nonnegative integer")
        self.state_revision: int = revision
        self._channel = channel
        self._next_id = 1

    def request(self, method: str, params: Mapping[str, Any]) -> Any:
        request_id = self._next_id
        self._next_id += 1
        self._channel.write({"jsonrpc": "2.0", "id": request_id,
                             "method": method, "params": dict(params)})
        response = self._channel.read()
        if response.get("id") != request_id or "method" in response:
            raise ProtocolError("host response ID or shape mismatch")
        if "error" in response:
            error = response["error"]
            message = error.get("message", "host operation failed") if isinstance(error, dict) else "host operation failed"
            raise HostError(message)
        if "result" not in response:
            raise ProtocolError("host response has no result")
        return response["result"]

    def integration(self, operation: str, **params: Any) -> dict[str, Any]:
        result = self.request("host.integration.call", {"operation": operation, "params": params})
        if not isinstance(result, dict):
            raise ProtocolError("integration result is not an object")
        return result

    def get_state(self) -> Any:
        return self.request("host.state.get", {})

    def query_records(self, collection: str, after: str = "") -> list[dict[str, Any]]:
        result = self.request("host.records.query", {"collection": collection, "after": after})
        if not isinstance(result, list):
            raise ProtocolError("record query result is not an array")
        return result

    def log(self, message: str) -> None:
        self.request("host.log", {"message": message})


def run(handler: Callable[[Context], RunResult | Mapping[str, Any]]) -> None:
    """Serve exactly one host run. Stdout is reserved for protocol frames."""
    channel = Channel()
    request_id: Any = "run"
    try:
        request = channel.read()
        request_id = request.get("id", "run")
        if request.get("id") != "run" or request.get("method") != "run":
            raise ProtocolError("expected run request with id 'run'")
        params = request.get("params")
        if not isinstance(params, dict):
            raise ProtocolError("run params must be an object")
        result = handler(Context(params, channel))
        payload = result.to_wire() if isinstance(result, RunResult) else dict(result)
        if not isinstance(payload.get("events", []), list) or not isinstance(payload.get("recordMutations", []), list):
            raise ProtocolError("invalid run result")
        channel.write({"jsonrpc": "2.0", "id": request_id, "result": payload})
    except Exception as error:
        print(f"Ledge plugin failed: {type(error).__name__}", file=sys.stderr)
        try:
            channel.write({"jsonrpc": "2.0", "id": request_id,
                           "error": {"code": -32000, "message": "Plugin run failed"}})
        except Exception:
            pass
        raise SystemExit(1) from None
