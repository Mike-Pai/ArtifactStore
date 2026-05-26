"""Tool surfaces for the demo.

Subagent tools are bound to a grant_id at construction time so the model
never sees a `grant_id` argument — the harness enforces scope, not the LLM.
Every call goes through ArtifactStore.* which logs to artifact_access_log.
"""
from __future__ import annotations

from dataclasses import asdict
from typing import Any, Callable

from artifactstore import ArtifactStore
from artifactstore.grants import AccessDenied
from artifactstore.tokens import estimate
from demo.agent import EventSink, Tool
from demo.workloads import ViewPolicy, WorkloadResult, run_workload


def _emit(event_sink: EventSink | None, *, actor: str, kind: str, title: str,
          summary: str, payload: dict[str, Any] | None = None) -> None:
    if event_sink is None:
        return
    try:
        event_sink({
            "actor": actor,
            "kind": kind,
            "title": title,
            "summary": summary,
            "payload": payload or {},
        })
    except Exception:
        return


def _read_payload(tool_name: str, grant_id: str, kw: dict[str, Any],
                  result: Any = None, *, allowed: bool,
                  exc: Exception | None = None) -> dict[str, Any]:
    op = tool_name.removeprefix("artifact_")
    payload: dict[str, Any] = {
        "tool_name": tool_name,
        "grant_id": grant_id,
        "operation": op,
        "allowed": allowed,
    }
    for key in ("artifact_id", "view"):
        if key in kw:
            payload[key] = kw[key]
    if isinstance(result, list):
        payload["result_count"] = len(result)
    elif isinstance(result, str):
        payload["result_chars"] = len(result)
        payload["result_tokens"] = estimate(result)
    elif isinstance(result, dict):
        payload["result_keys"] = sorted(
            k for k in result.keys()
            if k.lower() not in {"raw", "raw_blob", "raw_text", "body", "api_key"}
        )
    if exc is not None:
        payload["error_type"] = type(exc).__name__
        if isinstance(exc, AccessDenied):
            payload["denial_reason"] = str(exc)[:240]
    return payload


def _emit_read(event_sink: EventSink | None, *, actor: str, tool_name: str,
               grant_id: str, kw: dict[str, Any], result: Any = None,
               allowed: bool, exc: Exception | None = None) -> None:
    status = "allowed" if allowed else "denied"
    _emit(
        event_sink,
        actor=actor,
        kind="audit_recorded",
        title=tool_name,
        summary=f"{actor} {status} {tool_name}",
        payload=_read_payload(tool_name, grant_id, kw, result,
                              allowed=allowed, exc=exc),
    )


# --------- Subagent tools (gated by a single grant) ---------

