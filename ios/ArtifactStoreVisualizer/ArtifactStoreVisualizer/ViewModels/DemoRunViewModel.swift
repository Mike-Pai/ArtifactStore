import Foundation
import Combine

@MainActor
final class DemoRunViewModel: ObservableObject {
    enum ConnectionState: Equatable {
        case idle
        case checking
        case connected
        case disconnected(String)

        var label: String {
            switch self {
            case .idle:
                return "Not checked"
            case .checking:
                return "Checking..."
            case .connected:
                return "Connected"
            case .disconnected:
                return "Disconnected"
            }
        }
    }

    @Published var backendURL: String
    @Published var selectedScenario: DemoScenario = .authExpiry
    @Published var selectedModel: DemoModel = .deepseekV4Pro
    @Published var isSettingsPresented = false
    @Published private(set) var connectionState: ConnectionState = .idle
    @Published private(set) var runSummary: RunSummary?
    @Published private(set) var events: [RunEvent] = []
    @Published private(set) var presentedEvents: [RunEvent] = []
    @Published var selectedEvent: RunEvent?
    @Published var selectedMessage: FlowMessage?
    @Published var isRawEventsExpanded = false
    @Published private(set) var isStartingRun = false
    @Published private(set) var isPolling = false
    @Published private(set) var isPresentingFlow = false
    @Published private(set) var errorMessage: String?

    private var pollingTask: Task<Void, Never>?
    private var presentationTask: Task<Void, Never>?
    private var lastSeq = 0
    private var pendingMessages: [FlowMessage] = []
    private var presentedMessageIDs = Set<String>()
    private var presentationGeneration = 0

    var executionSnapshot: ExecutionSnapshot {
        ExecutionFlowMapper.snapshot(from: presentedEvents)
    }

    var flowPresentationStatusLabel: String {
        let shown = displayableMessages(from: presentedEvents).count
        let total = displayableMessages(from: events).count
        if total == 0 {
            return isPolling ? "waiting for events" : "idle"
        }
        if shown < total || isPresentingFlow {
            return "playing \(shown)/\(total)"
        }
        if runSummary?.isTerminal == true {
            return "complete"
        }
        if isPolling {
            return "waiting for harness"
        }
        return "ready"
    }

    var activeScenarioLabel: String {
        if let runSummary {
            return "\(runSummary.kind)/\(runSummary.target)"
        }
        return selectedScenario.requestLabel
    }

    var selectedModelLabel: String {
        if let runSummary {
            return runSummary.model
        }
        return selectedModel.id
    }

    init(backendURL: String = "http://100.110.13.83:8765") {
        self.backendURL = backendURL
    }

    deinit {
        pollingTask?.cancel()
        presentationTask?.cancel()
    }

    func connect() async {
        connectionState = .checking
        errorMessage = nil
        do {
            try await makeClient().health()
            connectionState = .connected
        } catch {
            let message = describe(error)
            connectionState = .disconnected(message)
            errorMessage = message
        }
    }

    func startDemo() async {
        stopPolling()
        isStartingRun = true
        errorMessage = nil
        events = []
        resetPresentation()
        selectedEvent = nil
        selectedMessage = nil
        isRawEventsExpanded = false
        runSummary = nil
        lastSeq = 0
        do {
            let scenario = selectedScenario
            let model = selectedModel
            let client = try makeClient()
            let created = try await client.createRun(
                kind: scenario.kind,
                target: scenario.target,
                model: model.id
            )
            runSummary = RunSummary(
                runID: created.runID,
                status: created.status,
                kind: scenario.kind,
                target: scenario.target,
                model: model.id,
                turns: 0,
                toolCalls: 0,
                inputTokens: 0,
                outputTokens: 0,
                finalText: nil,
                error: nil,
                startedAt: nil,
                finishedAt: nil
            )
            connectionState = .connected
            startPolling(runID: created.runID)
        } catch {
            errorMessage = describe(error)
        }
        isStartingRun = false
    }

    func loadLatestTrace() async {
        stopPolling()
        errorMessage = nil
        do {
            let trace = try await makeClient().fetchLatestTrace()
            runSummary = trace.run
            events = trace.events.sorted { $0.seq < $1.seq }
            lastSeq = events.map(\.seq).max() ?? 0
            resetPresentation()
            if let scenario = DemoScenario.matching(kind: trace.run.kind, target: trace.run.target) {
                selectedScenario = scenario
            }
            if let model = DemoModel.matching(id: trace.run.model) {
                selectedModel = model
            }
            selectedEvent = nil
            selectedMessage = nil
            connectionState = .connected
            rebuildPresentationQueue()
        } catch {
            errorMessage = describe(error)
        }
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
        isPolling = false
        stopPresentation()
    }

