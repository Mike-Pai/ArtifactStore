import SwiftUI

struct EventTimelineView: View {
    let events: [RunEvent]
    @Binding var selectedEvent: RunEvent?

    var body: some View {
        Group {
            if events.isEmpty {
                ContentUnavailableView(
                    "No Events",
                    systemImage: "timeline.selection",
                    description: Text("Start a demo run or replay the latest trace.")
                )
            } else {
                ScrollViewReader { reader in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            ForEach(events) { event in
                                EventRow(event: event)
                                    .id(event.seq)
                                    .onTapGesture {
                                        selectedEvent = event
                                    }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .onChange(of: events.count) { _, _ in
                        if let last = events.last {
                            withAnimation(.easeOut(duration: 0.2)) {
                                reader.scrollTo(last.seq, anchor: .bottom)
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct EventRow: View {
    let event: RunEvent

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 4) {
                Circle()
                    .fill(event.kindColor)
                    .frame(width: 12, height: 12)
                Rectangle()
                    .fill(.quaternary)
                    .frame(width: 2)
            }
            .frame(width: 16)

            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("#\(event.seq)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)

                    Text(event.actorLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(event.kindColor)

                    Text(event.kind)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(event.kindColor.opacity(0.12))
                        .foregroundStyle(event.kindColor)
                        .clipShape(Capsule())

                    Spacer()
                }

                Text(event.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)

                Text(event.summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.quaternary)
            )
        }
    }
}

#Preview {
    EventTimelineView(events: RunEvent.mockEvents, selectedEvent: .constant(nil))
        .padding()
}
