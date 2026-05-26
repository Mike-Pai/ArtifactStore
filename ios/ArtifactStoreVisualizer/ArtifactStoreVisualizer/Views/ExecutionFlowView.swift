import SwiftUI

private enum ArchitectureBoardSizing {
    static let minCardWidth: CGFloat = 360
    static let spacing: CGFloat = 12
    static let cardHeight: CGFloat = 260
}

struct ExecutionFlowView: View {
    let snapshot: ExecutionSnapshot
    let scenarioLabel: String
    let modelLabel: String
    let availableHeight: CGFloat
    let playbackStatus: String
    let onSelectMessage: (FlowMessage) -> Void

    private var conversationHeight: CGFloat {
        max(560, availableHeight - 410)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            ArchitectureBoard(
                snapshot: snapshot,
                scenarioLabel: scenarioLabel,
                modelLabel: modelLabel
            )
            CenterlineFlowConversationView(
                messages: snapshot.messages,
                panelHeight: conversationHeight,
                playbackStatus: playbackStatus,
                onSelectMessage: onSelectMessage
            )
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Execution Flow")
                    .font(.title3.weight(.semibold))
                Text("User, agent LLMs, harnesses, and Store operations")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(playbackStatus)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }
}

private struct ArchitectureBoard: View {
    let snapshot: ExecutionSnapshot
    let scenarioLabel: String
    let modelLabel: String
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        if horizontalSizeClass == .compact {
            VStack(alignment: .leading, spacing: ArchitectureBoardSizing.spacing) {
                UserContainer(
                    scenarioLabel: scenarioLabel,
                    modelLabel: modelLabel,
                    isActive: snapshot.activeActor == .user
                )
                .frame(maxWidth: .infinity, minHeight: 214)

                AgentContainer(
                    group: .supervisorAgent,
                    activeComponent: activeComponent(for: .supervisorAgent),
                    toolCalls: snapshot.toolCallsByActor[.supervisorAgent] ?? [],
                    activeToolName: activeToolName(for: .supervisorAgent)
                )
                .frame(maxWidth: .infinity, minHeight: ArchitectureBoardSizing.cardHeight)

                AgentContainer(
                    group: .subagent,
                    activeComponent: activeComponent(for: .subagent),
                    toolCalls: snapshot.toolCallsByActor[.subagent] ?? [],
                    activeToolName: activeToolName(for: .subagent)
                )
                .frame(maxWidth: .infinity, minHeight: ArchitectureBoardSizing.cardHeight)
            }
        } else {
            GeometryReader { proxy in
                let minimumBoardWidth = ArchitectureBoardSizing.minCardWidth * 3 + ArchitectureBoardSizing.spacing * 2
                let shouldFill = proxy.size.width >= minimumBoardWidth
                let cardWidth = shouldFill
                    ? (proxy.size.width - ArchitectureBoardSizing.spacing * 2) / 3
                    : ArchitectureBoardSizing.minCardWidth
                let boardWidth = shouldFill ? proxy.size.width : minimumBoardWidth

                ScrollView(.horizontal, showsIndicators: !shouldFill) {
                    HStack(alignment: .top, spacing: ArchitectureBoardSizing.spacing) {
                        UserContainer(
                            scenarioLabel: scenarioLabel,
                            modelLabel: modelLabel,
                            isActive: snapshot.activeActor == .user
                        )
                        .frame(width: cardWidth, height: ArchitectureBoardSizing.cardHeight)

                        AgentContainer(
                            group: .supervisorAgent,
                            activeComponent: activeComponent(for: .supervisorAgent),
                            toolCalls: snapshot.toolCallsByActor[.supervisorAgent] ?? [],
                            activeToolName: activeToolName(for: .supervisorAgent)
                        )
                        .frame(width: cardWidth, height: ArchitectureBoardSizing.cardHeight)

                        AgentContainer(
                            group: .subagent,
                            activeComponent: activeComponent(for: .subagent),
                            toolCalls: snapshot.toolCallsByActor[.subagent] ?? [],
                            activeToolName: activeToolName(for: .subagent)
                        )
                        .frame(width: cardWidth, height: ArchitectureBoardSizing.cardHeight)
                    }
                    .frame(width: boardWidth, alignment: .leading)
                }
            }
            .frame(height: ArchitectureBoardSizing.cardHeight)
        }
    }

    private func activeComponent(for group: ExecutionActorGroup) -> AgentComponent? {
        snapshot.activeActor == group ? snapshot.activeComponent : nil
    }

    private func activeToolName(for group: ExecutionActorGroup) -> String? {
        snapshot.activeActor == group ? snapshot.activeToolName : nil
    }
}

