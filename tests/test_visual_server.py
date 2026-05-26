from __future__ import annotations

import json
from pathlib import Path
from typing import Any, Callable

from fastapi.testclient import TestClient

from demo import visual_server as vs
from demo.agent import Agent, ModelConfig, Tool


class _Block:
    def __init__(self, **kw):
        for key, value in kw.items():
            setattr(self, key, value)


class _Usage:
    input_tokens = 10
    output_tokens = 5


class _Response:
    def __init__(self, content: list[_Block], stop_reason: str = "tool_use"):
        self.content = content
        self.stop_reason = stop_reason
        self.usage = _Usage()


def _tool_use(name: str, input_: dict[str, Any], *, idx: int = 0) -> _Block:
    return _Block(type="tool_use", id=f"toolu_{name}_{idx}", name=name,
                  input=input_)


def _text(text: str) -> _Block:
    return _Block(type="text", text=text)


Move = Callable[[list[dict], list[dict]], _Response]


class ScriptedClient:
    def __init__(self, moves: list[Move]):
        self._moves = list(moves)
        self._idx = 0

    @property
    def messages(self) -> "ScriptedClient":
        return self

    def create(self, **kw: Any) -> _Response:
        if self._idx >= len(self._moves):
            raise RuntimeError(f"ScriptedClient out of moves at {self._idx}")
        move = self._moves[self._idx]
        self._idx += 1
        return move(kw["messages"], kw.get("tools", []))


def _last_tool_result(messages: list[dict]) -> Any:
    for message in reversed(messages):
        if message.get("role") != "user":
            continue
        content = message.get("content", [])
        if not isinstance(content, list):
            continue
        for block in reversed(content):
            if isinstance(block, dict) and block.get("type") == "tool_result":
                raw = block["content"]
                try:
                    return json.loads(raw)
                except json.JSONDecodeError:
                    return raw
    return None


def _scan_tool_results(messages: list[dict]) -> list[Any]:
    out: list[Any] = []
    for message in messages:
        if message.get("role") != "user":
            continue
        content = message.get("content", [])
        if not isinstance(content, list):
            continue
        for block in content:
            if isinstance(block, dict) and block.get("type") == "tool_result":
                try:
                    out.append(json.loads(block["content"]))
                except json.JSONDecodeError:
                    out.append(block["content"])
    return out


def test_agent_event_sink_summarizes_tool_results_without_content():
    events: list[dict[str, Any]] = []

    def leak() -> str:
        return "token expired prematurely from raw pytest log"

    client = ScriptedClient([
        lambda _messages, _tools: _Response([_tool_use("leak", {}, idx=0)]),
        lambda _messages, _tools: _Response([_text("done")], "end_turn"),
    ])
    agent = Agent(
        name="probe",
        system="",
        tools=[Tool(
            name="leak",
            description="Return a sensitive-looking raw result.",
            input_schema={"type": "object", "properties": {}},
            fn=leak,
        )],
        config=ModelConfig(model="test-model"),
        client=client,
        event_sink=events.append,
    )

    result = agent.run("go")

    assert result.stop_reason == "end_turn"
    kinds = [event["kind"] for event in events]
    assert "tool_call" in kinds
    assert "tool_result" in kinds
    dumped = json.dumps(events)
    assert "token expired prematurely" not in dumped
    assert "content_chars" in dumped


def test_run_state_sanitizes_forbidden_payload_fields():
    state = vs.RunState(
        run_id="run_test",
        kind="pytest",
        target="auth_expiry",
        model="test-model",
    )
    state.add_event({
        "actor": "artifactstore",
        "kind": "artifact_created",
        "title": "raw",
        "summary": "created",
        "payload": {
            "artifact_id": "art_12345678",
            "raw_blob": "token expired prematurely",
            "nested": {"body": "token expired prematurely", "safe": "ok"},
            "items": [{"api_key": "secret", "span_id": "span_12345678"}],
        },
    })

    dumped = json.dumps(state.trace())
    assert "raw_blob" not in dumped
    assert "api_key" not in dumped
    assert "token expired prematurely" not in dumped
    assert "art_12345678" in dumped
    assert "span_12345678" in dumped


