import Foundation

struct RunSummary: Codable, Equatable, Sendable {
    let runID: String
    let status: String
    let kind: String
    let target: String
    let model: String
    let turns: Int
    let toolCalls: Int
    let inputTokens: Int
    let outputTokens: Int
    let finalText: String?
    let error: String?
    let startedAt: String?
    let finishedAt: String?

    enum CodingKeys: String, CodingKey {
        case runID = "run_id"
        case status
        case kind
        case target
        case model
        case turns
        case toolCalls = "tool_calls"
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case finalText = "final_text"
        case error
        case startedAt = "started_at"
        case finishedAt = "finished_at"
    }

    var isTerminal: Bool {
        status == "succeeded" || status == "failed"
    }

    static let mockSucceeded = RunSummary(
        runID: "run_20260525_163809_6c9d77",
        status: "succeeded",
        kind: "pytest",
        target: "auth_expiry",
        model: "deepseek-v4-pro",
        turns: 5,
        toolCalls: 9,
        inputTokens: 2716,
        outputTokens: 1718,
        finalText: "Root cause: validate_token compares a naive local datetime against a UTC-aware expiration timestamp. Fix by using datetime.now(timezone.utc).",
        error: nil,
        startedAt: "2026-05-25T16:38:09Z",
        finishedAt: "2026-05-25T16:40:17Z"
    )
}

struct CreateRunRequest: Codable, Sendable {
    let kind: String
    let target: String
    let model: String
}

struct CreateRunResponse: Codable, Sendable {
    let runID: String
    let status: String

    enum CodingKeys: String, CodingKey {
        case runID = "run_id"
        case status
    }
}

struct TraceResponse: Codable, Sendable {
    let run: RunSummary
    let events: [RunEvent]
}