private struct UserContainer: View {
    let scenarioLabel: String
    let modelLabel: String
    let isActive: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ActorHeader(group: .user, isActive: isActive)

            VStack(alignment: .leading, spacing: 6) {
                Text("Fixed prompt")
                    .font(.caption.weight(.semibold))
                Text(scenarioLabel)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.75))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            HStack(spacing: 10) {
                UserInfoCard(title: "Scenario", value: scenarioLabel)
                UserInfoCard(title: "Model", value: modelLabel)
            }

            Spacer(minLength: 0)
        }
        .containerBackground(group: .user, isActive: isActive)
    }
}

private struct UserInfoCard: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption.weight(.semibold))
            Text(value)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 68, alignment: .topLeading)
        .background(.white.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.28), lineWidth: 1)
        )
    }
}

private struct AgentContainer: View {
    let group: ExecutionActorGroup
    let activeComponent: AgentComponent?
    let toolCalls: [ToolCallSummary]
    let activeToolName: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ActorHeader(group: group, isActive: activeComponent != nil)

            HStack(spacing: 10) {
                ComponentCard(
                    title: "LLM",
                    subtitle: group == .supervisorAgent ? "chooses tools" : "requests evidence",
                    color: group.color,
                    isActive: activeComponent == .llm
                )
                ComponentCard(
                    title: "Harness",
                    subtitle: group == .supervisorAgent ? "runs tools + delegates" : "runs scoped tools",
                    color: group.color,
                    isActive: activeComponent == .harness || activeComponent == .storeOperation
                )
            }

            ToolCallStrip(
                toolCalls: toolCalls,
                activeToolName: activeToolName,
                color: group.color
            )
        }
        .containerBackground(group: group, isActive: activeComponent != nil)
    }
}

private struct ActorHeader: View {
    let group: ExecutionActorGroup
    let isActive: Bool

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(group.color)
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(group.title)
                    .font(.subheadline.weight(.semibold))
                Text(group.subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isActive {
                Image(systemName: "bolt.fill")
                    .font(.caption)
                    .foregroundStyle(group.color)
            }
        }
    }
}

private struct ComponentCard: View {
    let title: String
    let subtitle: String
    let color: Color
    let isActive: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption.weight(.semibold))
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 68, alignment: .topLeading)
        .background(isActive ? color.opacity(0.14) : .white.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isActive ? color : Color.secondary.opacity(0.28), lineWidth: isActive ? 1.4 : 1)
        )
    }
}

private struct ToolCallStrip: View {
    let toolCalls: [ToolCallSummary]
    let activeToolName: String?
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Image(systemName: "wrench")
                    .font(.caption2)
                Text("Tool calls chosen by LLM")
                    .font(.caption2.weight(.semibold))
                Spacer()
            }
            .foregroundStyle(color)

            if toolCalls.isEmpty {
                Text("No tool calls yet")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.72))
                    .clipShape(Capsule())
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 150), spacing: 6, alignment: .leading)],
                    alignment: .leading,
                    spacing: 6
                ) {
                    ForEach(toolCalls) { tool in
                        ToolCallChip(
                            tool: tool,
                            color: color,
                            isActive: activeToolName == tool.name
                        )
                    }
                }
            }
        }
        .padding(9)
        .background(activeToolName == nil ? color.opacity(0.05) : color.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(activeToolName == nil ? color.opacity(0.24) : color)
        )
    }
}

private struct ToolCallChip: View {
    let tool: ToolCallSummary
    let color: Color
    let isActive: Bool

    var body: some View {
        Text("\(tool.name) \(tool.count)")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isActive ? color.opacity(0.2) : Color.white.opacity(0.72))
            .clipShape(Capsule())
    }
}

private struct CenterlineFlowConversationView: View {
    let messages: [FlowMessage]
    let panelHeight: CGFloat
    let playbackStatus: String
    let onSelectMessage: (FlowMessage) -> Void
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var latestMessageID: String? {
        messages.last?.id
    }