def subagent_tools(
    store: ArtifactStore,
    grant_id: str,
    *,
    event_sink: EventSink | None = None,
) -> list[Tool]:
    def _call_read(tool_name: str, fn: Callable[..., Any], **kw: Any) -> Any:
        try:
            result = fn(**kw)
        except AccessDenied as exc:
            _emit_read(event_sink, actor="subagent", tool_name=tool_name,
                       grant_id=grant_id, kw=kw, allowed=False, exc=exc)
            raise
        _emit_read(event_sink, actor="subagent", tool_name=tool_name,
                   grant_id=grant_id, kw=kw, result=result, allowed=True)
        return result

    return [
        Tool(
            name="artifact_search",
            description="Full-text search over artifact previews and span text. "
                        "Returns a list of {artifact_id, type, preview, score}. "
                        "Use this first to locate evidence by keyword.",
            input_schema={
                "type": "object",
                "properties": {
                    "query": {"type": "string"},
                    "artifact_types": {"type": "array", "items": {"type": "string"}},
                    "limit": {"type": "integer", "default": 5},
                    "token_budget": {"type": "integer", "default": 800},
                },
                "required": ["query"],
            },
            fn=lambda **kw: _call_read(
                "artifact_search",
                lambda **inner: store.search(grant_id=grant_id, **inner),
                **kw,
            ),
        ),
        Tool(
            name="artifact_get_spans",
            description="Fetch typed evidence spans (assertion, stack_frame, "
                        "changed_line, error_message, ...) from one artifact.",
            input_schema={
                "type": "object",
                "properties": {
                    "artifact_id": {"type": "string"},
                    "span_types": {"type": "array", "items": {"type": "string"}},
                    "token_budget": {"type": "integer", "default": 800},
                },
                "required": ["artifact_id"],
            },
            fn=lambda **kw: _call_read(
                "artifact_get_spans",
                lambda **inner: store.get_spans(grant_id=grant_id, **inner),
                **kw,
            ),
        ),
        Tool(
            name="artifact_expand_view",
            description="Materialize a view of an artifact: 'preview' | 'evidence' "
                        "| 'redacted' | 'raw' | 'provenance'. 'raw' may be denied "
                        "by the grant.",
            input_schema={
                "type": "object",
                "properties": {
                    "artifact_id": {"type": "string"},
                    "view": {"type": "string",
                             "enum": ["preview", "evidence", "redacted", "raw", "provenance"]},
                    "token_budget": {"type": "integer", "default": 1500},
                },
                "required": ["artifact_id", "view"],
            },
            fn=lambda **kw: _call_read(
                "artifact_expand_view",
                lambda **inner: store.expand_view(grant_id=grant_id, **inner),
                **kw,
            ),
        ),
        Tool(
            name="artifact_find_related",
            description="Follow provenance/causal links from an artifact "
                        "(caused_by, derived_from, contains_evidence_for, ...).",
            input_schema={
                "type": "object",
                "properties": {
                    "artifact_id": {"type": "string"},
                    "relations": {"type": "array", "items": {"type": "string"}},
                },
                "required": ["artifact_id"],
            },
            fn=lambda **kw: _call_read(
                "artifact_find_related",
                lambda **inner: store.find_related(grant_id=grant_id, **inner),
                **kw,
            ),
        ),
        Tool(
            name="submit_report",
            description="Submit your final diagnosis. Calling this ends your turn. "
                        "Every claim MUST be backed by citations like 'art_xxx/span_y'.",
            input_schema={
                "type": "object",
                "properties": {
                    "diagnosis": {"type": "string"},
                    "citations": {"type": "array", "items": {"type": "string"}},
                    "confidence": {"type": "number", "minimum": 0, "maximum": 1},
                },
                "required": ["diagnosis", "citations"],
            },
            fn=lambda **kw: {"submitted": True, **kw},
        ),
    ]


# --------- Supervisor tools (run workloads + delegate) ---------


