import Foundation
import SwiftUI

enum ExecutionActorGroup: String, CaseIterable, Identifiable, Sendable {
    case user
    case supervisorAgent
    case subagent

    var id: String { rawValue }

    var title: String {
        switch self {
        case .user:
            return "User"
        case .supervisorAgent:
            return "Supervisor Agent"
        case .subagent:
            return "Subagent"
        }
    }

    var subtitle: String {
        switch self {
        case .user:
            return "fixed demo prompt"
        case .supervisorAgent:
            return "LLM decisions + harness execution"
        case .subagent:
            return "scoped evidence diagnosis"
        }
    }

    var color: Color {
        switch self {
        case .user:
            return .blue
        case .supervisorAgent:
            return .teal
        case .subagent:
            return .purple
        }
    }
}

enum AgentComponent: String, Identifiable, Sendable {
    case llm
    case harness
    case storeOperation

    var id: String { rawValue }

    var title: String {
        switch self {
        case .llm:
            return "LLM"
        case .harness:
            return "Harness"
        case .storeOperation:
            return "Store operation"
        }
    }
}

enum StoreOperation: String, CaseIterable, Identifiable, Sendable {
    case artifact
    case grant
    case audit
    case citation

    var id: String { rawValue }

    var title: String {
        switch self {
        case .artifact:
            return "artifact"
        case .grant:
            return "grant"
        case .audit:
            return "audit"
        case .citation:
            return "citation"
        }
    }
}

enum DemoStageID: Int, CaseIterable, Identifiable, Sendable {
    case userPrompt = 1
    case supervisorRunsWorkload
    case storesArtifact
    case createsGrant
    case delegatesSubagent
    case subagentRequestsEvidence
    case subagentReceivesEvidence
    case subagentSubmitsDiagnosis
    case supervisorVerifies
    case supervisorFinalizes

    var id: Int { rawValue }
}

enum FlowSpeaker: String, Identifiable, Sendable {
    case user
    case supervisorLLM
    case supervisorHarness
    case subagentLLM
    case subagentHarness

    var id: String { rawValue }

    var title: String {
        switch self {
        case .user:
            return "User"
        case .supervisorLLM:
            return "Supervisor LLM"
        case .supervisorHarness:
            return "Supervisor Harness"
        case .subagentLLM:
            return "Subagent LLM"
        case .subagentHarness:
            return "Subagent Harness"
        }
    }

    var actorGroup: ExecutionActorGroup {
        switch self {
        case .user:
            return .user
        case .supervisorLLM, .supervisorHarness:
            return .supervisorAgent
        case .subagentLLM, .subagentHarness:
            return .subagent
        }
    }

    var component: AgentComponent? {
        switch self {
        case .user:
            return nil
        case .supervisorLLM, .subagentLLM:
            return .llm
        case .supervisorHarness, .subagentHarness:
            return .harness
        }
    }

    var color: Color {
        actorGroup.color
    }

    var isHarness: Bool {
        switch self {
        case .supervisorHarness, .subagentHarness:
            return true
        case .user, .supervisorLLM, .subagentLLM:
            return false
        }
    }
}

enum FlowMessageStatus: String, Sendable {
    case active
    case completed
    case failed
}

struct FlowMessage: Identifiable, Equatable, Sendable {
    let id: String
    let stageID: DemoStageID
    let speaker: FlowSpeaker
    let title: String
    let summary: String
    let relatedEvents: [RunEvent]
    let storeOperations: [StoreOperation]
    let status: FlowMessageStatus

    var firstSeq: Int {
        relatedEvents.map(\.seq).min() ?? 0
    }

    var lastSeq: Int {
        relatedEvents.map(\.seq).max() ?? firstSeq
    }

    var seqRangeLabel: String {
        firstSeq == lastSeq ? "#\(firstSeq)" : "#\(firstSeq)-#\(lastSeq)"
    }

    var activeComponent: AgentComponent? {
        storeOperations.isEmpty ? speaker.component : .storeOperation
    }
}

struct ToolCallSummary: Identifiable, Equatable, Sendable {
    let name: String
    let count: Int

    var id: String { name }
}

struct ExecutionSnapshot: Equatable, Sendable {
    let messages: [FlowMessage]
    let activeActor: ExecutionActorGroup?
    let activeComponent: AgentComponent?
    let activeMessage: FlowMessage?
    let hasFailure: Bool