    private var effectivePanelHeight: CGFloat {
        horizontalSizeClass == .compact ? min(panelHeight, 620) : panelHeight
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Flow Conversation")
                    .font(.headline)
                Spacer()
                Text(playbackStatus)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Text("tap a bubble for inspector")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ScrollViewReader { proxy in
                ZStack {
                    CenterlineLaneBackground()

                    ScrollView {
                        if messages.isEmpty {
                            EmptyConversation()
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 86)
                        } else {
                            LazyVStack(alignment: .leading, spacing: 0) {
                                ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                                    CenterlineFlowRow(
                                        message: message,
                                        isLast: index == messages.count - 1,
                                        onSelectMessage: onSelectMessage
                                    )
                                    .id(message.id)
                                }
                            }
                            .padding(10)
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
                .frame(height: effectivePanelHeight)
                .background(.white.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(.secondary.opacity(0.2))
                )
                .onChange(of: latestMessageID) { _, id in
                    guard let id else { return }
                    withAnimation(.easeOut(duration: 0.25)) {
                        proxy.scrollTo(id, anchor: .bottom)
                    }
                }
            }
        }
    }
}

private struct CenterlineLaneBackground: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                if horizontalSizeClass == .compact {
                    Color.teal.opacity(0.026)
                } else {
                    HStack(spacing: 0) {
                        Color.teal.opacity(0.035)
                        Rectangle()
                            .fill(Color.white.opacity(0.38))
                            .frame(width: 70)
                        Color.purple.opacity(0.035)
                    }
                }

                Rectangle()
                    .fill(Color.teal.opacity(0.16))
                    .frame(width: 2)
                    .frame(maxHeight: .infinity)

                if horizontalSizeClass == .compact {
                    laneLabel("Flow lane", color: .teal)
                        .padding(.top, 12)
                } else {
                    HStack {
                        laneLabel("Supervisor lane", color: .teal)
                        Spacer()
                        laneLabel("Subagent lane", color: .purple)
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 12)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .allowsHitTesting(false)
    }

    private func laneLabel(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color.opacity(0.55))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.white.opacity(0.46))
            .clipShape(Capsule())
    }
}

private struct EmptyConversation: View {
    var body: some View {
        VStack(spacing: 12) {
            CenterlineNode(color: .secondary, status: .completed)
            VStack(spacing: 3) {
                Rectangle()
                    .fill(Color.secondary.opacity(0.25))
                    .frame(width: 2, height: 24)
                    .clipShape(Capsule())
                Image(systemName: "arrow.down")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(.secondary)
            VStack(spacing: 6) {
                Text("No Conversation Yet")
                    .font(.headline)
                Text("Start a demo run or replay the latest trace.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct CenterlineFlowRow: View {
    let message: FlowMessage
    let isLast: Bool
    let onSelectMessage: (FlowMessage) -> Void
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        VStack(spacing: 7) {
            if horizontalSizeClass == .compact {
                VStack(spacing: 8) {
                    CenterlineNode(color: nodeColor, status: message.status)
                    bubble
                        .frame(maxWidth: .infinity)
                }
                .frame(maxWidth: .infinity)
            } else {
                switch placement {
                case .center:
                    VStack(spacing: 8) {
                        CenterlineNode(color: nodeColor, status: message.status)
                        bubble
                            .frame(maxWidth: 520)
                    }
                    .frame(maxWidth: .infinity)
                case .left:
                    HStack(alignment: .top, spacing: 12) {
                        HStack {
                            Spacer(minLength: 0)
                            bubble
                                .frame(maxWidth: 620, alignment: .trailing)
                        }
                        .frame(maxWidth: .infinity)
                        CenterlineNode(color: nodeColor, status: message.status)
                            .padding(.top, 14)
                        Color.clear
                            .frame(maxWidth: .infinity)
                    }
                    .frame(maxWidth: .infinity)
                case .right:
                    HStack(alignment: .top, spacing: 12) {
                        Color.clear
                            .frame(maxWidth: .infinity)
                        CenterlineNode(color: nodeColor, status: message.status)
                            .padding(.top, 14)
                        HStack {
                            bubble
                                .frame(maxWidth: 620, alignment: .leading)
                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .frame(maxWidth: .infinity)
                }
            }

            if !isLast {
                CenterlineConnector(color: nodeColor.opacity(0.55))
            }
        }
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity)
    }

    private var bubble: some View {
        Button {
            onSelectMessage(message)
        } label: {
            FlowBubble(message: message)
        }
        .buttonStyle(.plain)
    }

    private var placement: CenterlinePlacement {
        switch message.speaker.actorGroup {
        case .user:
            return .center
        case .supervisorAgent:
            return .left
        case .subagent:
            return .right
        }
    }

    private var nodeColor: Color {
        switch message.status {
        case .failed:
            return .red
        case .active, .completed:
            return message.speaker.color
        }
    }
}

private enum CenterlinePlacement {
    case center
    case left
    case right
}

private struct CenterlineNode: View {
    let color: Color
    let status: FlowMessageStatus

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.14))
                .frame(width: 26, height: 26)
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
            if status == .active {
                Circle()
                    .stroke(color.opacity(0.55), lineWidth: 2)
                    .frame(width: 22, height: 22)
            }
        }
        .frame(width: 28, height: 28)
    }
}

private struct CenterlineConnector: View {
    let color: Color

