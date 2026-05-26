import SwiftUI

struct FlowMessageDetailSheet: View {
    let message: FlowMessage
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    summarySection
                    storeSection
                    eventsSection
                }
                .padding(18)
            }
            .navigationTitle("Flow Inspector")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                inspectorBadge(message.speaker.title, color: message.speaker.color)
                inspectorBadge(message.status.rawValue, color: statusColor)
                Spacer()
                Text(message.seqRangeLabel)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Text(message.title)
                .font(.title3.weight(.semibold))

            Text(message.summary)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                inspectorBadge(message.speaker.actorGroup.title, color: message.speaker.color)
                if let component = message.activeComponent {
                    inspectorBadge(component.title, color: component == .storeOperation ? .orange : message.speaker.color)
                }
            }
        }
        .sheetCard()
    }

    @ViewBuilder
    private var storeSection: some View {
        if !message.storeOperations.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Store Operations")
                    .font(.headline)
                HStack(spacing: 7) {
                    ForEach(message.storeOperations) { operation in
                        Label("Store: \(operation.title)", systemImage: "externaldrive.connected.to.line.below")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.orange)
                            .labelStyle(.titleAndIcon)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(Color.orange.opacity(0.12))
                            .clipShape(Capsule())
                    }
                }
            }
            .sheetCard()
        }
    }

    private var eventsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Related Raw Events")
                    .font(.headline)
                Spacer()
                Text("\(message.relatedEvents.count) events")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if message.relatedEvents.isEmpty {
                Text("No related backend event is attached to this message.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 8) {
                    ForEach(message.relatedEvents) { event in
                        InspectorEventRow(event: event)
                    }
                }
            }
        }
        .sheetCard()
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

    private func inspectorBadge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.11))
            .clipShape(Capsule())
    }
}

private struct InspectorEventRow: View {
    let event: RunEvent
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 8) {
                Text(event.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if event.payload.isEmpty {
                    Text("No payload")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(event.payload.keys.sorted(), id: \.self) { key in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(key)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Text(event.payload[key]?.displayValue ?? "")
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.primary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(8)
                    .background(.white.opacity(0.58))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding(.top, 8)
        } label: {
            HStack(spacing: 8) {
                Text("#\(event.seq)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 46, alignment: .leading)
                Text(event.actorLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(event.kindColor)
                    .frame(width: 104, alignment: .leading)
                Text(event.kind)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 116, alignment: .leading)
                Text(event.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .padding(10)
        .background(.white.opacity(0.74))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.secondary.opacity(0.2))
        )
    }
}

private extension View {
    func sheetCard() -> some View {
        self
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.quaternary)
            )
    }
}

#Preview {
    FlowMessageDetailSheet(
        message: ExecutionFlowMapper.snapshot(from: RunEvent.mockEvents).messages.first!
    )
}