def test_run_endpoints_create_and_poll_events(monkeypatch):
    with vs.RUNS_LOCK:
        vs.RUNS.clear()

    def fake_start_run(request: vs.RunRequest) -> vs.RunState:
        state = vs.RunState(
            run_id="run_fake",
            kind=request.kind,
            target=request.target,
            model=request.model,
        )
        state.add_event({
            "actor": "system",
            "kind": "run_started",
            "title": "run_fake",
            "summary": "started",
            "payload": {"run_id": "run_fake"},
        })
        state.add_event({
            "actor": "artifactstore",
            "kind": "artifact_created",
            "title": "pytest_failure",
            "summary": "artifact created",
            "payload": {
                "artifact_id": "art_12345678",
                "raw_blob": "token expired prematurely",
            },
        })
        state.status = "succeeded"
        with vs.RUNS_LOCK:
            vs.RUNS[state.run_id] = state
        return state

    monkeypatch.setattr(vs, "start_run", fake_start_run)
    client = TestClient(vs.app)

    assert client.get("/health").json() == {"status": "ok"}
    created = client.post("/runs", json={
        "kind": "pytest",
        "target": "auth_expiry",
        "model": "deepseek-v4-pro",
    })
    assert created.status_code == 202
    assert created.json() == {"run_id": "run_fake", "status": "succeeded"}

    summary = client.get("/runs/run_fake").json()
    assert summary["status"] == "succeeded"
    all_events = client.get("/runs/run_fake/events").json()["events"]
    assert [event["seq"] for event in all_events] == [1, 2]
    new_events = client.get("/runs/run_fake/events?after=1").json()["events"]
    assert [event["seq"] for event in new_events] == [2]
    dumped = json.dumps(all_events)
    assert "raw_blob" not in dumped
    assert "token expired prematurely" not in dumped


def test_latest_trace_returns_404_when_no_trace(monkeypatch, tmp_path: Path):
    monkeypatch.setattr(vs, "TRACE_DIR", tmp_path)
    client = TestClient(vs.app)

    response = client.get("/traces/latest")

    assert response.status_code == 404


def sub_search(_messages, _tools):
    return _Response([_tool_use(
        "artifact_search",
        {"query": "expired token", "token_budget": 800},
        idx=0,
    )])


def sub_get_spans(messages, _tools):
    rows = _last_tool_result(messages)
    assert isinstance(rows, list) and rows
    return _Response([_tool_use(
        "artifact_get_spans",
        {"artifact_id": rows[0]["artifact_id"], "token_budget": 800},
        idx=1,
    )])


def sub_submit(messages, _tools):
    art_id: str | None = None
    spans: list[dict[str, Any]] | None = None
    for payload in _scan_tool_results(messages):
        if isinstance(payload, list) and payload and isinstance(payload[0], dict):
            if "artifact_id" in payload[0]:
                art_id = payload[0]["artifact_id"]
            if "span_id" in payload[0]:
                spans = payload
    assert art_id is not None
    assert spans
    citations = [f"{art_id}/{span['span_id']}" for span in spans[:2]]
    return _Response([_tool_use(
        "submit_report",
        {
            "diagnosis": "Timezone mismatch in token validation.",
            "citations": citations,
            "confidence": 0.9,
        },
        idx=2,
    )])


def sub_finalize(_messages, _tools):
    return _Response([_text("submitted")], "end_turn")


def sup_run_workload(_messages, _tools):
    return _Response([_tool_use(
        "run_workload",
        {"kind": "pytest", "target": "auth_expiry"},
        idx=0,
    )])


def sup_create_grant(_messages, _tools):
    return _Response([_tool_use(
        "create_grant",
        {
            "subject_agent_id": "diagnostic-subagent",
            "artifact_types": ["pytest_failure"],
            "allowed_views": ["preview", "evidence", "redacted"],
            "allowed_ops": ["search", "get_spans", "expand_view",
                            "find_related"],
            "max_tokens": 2500,
        },
        idx=1,
    )])


def sup_delegate(messages, _tools):
    grant = _last_tool_result(messages)
    assert isinstance(grant, dict)
    return _Response([_tool_use(
        "delegate",
        {"task": "Diagnose the pytest failure.", "grant_id": grant["grant_id"]},
        idx=2,
    )])


def sup_verify(messages, _tools):
    delegate_result = _last_tool_result(messages)
    assert isinstance(delegate_result, dict)
    citation = delegate_result["citations"][0]
    return _Response([_tool_use(
        "verify_citation",
        {"citation": citation},
        idx=3,
    )])


def sup_finalize(_messages, _tools):
    return _Response([_text(
        "Root cause: timezone-aware expiry compared with local naive now."
    )], "end_turn")


def test_visual_demo_scripted_run_emits_expected_safe_events(tmp_path: Path):
    state = vs.RunState(
        run_id="run_scripted",
        kind="pytest",
        target="auth_expiry",
        model="test-model",
    )

    vs.run_visual_demo(
        state,
        sup_client=ScriptedClient([
            sup_run_workload,
            sup_create_grant,
            sup_delegate,
            sup_verify,
            sup_finalize,
        ]),
        sub_client=ScriptedClient([
            sub_search,
            sub_get_spans,
            sub_submit,
            sub_finalize,
        ]),
        trace_dir=tmp_path,
    )

    assert state.status == "succeeded"
    kinds = {event["kind"] for event in state.events_after(0)}
    assert {
        "run_started",
        "artifact_created",
        "grant_created",
        "delegate_started",
        "citation_verified",
        "audit_recorded",
        "run_finished",
    } <= kinds
    trace_path = tmp_path / "run_scripted.json"
    assert trace_path.is_file()
    dumped = trace_path.read_text()
    assert "raw_blob" not in dumped
    assert "raw_text" not in dumped
    assert "token expired prematurely" not in dumped