    var body: some View {
        VStack(spacing: 3) {
            Rectangle()
                .fill(color.opacity(0.42))
                .frame(width: 2, height: 18)
                .clipShape(Capsule())
            Image(systemName: "arrow.down")
                .font(.caption2.weight(.bold))
                .foregroundStyle(color)
            Rectangle()
                .fill(color.opacity(0.24))
                .frame(width: 2, height: 12)
                .clipShape(Capsule())
        }
        .frame(maxWidth: .infinity)
    }
}

private struct FlowBubble: View {
    let message: FlowMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                speakerBadge
                statusBadge
                Spacer()
                Text(message.seqRangeLabel)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Text(message.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            Text(message.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if !message.storeOperations.isEmpty {
                HStack(spacing: 6) {
                    ForEach(message.storeOperations) { operation in
                        StoreChip(operation: operation)
                    }
                }
            }
        }
        .padding(12)
        .background(bubbleBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(borderColor, lineWidth: message.status == .active ? 1.6 : 1)
        )
    }

    private var speakerBadge: some View {
        Label(message.speaker.title, systemImage: speakerIcon)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(message.speaker.color)
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(message.speaker.color.opacity(0.11))
            .clipShape(Capsule())
    }

    private var statusBadge: some View {
        Text(message.status.rawValue)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(statusColor)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(statusColor.opacity(0.1))
            .clipShape(Capsule())
    }

    private var speakerIcon: String {
        switch message.speaker {
        case .user:
            return "person"
        case .supervisorLLM, .subagentLLM:
            return "brain.head.profile"
        case .supervisorHarness, .subagentHarness:
            return "gearshape"
        }
    }

    private var statusColor: Color {
        switch message.status {
        case .active:
            return message.speaker.color
        case .completed:
            return .green
        case .failed:
            return .red
        }
    }

    private var bubbleBackground: Color {
        if message.status == .failed {
            return .red.opacity(0.1)
        }
        if message.speaker.isHarness {
            return message.speaker.color.opacity(message.status == .active ? 0.16 : 0.09)
        }
        if message.speaker == .user {
            return Color.blue.opacity(message.status == .active ? 0.14 : 0.08)
        }
        return .white.opacity(0.78)
    }

    private var borderColor: Color {
        switch message.status {
        case .active:
            return message.speaker.color
        case .failed:
            return .red
        case .completed:
            return message.speaker.isHarness ? message.speaker.color.opacity(0.35) : Color.secondary.opacity(0.25)
        }
    }
}

private struct StoreChip: View {
    let operation: StoreOperation

    var body: some View {
        Label("Store: \(operation.title)", systemImage: "externaldrive.connected.to.line.below")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Color.orange)
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(Color.orange.opacity(0.12))
            .clipShape(Capsule())
    }
}

private extension View {
    func containerBackground(group: ExecutionActorGroup, isActive: Bool) -> some View {
        self
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(isActive ? group.color.opacity(0.1) : Color.white.opacity(0.62))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isActive ? group.color : Color.secondary.opacity(0.28), lineWidth: isActive ? 1.5 : 1)
            )
    }
}

#Preview {
    ExecutionFlowView(
        snapshot: ExecutionFlowMapper.snapshot(from: RunEvent.mockEvents),
        scenarioLabel: DemoScenario.authExpiry.requestLabel,
        modelLabel: DemoModel.deepseekV4Pro.id,
        availableHeight: 900,
        playbackStatus: "playing 3/12",
        onSelectMessage: { _ in }
    )
    .padding()
}
