"""FastAPI backend for the ArtifactStore visualizer.

The API is intentionally small and read-only from the iOS client's point of
view: start a deterministic demo run, poll run state, poll structured events,
or replay the latest saved trace. Raw tool output and provider credentials are
never included in event payloads.
"""
from __future__ import annotations

import json
import threading
import uuid
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from fastapi import FastAPI, HTTPException, Query
from pydantic import BaseModel, Field

from artifactstore import ArtifactStore
from demo.agent import Agent, DEFAULT_MODEL, ModelConfig
from demo.prompts import SUPERVISOR_SYSTEM
from demo.runner import _PROJECT_ROOT, _make_run_subagent, load_dotenv
from demo.tools import supervisor_tools
from demo.workloads import ViewPolicy

TRACE_DIR = _PROJECT_ROOT / "visual_traces"

EVENT_KINDS = {
    "run_started",
    "agent_text",
    "tool_call",
    "tool_result",
    "artifact_created",
    "grant_created",
    "delegate_started",
    "citation_verified",
    "audit_recorded",
    "run_finished",
    "error",
}

FORBIDDEN_KEYS = {
    "raw",
    "raw_blob",
    "raw_text",
    "body",
    "api_key",
    "deepseek_api_key",
    "qwen_api_key",
}
FORBIDDEN_STRING_MARKERS = (
    "DEEPSEEK_API_KEY",
    "QWEN_API_KEY",
    "api_key",
    "raw_blob",
    "raw_text",
)
MAX_STRING_CHARS = 2000


def _utc_now() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def _sanitize(value: Any) -> Any:
    if isinstance(value, dict):
        out: dict[str, Any] = {}
        for key, item in value.items():
            key_text = str(key)
            key_norm = key_text.lower()
            if key_norm in FORBIDDEN_KEYS or "api_key" in key_norm:
                continue
            out[key_text] = _sanitize(item)
        return out
    if isinstance(value, list):
        return [_sanitize(item) for item in value[:100]]
    if isinstance(value, tuple):
        return [_sanitize(item) for item in value[:100]]
    if isinstance(value, str):
        if any(marker in value for marker in FORBIDDEN_STRING_MARKERS):
            return "[redacted]"
        if len(value) > MAX_STRING_CHARS:
            return value[:MAX_STRING_CHARS] + "... [truncated]"
        return value
    if value is None or isinstance(value, (bool, int, float)):
        return value
    return str(value)[:MAX_STRING_CHARS]


def _new_run_id() -> str:
    stamp = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")
    return f"run_{stamp}_{uuid.uuid4().hex[:6]}"


class RunRequest(BaseModel):
    kind: str = Field(default="pytest")
    target: str = Field(default="auth_expiry")
    model: str = Field(default=DEFAULT_MODEL)


@dataclass
class RunState:
    run_id: str
    kind: str
    target: str
    model: str
    status: str = "running"
    turns: int = 0
    tool_calls: int = 0
    input_tokens: int = 0
    output_tokens: int = 0
    final_text: str | None = None
    error: str | None = None
    started_at: str = field(default_factory=_utc_now)
    finished_at: str | None = None
    events: list[dict[str, Any]] = field(default_factory=list)
    _next_seq: int = 1
    _lock: threading.Lock = field(default_factory=threading.Lock, repr=False)

    def add_event(self, event: dict[str, Any]) -> dict[str, Any]:
        kind = str(event.get("kind") or "agent_text")
        if kind not in EVENT_KINDS:
            kind = "agent_text"
        payload = _sanitize(event.get("payload") or {})
        row = {
            "seq": 0,
            "timestamp": _utc_now(),
            "actor": str(event.get("actor") or "system")[:80],
            "kind": kind,
            "title": str(event.get("title") or kind)[:160],
            "summary": _sanitize(str(event.get("summary") or "")),
            "payload": payload,
        }
        with self._lock:
            row["seq"] = self._next_seq
            self._next_seq += 1
            self.events.append(row)
        return row

    def complete(self, result) -> None:
        with self._lock:
            self.status = "succeeded"
            self.turns = result.turns
            self.tool_calls = result.tool_calls
            self.input_tokens = result.input_tokens
            self.output_tokens = result.output_tokens
            self.final_text = result.final_text
            self.finished_at = _utc_now()

    def fail(self, exc: Exception) -> None:
        with self._lock:
            self.status = "failed"
            self.error = f"{type(exc).__name__}: {exc}"
            self.finished_at = _utc_now()

    def summary(self) -> dict[str, Any]:
        with self._lock:
            return {
                "run_id": self.run_id,
                "status": self.status,
                "kind": self.kind,
                "target": self.target,
                "model": self.model,
                "turns": self.turns,
                "tool_calls": self.tool_calls,
                "input_tokens": self.input_tokens,
                "output_tokens": self.output_tokens,
                "final_text": _sanitize(self.final_text),
                "error": _sanitize(self.error),
                "started_at": self.started_at,
                "finished_at": self.finished_at,
            }

    def events_after(self, seq: int) -> list[dict[str, Any]]:
        with self._lock:
            return [dict(event) for event in self.events if event["seq"] > seq]

    def trace(self) -> dict[str, Any]:
        return {
            "run": self.summary(),
            "events": self.events_after(0),
        }


