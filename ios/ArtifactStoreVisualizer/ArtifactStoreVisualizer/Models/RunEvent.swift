import Foundation
import SwiftUI

struct RunEvent: Codable, Identifiable, Equatable, Sendable {
    let seq: Int
    let timestamp: String
    let actor: String
    let kind: String
    let title: String
    let summary: String
    let payload: [String: JSONValue]

    var id: Int { seq }

    var actorLabel: String {
        actor.replacingOccurrences(of: "_", with: " ").capitalized
    }

    var kindColor: Color {
        switch kind {
        case "run_started", "run_finished":
            return .blue
        case "tool_call":
            return .indigo
        case "tool_result":
            return .teal
        case "artifact_created":
            return .orange
        case "grant_created":
            return .purple
        case "delegate_started":
            return .pink
        case "citation_verified":
            return .green
        case "audit_recorded":
            return .cyan
        case "error":
            return .red
        default:
            return .secondary
        }
    }
}

struct EventsResponse: Codable, Sendable {
    let events: [RunEvent]
}

extension RunEvent {
    static let mockEvents: [RunEvent] = [
        RunEvent(
            seq: 1,
            timestamp: "2026-05-25T16:38:09Z",
            actor: "system",
            kind: "run_started",
            title: "run_20260525_163809_6c9d77",
            summary: "Started pytest/auth_expiry",
            payload: [
                "kind": .string("pytest"),
                "target": .string("auth_expiry"),
                "model": .string("deepseek-v4-pro"),
            ]
        ),
        RunEvent(
            seq: 2,
            timestamp: "2026-05-25T16:38:13Z",
            actor: "supervisor",
            kind: "tool_call",
            title: "run_workload",
            summary: "supervisor called run_workload",
            payload: ["kind": .string("pytest"), "target": .string("auth_expiry")]
        ),
        RunEvent(
            seq: 3,
            timestamp: "2026-05-25T16:38:14Z",
            actor: "artifactstore",
            kind: "artifact_created",
            title: "pytest_failure",
            summary: "Artifact art_12345678 created",
            payload: ["artifact_id": .string("art_12345678"), "raw_token_count": .number(452)]
        ),
        RunEvent(
            seq: 4,
            timestamp: "2026-05-25T16:38:15Z",
            actor: "supervisor",
            kind: "tool_result",
            title: "run_workload",
            summary: "supervisor received result from run_workload",
            payload: ["tool_name": .string("run_workload"), "result_keys": .array([.string("artifact_id")])]
        ),
        RunEvent(
            seq: 5,
            timestamp: "2026-05-25T16:38:17Z",
            actor: "supervisor",
            kind: "agent_text",
            title: "assistant_text",
            summary: "supervisor emitted text (94 chars)",
            payload: [
                "text_chars": .number(94),
                "text_preview": .string("Good, I have a pytest failure artifact with a clear timezone signal. I will create a narrow grant next."),
                "text_truncated": .bool(false),
            ]
        ),
        RunEvent(
            seq: 6,
            timestamp: "2026-05-25T16:38:18Z",
            actor: "supervisor",
            kind: "tool_call",
            title: "delegate",
            summary: "supervisor called delegate",
            payload: ["tool_name": .string("delegate"), "task_chars": .number(480)]
        ),
        RunEvent(
            seq: 7,
            timestamp: "2026-05-25T16:38:19Z",
            actor: "supervisor",
            kind: "delegate_started",
            title: "grant_1234",
            summary: "Supervisor delegated work under grant_1234",
            payload: ["grant_id": .string("grant_1234")]
        ),
        RunEvent(
            seq: 8,
            timestamp: "2026-05-25T16:38:23Z",
            actor: "subagent",
            kind: "tool_call",
            title: "artifact_get_spans",
            summary: "subagent called artifact_get_spans",
            payload: ["artifact_id": .string("art_12345678")]
        ),
        RunEvent(
            seq: 9,
            timestamp: "2026-05-25T16:38:24Z",
            actor: "subagent",
            kind: "audit_recorded",
            title: "artifact_get_spans",
            summary: "subagent allowed artifact_get_spans",
            payload: ["allowed": .bool(true), "result_count": .number(4)]
        ),
        RunEvent(
            seq: 10,
            timestamp: "2026-05-25T16:38:25Z",
            actor: "subagent",
            kind: "tool_result",
            title: "artifact_get_spans",
            summary: "subagent received result from artifact_get_spans",
            payload: ["tool_name": .string("artifact_get_spans"), "result_count": .number(4)]
        ),
        RunEvent(
            seq: 11,
            timestamp: "2026-05-25T16:38:20Z",
            actor: "supervisor",
            kind: "citation_verified",
            title: "art_12345678/span_87654321",
            summary: "Citation art_12345678/span_87654321 resolved",
            payload: ["resolved": .bool(true)]
        ),
        RunEvent(
            seq: 12,
            timestamp: "2026-05-25T16:38:26Z",
            actor: "supervisor",
            kind: "tool_result",
            title: "verify_citation",
            summary: "supervisor received result from verify_citation",
            payload: ["tool_name": .string("verify_citation"), "resolved": .bool(true)]
        ),
        RunEvent(
            seq: 13,
            timestamp: "2026-05-25T16:38:30Z",
            actor: "system",
            kind: "run_finished",
            title: "run_20260525_163809_6c9d77",
            summary: "Run finished with status succeeded",
            payload: ["status": .string("succeeded")]
        )
    ]
}
