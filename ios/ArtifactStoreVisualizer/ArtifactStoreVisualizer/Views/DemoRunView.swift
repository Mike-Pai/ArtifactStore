import SwiftUI

struct DemoRunView: View {
    @ObservedObject var viewModel: DemoRunViewModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        if horizontalSizeClass == .compact {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        ConnectionView(viewModel: viewModel)
                        RunSummaryView(summary: viewModel.runSummary)
                        FinalDiagnosisView(summary: viewModel.runSummary)
                        timelinePanel(availableHeight: 760)
                    }
                    .padding(16)
                }
                .navigationTitle("ArtifactStore Visualizer")
            }
            .sheet(item: $viewModel.selectedEvent) { event in
                EventDetailSheet(event: event)
            }
            .sheet(item: $viewModel.selectedMessage) { message in
                FlowMessageDetailSheet(message: message)
            }
        } else {
            NavigationSplitView {
                sidebar
                    .navigationTitle("ArtifactStore Visualizer")
                    .navigationSplitViewColumnWidth(min: 300, ideal: 360, max: 430)
            } detail: {
                GeometryReader { proxy in
                    ScrollView {
                        timelinePanel(availableHeight: proxy.size.height)
                            .padding(20)
                    }
                }
                .navigationTitle("Execution Flow")
                .navigationBarTitleDisplayMode(.inline)
            }
            .sheet(item: $viewModel.selectedEvent) { event in
                EventDetailSheet(event: event)
            }
            .sheet(item: $viewModel.selectedMessage) { message in
                FlowMessageDetailSheet(message: message)
            }
        }
    }

    private var sidebar: some View {
        List {
            Section {
                ConnectionView(viewModel: viewModel, showsTitle: false)
                    .listRowInsets(EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14))
                    .listRowBackground(Color.clear)
            }

            Section {
                RunSummaryView(summary: viewModel.runSummary)
                    .listRowInsets(EdgeInsets(top: 8, leading: 14, bottom: 8, trailing: 14))
                    .listRowBackground(Color.clear)
            }

            Section {
                FinalDiagnosisView(summary: viewModel.runSummary)
                    .listRowInsets(EdgeInsets(top: 8, leading: 14, bottom: 14, trailing: 14))
                    .listRowBackground(Color.clear)
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(Color(red: 0.96, green: 0.97, blue: 0.98))
    }

    private func timelinePanel(availableHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ExecutionFlowView(
                snapshot: viewModel.executionSnapshot,
                scenarioLabel: viewModel.activeScenarioLabel,
                modelLabel: viewModel.selectedModelLabel,
                availableHeight: availableHeight,
                playbackStatus: viewModel.flowPresentationStatusLabel
            ) { message in
                viewModel.selectedMessage = message
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Raw Events")
                        .font(.headline)
                    Spacer()
                    Text("\(viewModel.events.count) events")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button {
                        viewModel.isRawEventsExpanded.toggle()
                    } label: {
                        Label(
                            viewModel.isRawEventsExpanded ? "Hide" : "Show",
                            systemImage: viewModel.isRawEventsExpanded ? "chevron.up" : "chevron.down"
                        )
                        .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(.bordered)
                    .font(.caption)
                }

                if viewModel.isRawEventsExpanded {
                    EventTimelineView(
                        events: viewModel.events,
                        selectedEvent: $viewModel.selectedEvent
                    )
                    .frame(maxHeight: 340)
                } else {
                    Text("Raw backend events are hidden during the main presentation. Expand when you need tool-call, audit, or citation-level evidence.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.white.opacity(0.62))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(.secondary.opacity(0.22))
                        )
                }
            }
        }
    }
}

private struct RunSummaryView: View {
    let summary: RunSummary?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Run")
                .font(.headline)

            if let summary {
                VStack(spacing: 10) {
                    metricRow("Status", summary.status)
                    metricRow("Run ID", summary.runID)
                    metricRow("Model", summary.model)
                    metricRow("Scenario", "\(summary.kind)/\(summary.target)")
                    metricGrid(summary)
                }
            } else {
                Text("No run loaded")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.quaternary)
        )
    }

    private func metricRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .multilineTextAlignment(.trailing)
        }
        .font(.caption)
    }

    private func metricGrid(_ summary: RunSummary) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 10) {
            GridRow {
                metric("Turns", "\(summary.turns)")
                metric("Tools", "\(summary.toolCalls)")
            }
            GridRow {
                metric("Input", "\(summary.inputTokens)")
                metric("Output", "\(summary.outputTokens)")
            }
        }
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline.monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

#Preview {
    DemoRunView(viewModel: .previewLoaded())
}
