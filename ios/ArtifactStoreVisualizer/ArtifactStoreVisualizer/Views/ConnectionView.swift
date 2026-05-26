import SwiftUI

struct ConnectionView: View {
    @ObservedObject var viewModel: DemoRunViewModel
    var showsTitle = true

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if showsTitle {
                Text("ArtifactStore Visualizer")
                    .font(.title2.weight(.semibold))
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Backend URL")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextField("http://100.110.13.83:8765", text: $viewModel.backendURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(.body, design: .monospaced))
                    .textFieldStyle(.roundedBorder)
            }

            scenarioSection

            HStack(spacing: 8) {
                Button {
                    Task { await viewModel.connect() }
                } label: {
                    Label("Connect", systemImage: "network")
                }
                .buttonStyle(SidebarPillButtonStyle(variant: .secondary))

                statusPill
            }

            HStack(spacing: 8) {
                Button {
                    Task { await viewModel.startDemo() }
                } label: {
                    Label("Start Demo", systemImage: "play.fill")
                }
                .buttonStyle(SidebarPillButtonStyle(variant: .primary))
                .disabled(viewModel.isStartingRun || viewModel.isPolling)

                Button {
                    Task { await viewModel.loadLatestTrace() }
                } label: {
                    Label("Replay", systemImage: "clock.arrow.circlepath")
                }
                .buttonStyle(SidebarPillButtonStyle(variant: .secondary))
                .accessibilityLabel("Replay latest trace")
            }

            if viewModel.isPolling {
                Label("Polling events every 0.5s", systemImage: "dot.radiowaves.left.and.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .sheet(isPresented: $viewModel.isSettingsPresented) {
            RunSettingsSheet(
                selectedScenario: $viewModel.selectedScenario,
                selectedModel: $viewModel.selectedModel
            )
        }
    }

    private var scenarioSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Scenario")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    viewModel.isSettingsPresented = true
                } label: {
                    Label("Configure", systemImage: "slider.horizontal.3")
                }
                .font(.caption)
                .buttonStyle(CompactSidebarButtonStyle())
                .disabled(viewModel.isStartingRun || viewModel.isPolling)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(viewModel.selectedScenario.title)
                    .font(.subheadline.weight(.semibold))
                Text(viewModel.selectedScenario.requestLabel)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                Text(viewModel.selectedModelLabel)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.65))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.secondary.opacity(0.22))
            )
        }
    }

    private var statusPill: some View {
        let state = statusPresentation
        return Label(state.text, systemImage: state.systemImage)
            .font(.subheadline.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.78)
            .labelStyle(.titleAndIcon)
            .foregroundStyle(state.color)
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.horizontal, 12)
            .background(state.color.opacity(0.1))
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(state.color.opacity(0.22), lineWidth: 1)
            )
    }

    private var statusPresentation: (text: String, systemImage: String, color: Color) {
        switch viewModel.connectionState {
        case .connected:
            return ("Connected", "checkmark.circle.fill", .green)
        case .checking:
            return ("Checking", "hourglass", .secondary)
        case .disconnected:
            return ("Offline", "xmark.circle.fill", .red)
        case .idle:
            return ("Not checked", "circle", .secondary)
        }
    }
}

private struct SidebarPillButtonStyle: ButtonStyle {
    enum Variant {
        case primary
        case secondary
    }

    let variant: Variant
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.78)
            .labelStyle(.titleAndIcon)
            .foregroundStyle(foregroundColor)
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.horizontal, 12)
            .background(backgroundColor(configuration: configuration))
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(borderColor, lineWidth: 1)
            )
            .opacity(isEnabled ? 1 : 0.46)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }

    private var foregroundColor: Color {
        switch variant {
        case .primary:
            return .white
        case .secondary:
            return .blue
        }
    }

    private func backgroundColor(configuration: Configuration) -> Color {
        switch variant {
        case .primary:
            return configuration.isPressed ? Color.blue.opacity(0.78) : Color.blue
        case .secondary:
            return configuration.isPressed ? Color.blue.opacity(0.14) : Color.blue.opacity(0.08)
        }
    }

    private var borderColor: Color {
        switch variant {
        case .primary:
            return Color.blue.opacity(0.35)
        case .secondary:
            return Color.blue.opacity(0.18)
        }
    }
}

private struct CompactSidebarButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .foregroundStyle(.blue)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(configuration.isPressed ? Color.blue.opacity(0.14) : Color.blue.opacity(0.08))
            .clipShape(Capsule())
            .opacity(isEnabled ? 1 : 0.46)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

#Preview {
    ConnectionView(viewModel: DemoRunViewModel())
        .padding()
}