RUNS: dict[str, RunState] = {}
RUNS_LOCK = threading.Lock()

app = FastAPI(title="ArtifactStore Visualizer API")


def write_trace(state: RunState, trace_dir: Path | None = None) -> Path:
    target_dir = trace_dir or TRACE_DIR
    target_dir.mkdir(parents=True, exist_ok=True)
    path = target_dir / f"{state.run_id}.json"
    path.write_text(json.dumps(state.trace(), indent=2, sort_keys=True) + "\n")
    return path


def run_visual_demo(
    state: RunState,
    *,
    sup_client: Any | None = None,
    sub_client: Any | None = None,
    trace_dir: Path | None = None,
) -> None:
    active_trace_dir = trace_dir or TRACE_DIR
    try:
        load_dotenv(override=True)
        state.add_event({
            "actor": "system",
            "kind": "run_started",
            "title": state.run_id,
            "summary": f"Started {state.kind}/{state.target}",
            "payload": {
                "run_id": state.run_id,
                "kind": state.kind,
                "target": state.target,
                "model": state.model,
            },
        })

        active_trace_dir.mkdir(parents=True, exist_ok=True)
        store = ArtifactStore.init(active_trace_dir / f"{state.run_id}.sqlite")
        run_subagent = _make_run_subagent(
            store,
            model=state.model,
            verbose=False,
            client=sub_client,
            event_sink=state.add_event,
        )
        supervisor = Agent(
            name="supervisor",
            system=SUPERVISOR_SYSTEM,
            tools=supervisor_tools(
                store,
                session_id=state.run_id,
                issuer_agent_id="supervisor",
                run_subagent=run_subagent,
                policy=ViewPolicy.ARTIFACT,
                event_sink=state.add_event,
            ),
            config=ModelConfig(model=state.model),
            client=sup_client,
            verbose=False,
            event_sink=state.add_event,
        )

        task = (
            f"Run the {state.kind} workload on target '{state.target}'. "
            "Identify the root cause of any failure. Delegate the diagnosis "
            "to a subagent under the narrowest grant possible. Verify every "
            "citation in the subagent's report by calling verify_citation. "
            "Produce a final answer."
        )
        result = supervisor.run(task)
        state.complete(result)
        state.add_event({
            "actor": "system",
            "kind": "run_finished",
            "title": state.run_id,
            "summary": f"Run {state.run_id} finished with status succeeded",
            "payload": {
                "run_id": state.run_id,
                "status": state.status,
                "turns": state.turns,
                "tool_calls": state.tool_calls,
                "input_tokens": state.input_tokens,
                "output_tokens": state.output_tokens,
            },
        })
    except Exception as exc:  # noqa: BLE001 - expose as run failure
        state.fail(exc)
        state.add_event({
            "actor": "system",
            "kind": "error",
            "title": type(exc).__name__,
            "summary": f"Run {state.run_id} failed",
            "payload": {"error_type": type(exc).__name__},
        })
    finally:
        write_trace(state, active_trace_dir)


def start_run(request: RunRequest) -> RunState:
    from demo.providers import ProviderError, resolve_model_shorthand
    try:
        model = resolve_model_shorthand(request.model)
    except ProviderError as exc:
        raise ValueError(str(exc)) from exc

    state = RunState(
        run_id=_new_run_id(),
        kind=request.kind,
        target=request.target,
        model=model,
    )
    with RUNS_LOCK:
        RUNS[state.run_id] = state
    thread = threading.Thread(
        target=run_visual_demo,
        args=(state,),
        name=f"visual-demo-{state.run_id}",
        daemon=True,
    )
    thread.start()
    return state


def _get_run(run_id: str) -> RunState:
    with RUNS_LOCK:
        state = RUNS.get(run_id)
    if state is None:
        raise HTTPException(status_code=404, detail="run not found")
    return state


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


@app.post("/runs", status_code=202)
def create_run(request: RunRequest) -> dict[str, str]:
    try:
        state = start_run(request)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return {"run_id": state.run_id, "status": state.status}


@app.get("/runs/{run_id}")
def get_run(run_id: str) -> dict[str, Any]:
    return _get_run(run_id).summary()


@app.get("/runs/{run_id}/events")
def get_events(run_id: str, after: int = Query(default=0, ge=0)) -> dict[str, Any]:
    return {"events": _get_run(run_id).events_after(after)}


@app.get("/traces/latest")
def latest_trace() -> dict[str, Any]:
    if not TRACE_DIR.exists():
        raise HTTPException(status_code=404, detail="no traces found")
    traces = sorted(
        TRACE_DIR.glob("run_*.json"),
        key=lambda p: p.stat().st_mtime,
        reverse=True,
    )
    if not traces:
        raise HTTPException(status_code=404, detail="no traces found")
    return json.loads(traces[0].read_text())