    private func startPolling(runID: String) {
        stopPolling()
        isPolling = true
        pollingTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.pollOnce(runID: runID)
                if self.runSummary?.isTerminal == true {
                    try? await Task.sleep(nanoseconds: 250_000_000)
                    await self.pollOnce(runID: runID)
                    self.isPolling = false
                    return
                }
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
            self.isPolling = false
        }
    }

    private func pollOnce(runID: String) async {
        do {
            let client = try makeClient()
            let newEvents = try await client.fetchEvents(runID: runID, after: lastSeq)
            mergeEvents(newEvents)
            runSummary = try await client.fetchRun(runID: runID)
        } catch {
            errorMessage = describe(error)
        }
    }

    private func mergeEvents(_ newEvents: [RunEvent]) {
        guard !newEvents.isEmpty else { return }
        var bySeq = Dictionary(uniqueKeysWithValues: events.map { ($0.seq, $0) })
        for event in newEvents {
            bySeq[event.seq] = event
        }
        events = bySeq.values.sorted { $0.seq < $1.seq }
        lastSeq = max(lastSeq, events.map(\.seq).max() ?? 0)
        rebuildPresentationQueue()
    }

    private func rebuildPresentationQueue() {
        let messages = displayableMessages(from: events)
        refreshPresentedEvents(from: messages)
        pendingMessages = messages.filter { !presentedMessageIDs.contains($0.id) }
        startPresentationIfNeeded()
    }

    private func startPresentationIfNeeded() {
        guard presentationTask == nil, !pendingMessages.isEmpty else { return }
        let generation = presentationGeneration
        isPresentingFlow = true
        presentationTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                guard self.presentationGeneration == generation else { return }
                guard let message = self.pendingMessages.first else { break }
                self.pendingMessages.removeFirst()
                self.presentedMessageIDs.insert(message.id)
                self.refreshPresentedEvents(from: self.displayableMessages(from: self.events))
                try? await Task.sleep(nanoseconds: Self.playbackDelay(for: message))
            }
            guard self.presentationGeneration == generation else { return }
            self.isPresentingFlow = false
            self.presentationTask = nil
            if !Task.isCancelled, !self.pendingMessages.isEmpty {
                self.startPresentationIfNeeded()
            }
        }
    }

    private func refreshPresentedEvents(from messages: [FlowMessage]) {
        var bySeq: [Int: RunEvent] = [:]
        for message in messages where presentedMessageIDs.contains(message.id) {
            for event in message.relatedEvents {
                bySeq[event.seq] = event
            }
        }
        presentedEvents = bySeq.values.sorted { $0.seq < $1.seq }
    }

    private func resetPresentation() {
        stopPresentation()
        presentedEvents = []
        pendingMessages = []
        presentedMessageIDs = []
    }

    private func stopPresentation() {
        presentationGeneration += 1
        presentationTask?.cancel()
        presentationTask = nil
        isPresentingFlow = false
    }

    private func displayableMessages(from sourceEvents: [RunEvent]) -> [FlowMessage] {
        ExecutionFlowMapper.snapshot(from: sourceEvents).messages.filter { message in
            !message.relatedEvents.allSatisfy { Self.isStoreOnlyEvent($0) }
        }
    }

    private static func isStoreOnlyEvent(_ event: RunEvent) -> Bool {
        switch event.kind {
        case "artifact_created", "grant_created", "audit_recorded", "citation_verified":
            return true
        default:
            return false
        }
    }

    private static func playbackDelay(for message: FlowMessage) -> UInt64 {
        if message.title == "Receive final answer" || message.stageID == .supervisorFinalizes {
            return 1_400_000_000
        }
        if !message.storeOperations.isEmpty
            || message.relatedEvents.contains(where: { $0.kind == "citation_verified" }) {
            return 1_250_000_000
        }
        if message.speaker.isHarness
            || message.relatedEvents.contains(where: { $0.kind == "tool_result" }) {
            return 1_150_000_000
        }
        return 750_000_000
    }

    private func makeClient() throws -> DemoBackendClient {
        try DemoBackendClient(baseURLString: backendURL)
    }

    private func describe(_ error: Error) -> String {
        if let localized = error as? LocalizedError,
           let description = localized.errorDescription {
            return description
        }
        return error.localizedDescription
    }
}

#if DEBUG
extension DemoRunViewModel {
    static func previewLoaded() -> DemoRunViewModel {
        let model = DemoRunViewModel()
        model.connectionState = .connected
        model.runSummary = .mockSucceeded
        model.events = RunEvent.mockEvents
        model.presentedEvents = RunEvent.mockEvents
        model.lastSeq = RunEvent.mockEvents.map(\.seq).max() ?? 0
        return model
    }
}
#endif
