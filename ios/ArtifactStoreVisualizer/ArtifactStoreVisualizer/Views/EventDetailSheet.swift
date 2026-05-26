import SwiftUI

struct EventDetailSheet: View {
    let event: RunEvent
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Event") {
                    row("Seq", "#\(event.seq)")
                    row("Actor", event.actor)
                    row("Kind", event.kind)
                    row("Title", event.title)
                    row("Summary", event.summary)
                    row("Timestamp", event.timestamp)
                }

                Section("Payload") {
                    if event.payload.isEmpty {
                        Text("No payload")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(event.payload.keys.sorted(), id: \.self) { key in
                            row(key, event.payload[key]?.displayValue ?? "")
                        }
                    }
                }
            }
            .navigationTitle("Event Detail")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value.isEmpty ? "-" : value)
                .font(.system(.body, design: label == "Summary" ? .default : .monospaced))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    EventDetailSheet(event: RunEvent.mockEvents[2])
}