    var toolCallsByActor: [ExecutionActorGroup: [ToolCallSummary]] {
        var counts: [ExecutionActorGroup: [String: Int]] = [:]
        var order: [ExecutionActorGroup: [String]] = [:]
        for message in messages {
            for event in message.relatedEvents where event.kind == "tool_call" {
                guard let group = actorGroup(for: event) else { continue }
                if counts[group, default: [:]][event.title] == nil {
                    order[group, default: []].append(event.title)
                }
                counts[group, default: [:]][event.title, default: 0] += 1
            }
        }
        var out: [ExecutionActorGroup: [ToolCallSummary]] = [:]
        for group in ExecutionActorGroup.allCases {
            out[group] = (order[group] ?? []).map { name in
                ToolCallSummary(name: name, count: counts[group]?[name] ?? 0)
            }
        }
        return out
    }

    var activeToolName: String? {
        guard let activeMessage else { return nil }
        for event in activeMessage.relatedEvents {
            if event.kind == "tool_call" || event.kind == "tool_result" {
                return event.title
            }
        }
        return nil
    }

    static let empty = ExecutionFlowMapper.snapshot(from: [])

    private func actorGroup(for event: RunEvent) -> ExecutionActorGroup? {
        switch event.actor {
        case "supervisor":
            return .supervisorAgent
        case "subagent":
            return .subagent
        default:
            return nil
        }
    }
}

private struct FlowMessageDraft {
    let speaker: FlowSpeaker
    let title: String
    let summary: String
    let events: [RunEvent]
    let storeOperations: [StoreOperation]

    var stageID: DemoStageID {
        if let event = events.first {
            return ExecutionFlowMapper.stageID(for: event)
        }
        return .supervisorFinalizes
    }
}

enum ExecutionFlowMapper {
    static func snapshot(from events: [RunEvent]) -> ExecutionSnapshot {
        let sorted = events.sorted { $0.seq < $1.seq }
        let drafts = messageDrafts(from: sorted)
        let runFinished = sorted.contains { $0.kind == "run_finished" }
        let hasFailure = sorted.contains { $0.kind == "error" }

        let activeIndex: Int? = {
            guard !drafts.isEmpty else { return nil }
            return drafts.indices.last
        }()

        let messages = drafts.enumerated().map { index, draft in
            FlowMessage(
                id: "\(draft.events.map(\.seq).min() ?? index)-\(draft.speaker.rawValue)",
                stageID: draft.stageID,
                speaker: draft.speaker,
                title: draft.title,
                summary: draft.summary,
                relatedEvents: draft.events.sorted { $0.seq < $1.seq },
                storeOperations: orderedStoreOperations(draft.storeOperations),
                status: status(
                    for: draft,
                    index: index,
                    activeIndex: activeIndex,
                    runFinished: runFinished
                )
            )
        }

        let activeMessage = messages.last
        return ExecutionSnapshot(
            messages: messages,
            activeActor: activeMessage?.speaker.actorGroup,
            activeComponent: activeMessage?.activeComponent,
            activeMessage: activeMessage,
            hasFailure: hasFailure
        )
    }

    private static func messageDrafts(from events: [RunEvent]) -> [FlowMessageDraft] {
        var drafts: [FlowMessageDraft] = []
        var pendingStoreEvents: [RunEvent] = []

        for event in events {
            if storeOperation(for: event) != nil {
                pendingStoreEvents.append(event)
                continue
            }

            switch event.kind {
            case "run_started":
                drafts.append(FlowMessageDraft(
                    speaker: .user,
                    title: "Start demo request",
                    summary: "The user starts the \(scenarioLabel(from: event)) demo.",
                    events: [event],
                    storeOperations: []
                ))
            case "tool_call":
                drafts.append(makeToolCall(event))
            case "tool_result":
                let storeEvents = pendingStoreEvents
                pendingStoreEvents.removeAll()
                drafts.append(makeToolResult(event, storeEvents: storeEvents))
            case "agent_text":
                drafts.append(makeAgentText(event))
            case "delegate_started":
                drafts.append(makeDelegateStarted(event))
            case "run_finished":
                drafts.append(FlowMessageDraft(
                    speaker: .user,
                    title: "Receive final answer",
                    summary: "The verified diagnosis is ready for the user.",
                    events: [event],
                    storeOperations: []
                ))
            case "error":
                drafts.append(FlowMessageDraft(
                    speaker: inferSpeaker(for: event),
                    title: "Run failed",
                    summary: "The backend reported an error. Open this message to inspect the safe error summary.",
                    events: [event],
                    storeOperations: []
                ))
            default:
                drafts.append(FlowMessageDraft(
                    speaker: inferSpeaker(for: event),
                    title: event.title,
                    summary: event.summary,
                    events: [event],
                    storeOperations: []
                ))
            }
        }

        if !pendingStoreEvents.isEmpty {
            drafts.append(FlowMessageDraft(
                speaker: inferSpeaker(for: pendingStoreEvents.last),
                title: "Record Store operation",
                summary: "The harness recorded Store activity for audit or citation tracking.",
                events: pendingStoreEvents,
                storeOperations: orderedStoreOperations(pendingStoreEvents.compactMap { storeOperation(for: $0) })
            ))
        }

        return drafts
    }