def supervisor_tools(
    store: ArtifactStore,
    *,
    session_id: str,
    issuer_agent_id: str,
    run_subagent: Callable[[str, str], dict],
    policy: ViewPolicy = ViewPolicy.ARTIFACT,
    event_sink: EventSink | None = None,
) -> list[Tool]:
    """Supervisor tool surface.

    `run_subagent(task, grant_id)` is supplied by the runner — the runner owns
    construction of the subagent loop because it knows which model + tool set
    to use. Keeping it as a callback keeps the supervisor harness loop-agnostic.
    """

    def _run_workload(kind: str, target: str) -> dict:
        result: WorkloadResult = run_workload(
            store=store,
            session_id=session_id,
            creator_agent_id=issuer_agent_id,
            kind=kind, target=target,
            policy=policy,
        )
        # Under ARTIFACT policy the supervisor sees ONLY the handle, never raw.
        # Under RAW/TRUNCATED/SUMMARY it sees the body — that's the eval baseline.
        d = asdict(result); d["policy"] = result.policy.value
        if result.artifact_id:
            _emit(
                event_sink,
                actor="artifactstore",
                kind="artifact_created",
                title=result.artifact_type,
                summary=f"Artifact {result.artifact_id} created",
                payload={
                    "tool_name": "run_workload",
                    "artifact_id": result.artifact_id,
                    "artifact_type": result.artifact_type,
                    "raw_token_count": result.raw_token_count,
                    "policy": result.policy.value,
                },
            )
        return d

    def _create_grant(subject_agent_id: str, artifact_types: list[str],
                      allowed_views: list[str], allowed_ops: list[str],
                      max_tokens: int = 2500, ttl_seconds: int = 1800,
                      path_prefixes: list[str] | None = None,
                      sensitivity_max: str | None = None) -> dict:
        predicate = {"session_id": session_id, "artifact_types": artifact_types}
        if path_prefixes is not None:
            predicate["path_prefixes"] = path_prefixes
        if sensitivity_max is not None:
            predicate["sensitivity_max"] = sensitivity_max
        grant_id = store.create_grant(
            subject_agent_id=subject_agent_id,
            issuer_agent_id=issuer_agent_id,
            artifact_predicate=predicate,
            allowed_ops=allowed_ops,
            allowed_views=allowed_views,
            max_tokens=max_tokens,
            ttl_seconds=ttl_seconds,
        )
        payload = {"grant_id": grant_id, "predicate": predicate,
                   "allowed_views": allowed_views, "allowed_ops": allowed_ops,
                   "max_tokens": max_tokens,
                   "subject_agent_id": subject_agent_id}
        _emit(
            event_sink,
            actor="artifactstore",
            kind="grant_created",
            title=grant_id,
            summary=f"Grant {grant_id} created for {subject_agent_id}",
            payload=payload,
        )
        return payload

    def _delegate(task: str, grant_id: str) -> dict:
        _emit(
            event_sink,
            actor="supervisor",
            kind="delegate_started",
            title=grant_id,
            summary=f"Supervisor delegated work under {grant_id}",
            payload={"grant_id": grant_id, "task_chars": len(task)},
        )
        result = run_subagent(task, grant_id)
        audit = result.get("audit") or []
        if isinstance(audit, list):
            allowed = sum(1 for row in audit if row.get("allowed") in (1, True))
            denied = sum(1 for row in audit if row.get("allowed") in (0, False))
            _emit(
                event_sink,
                actor="artifactstore",
                kind="audit_recorded",
                title=grant_id,
                summary=f"Audit recorded {len(audit)} reads for {grant_id}",
                payload={
                    "grant_id": grant_id,
                    "audit_count": len(audit),
                    "allowed_count": allowed,
                    "denied_count": denied,
                },
            )
        return result

    def _expand_artifact(artifact_id: str, view: str,
                         token_budget: int = 1500) -> str:
        # Supervisor uses its own implicit grant — eval treats supervisor as
        # trusted for citation verification. (PLAN §20.2: "supervisor verifies
        # every citation".)
        kw = {"artifact_id": artifact_id, "view": view,
              "token_budget": token_budget}
        result = store.expand_view(artifact_id=artifact_id,
                                   grant_id="__supervisor__",
                                   view=view,
                                   token_budget=token_budget)
        _emit_read(event_sink, actor="supervisor", tool_name="expand_artifact",
                   grant_id="__supervisor__", kw=kw, result=result,
                   allowed=True)
        return result

    def _verify_citation(citation: str) -> dict:
        """Resolve a 'art_xxx/span_yyy' citation. The supervisor should call
        this on each citation in a subagent's submit_report. Cleaner than
        passing the whole citation string into expand_artifact (which expects
        just artifact_id, not artifact_id/span_id)."""
        from artifactstore.cite import BadCitation, parse, verify_resolves
        try:
            art_id, span_id = parse(citation)
        except BadCitation as e:
            result = {"citation": citation, "resolved": False,
                      "error": f"malformed: {e}"}
            _emit(event_sink, actor="supervisor", kind="citation_verified",
                  title=citation, summary=f"Citation {citation} malformed",
                  payload=result)
            return result
        ok = verify_resolves(store.conn, citation)
        result = {
            "citation": citation,
            "resolved": ok,
            "artifact_id": art_id,
            "span_id": span_id,
            "error": None if ok else "span not found in store",
        }
        _emit(
            event_sink,
            actor="supervisor",
            kind="citation_verified",
            title=citation,
            summary=f"Citation {citation} {'resolved' if ok else 'failed'}",
            payload=result,
        )
        return result

    return [
        Tool(
            name="run_workload",
            description="Run a workload (pytest / grep / git / ...). Under the "
                        "default policy you receive only an artifact handle "
                        "{artifact_id, type, preview}; raw output is stored in "
                        "ArtifactStore. To inspect, mint a grant and delegate, "
                        "or call expand_artifact.",
            input_schema={
                "type": "object",
                "properties": {
                    "kind":   {"type": "string",
                               "enum": ["pytest", "grep", "git", "npm", "docker"]},
                    "target": {"type": "string",
                               "description": "Test path / pattern / commit-ish; "
                                              "fixture lookup key in replay mode."},
                },
                "required": ["kind", "target"],
            },
            fn=_run_workload,
        ),
        Tool(
            name="create_grant",
            description="Mint a scoped grant for a subagent. Be specific: "
                        "narrow artifact_types and avoid 'raw' in allowed_views "
                        "unless required.",
            input_schema={
                "type": "object",
                "properties": {
                    "subject_agent_id": {"type": "string"},
                    "artifact_types":   {"type": "array",
                                         "items": {"type": "string"}},
                    "allowed_views":    {"type": "array",
                                         "items": {"type": "string",
                                                   "enum": ["preview", "evidence",
                                                            "redacted", "raw",
                                                            "provenance"]}},
                    "allowed_ops":      {"type": "array",
                                         "items": {"type": "string",
                                                   "enum": ["search", "get_spans",
                                                            "expand_view",
                                                            "find_related"]}},
                    "max_tokens":       {"type": "integer", "default": 2500},
                    "ttl_seconds":      {"type": "integer", "default": 1800},
                    "path_prefixes":    {"type": "array", "items": {"type": "string"}},
                    "sensitivity_max":  {"type": "string"},
                },
                "required": ["subject_agent_id", "artifact_types",
                             "allowed_views", "allowed_ops"],
            },
            fn=_create_grant,
        ),
        Tool(
            name="delegate",
            description="Hand a focused task to the diagnostic subagent under "
                        "the given grant. The subagent does NOT see your "
                        "transcript. Returns its final report and audit summary.",
            input_schema={
                "type": "object",
                "properties": {
                    "task":     {"type": "string",
                                 "description": "Self-contained problem statement "
                                                "and any artifact handles to inspect."},
                    "grant_id": {"type": "string"},
                },
                "required": ["task", "grant_id"],
            },
            fn=_delegate,
        ),
        Tool(
            name="expand_artifact",
            description="Materialize a view of an artifact (NOT a citation — "
                        "artifact_id is just 'art_xxx', no slash, no span_id). "
                        "Views: preview | evidence | redacted | raw | provenance.",
            input_schema={
                "type": "object",
                "properties": {
                    "artifact_id":  {"type": "string",
                                     "description": "art_<8hex>, no slash"},
                    "view":         {"type": "string",
                                     "enum": ["preview", "evidence", "redacted",
                                              "raw", "provenance"]},
                    "token_budget": {"type": "integer", "default": 1500},
                },
                "required": ["artifact_id", "view"],
            },
            fn=_expand_artifact,
        ),
        Tool(
            name="verify_citation",
            description="Verify ONE citation 'art_xxx/span_yyy' resolves to a "
                        "real span in the store. Returns {resolved: bool, "
                        "artifact_id, span_id, error?}. Use this — not "
                        "expand_artifact — to verify subagent submit_report "
                        "citations one at a time.",
            input_schema={
                "type": "object",
                "properties": {
                    "citation": {"type": "string",
                                 "description": "format: art_<8hex>/span_<8hex>"},
                },
                "required": ["citation"],
            },
            fn=_verify_citation,
        ),
    ]