    private static func status(for draft: FlowMessageDraft,
                               index: Int,
                               activeIndex: Int?,
                               runFinished: Bool) -> FlowMessageStatus {
        if draft.events.contains(where: { $0.kind == "error" }) {
            return .failed
        }
        if !runFinished && index == activeIndex {
            return .active
        }
        return .completed
    }

    private static func inferSpeaker(for event: RunEvent?) -> FlowSpeaker {
        switch event?.actor {
        case "subagent":
            return event?.kind == "tool_call" || event?.kind == "agent_text" ? .subagentLLM : .subagentHarness
        case "supervisor":
            return event?.kind == "tool_call" || event?.kind == "agent_text" ? .supervisorLLM : .supervisorHarness
        case "system":
            return .user
        case "artifactstore":
            return .supervisorHarness
        default:
            return .supervisorHarness
        }
    }

    static func stageID(for event: RunEvent) -> DemoStageID {
        switch event.kind {
        case "run_started":
            return .userPrompt
        case "agent_text":
            return event.actor == "subagent" ? .subagentSubmitsDiagnosis : .supervisorFinalizes
        case "tool_call", "tool_result":
            switch event.title {
            case "run_workload":
                return event.kind == "tool_call" ? .supervisorRunsWorkload : .storesArtifact
            case "create_grant":
                return .createsGrant
            case "delegate":
                return .delegatesSubagent
            case "artifact_search", "artifact_get_spans", "artifact_expand_view", "artifact_find_related":
                return event.kind == "tool_call" ? .subagentRequestsEvidence : .subagentReceivesEvidence
            case "submit_report":
                return .subagentSubmitsDiagnosis
            case "verify_citation", "expand_artifact":
                return .supervisorVerifies
            default:
                return event.actor == "subagent" ? .subagentRequestsEvidence : .supervisorRunsWorkload
            }
        case "artifact_created":
            return .storesArtifact
        case "grant_created":
            return .createsGrant
        case "delegate_started":
            return .delegatesSubagent
        case "audit_recorded":
            return event.actor == "subagent" ? .subagentReceivesEvidence : .delegatesSubagent
        case "citation_verified":
            return .supervisorVerifies
        case "run_finished":
            return .supervisorFinalizes
        default:
            return .supervisorFinalizes
        }
    }

    private static func makeToolCall(_ event: RunEvent) -> FlowMessageDraft {
        FlowMessageDraft(
            speaker: event.actor == "subagent" ? .subagentLLM : .supervisorLLM,
            title: toolCallTitle(event.title),
            summary: toolCallSummary(event),
            events: [event],
            storeOperations: []
        )
    }

    private static func makeToolResult(_ event: RunEvent, storeEvents: [RunEvent]) -> FlowMessageDraft {
        FlowMessageDraft(
            speaker: event.actor == "subagent" ? .subagentHarness : .supervisorHarness,
            title: toolResultTitle(event.title),
            summary: toolResultSummary(event),
            events: (storeEvents + [event]).sorted { $0.seq < $1.seq },
            storeOperations: orderedStoreOperations(storeEvents.compactMap { storeOperation(for: $0) })
        )
    }

    private static func makeAgentText(_ event: RunEvent) -> FlowMessageDraft {
        let fallback = "The LLM reads the latest harness result and decides what to do next."
        return FlowMessageDraft(
            speaker: event.actor == "subagent" ? .subagentLLM : .supervisorLLM,
            title: event.actor == "subagent" ? "Subagent LLM updates diagnosis" : "Supervisor LLM updates plan",
            summary: agentTextSummary(event) ?? fallback,
            events: [event],
            storeOperations: []
        )
    }

    private static func agentTextSummary(_ event: RunEvent) -> String? {
        guard case .string(let text)? = event.payload["text_preview"] else {
            return nil
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        let oneLine = trimmed
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
        let maxChars = 260
        if oneLine.count <= maxChars {
            return oneLine
        }
        return String(oneLine.prefix(maxChars)) + "..."
    }

    private static func makeDelegateStarted(_ event: RunEvent) -> FlowMessageDraft {
        FlowMessageDraft(
            speaker: .supervisorHarness,
            title: "Start subagent run",
            summary: "The supervisor harness launches the diagnostic subagent with the scoped grant.",
            events: [event],
            storeOperations: []
        )
    }

    private static func toolCallTitle(_ name: String) -> String {
        switch name {
        case "run_workload":
            return "Ask harness to reproduce failure"
        case "create_grant":
            return "Ask harness to scope evidence access"
        case "delegate":
            return "Ask harness to delegate diagnosis"
        case "artifact_search":
            return "Search permitted evidence"
        case "artifact_get_spans":
            return "Request concrete evidence spans"
        case "artifact_expand_view":
            return "Open safe artifact view"
        case "artifact_find_related":
            return "Follow related evidence links"
        case "submit_report":
            return "Submit cited diagnosis"
        case "verify_citation":
            return "Ask harness to verify citation"
        case "expand_artifact":
            return "Ask harness to inspect citation evidence"
        default:
            return "Call \(name)"
        }
    }

    private static func toolResultTitle(_ name: String) -> String {
        switch name {
        case "run_workload":
            return "Return workload artifact"
        case "create_grant":
            return "Return scoped grant"
        case "delegate":
            return "Return subagent report"
        case "artifact_search":
            return "Return search results"
        case "artifact_get_spans":
            return "Return evidence spans"
        case "artifact_expand_view":
            return "Return safe artifact view"
        case "artifact_find_related":
            return "Return related evidence"
        case "submit_report":
            return "Accept cited report"
        case "verify_citation":
            return "Return citation status"
        case "expand_artifact":
            return "Return citation evidence"
        default:
            return "Return \(name) result"
        }
    }

    private static func toolCallSummary(_ event: RunEvent) -> String {
        switch event.title {
        case "run_workload":
            return "The supervisor LLM needs a reproducible failure, so it asks the harness to replay \(scenarioLabel(from: event))."
        case "create_grant":
            return "The supervisor LLM asks for a narrow grant before giving the subagent access to evidence."
        case "delegate":
            return "The supervisor LLM asks the harness to launch a subagent for root-cause diagnosis."
        case "artifact_search":
            return "The subagent LLM looks for relevant evidence inside the permitted artifact set."
        case "artifact_get_spans":
            return "The subagent LLM asks for precise spans instead of the full raw output."
        case "artifact_expand_view":
            return "The subagent LLM requests a safe, grant-bounded view of the artifact."
        case "artifact_find_related":
            return "The subagent LLM follows provenance links to find related evidence."
        case "submit_report":
            return "The subagent LLM has enough evidence and submits a diagnosis with citations."
        case "verify_citation":
            return "The supervisor LLM checks that a cited artifact/span really exists."
        case "expand_artifact":
            return "The supervisor LLM asks its harness to inspect the cited evidence."
        default:
            return event.summary
        }
    }

    private static func toolResultSummary(_ event: RunEvent) -> String {
        switch event.title {
        case "run_workload":
            return "The harness replayed the workload and returned an ArtifactStore handle instead of raw output."
        case "create_grant":
            return "The harness created a scoped grant and returned the grant id to the supervisor LLM."
        case "delegate":
            return "The harness received the subagent's cited report and returns it to the supervisor LLM."
        case "artifact_search":
            return "The harness enforced the grant and returned matching artifact previews."
        case "artifact_get_spans":
            return "The harness enforced the grant and returned compact evidence spans."
        case "artifact_expand_view":
            return "The harness enforced the grant and returned the requested safe view."
        case "artifact_find_related":
            return "The harness returned related evidence links that are visible under the grant."
        case "submit_report":
            return "The harness accepted the subagent's report payload."
        case "verify_citation":
            return "The harness resolved the citation and returns whether it is valid."
        case "expand_artifact":
            return "The harness returned citation evidence under supervisor access."
        default:
            return event.summary
        }
    }

    private static func storeOperation(for event: RunEvent) -> StoreOperation? {
        switch event.kind {
        case "artifact_created":
            return .artifact
        case "grant_created":
            return .grant
        case "audit_recorded":
            return .audit
        case "citation_verified":
            return .citation
        default:
            return nil
        }
    }

    private static func scenarioLabel(from event: RunEvent) -> String {
        let kind = stringPayload(event, "kind") ?? "pytest"
        let target = stringPayload(event, "target") ?? "auth_expiry"
        return "\(kind)/\(target)"
    }

    private static func stringPayload(_ event: RunEvent, _ key: String) -> String? {
        guard let value = event.payload[key] else { return nil }
        switch value {
        case .string(let text):
            return text
        case .number(let number):
            if number.rounded() == number {
                return String(Int(number))
            }
            return String(number)
        case .bool(let bool):
            return bool ? "true" : "false"
        case .object, .array, .null:
            return nil
        }
    }

    private static func orderedStoreOperations(_ operations: [StoreOperation]) -> [StoreOperation] {
        var seen: Set<StoreOperation> = []
        var ordered: [StoreOperation] = []
        for operation in operations where !seen.contains(operation) {
            seen.insert(operation)
            ordered.append(operation)
        }
        return ordered
    }
}
