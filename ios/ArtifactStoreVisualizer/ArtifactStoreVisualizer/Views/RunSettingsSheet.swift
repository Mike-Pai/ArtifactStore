import SwiftUI

struct RunSettingsSheet: View {
    @Binding var selectedScenario: DemoScenario
    @Binding var selectedModel: DemoModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Scenario")
                            .font(.title3.weight(.semibold))
                        Text("Choose which replay fixture the demo run should diagnose.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    VStack(spacing: 10) {
                        ForEach(DemoScenario.all) { scenario in
                            ScenarioCard(
                                scenario: scenario,
                                isSelected: selectedScenario == scenario
                            ) {
                                selectedScenario = scenario
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Model")
                            .font(.title3.weight(.semibold))
                        Text("Choose which DeepSeek model the backend should use for the run.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        VStack(spacing: 10) {
                            ForEach(DemoModel.all) { model in
                                ModelCard(
                                    model: model,
                                    isSelected: selectedModel == model
                                ) {
                                    selectedModel = model
                                }
                            }
                        }
                    }
                }
                .padding(18)
            }
            .navigationTitle("Run Settings")
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
}

private struct ScenarioCard: View {
    let scenario: DemoScenario
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.blue : Color.secondary)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 8) {
                        Text(scenario.title)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        if let badge = scenario.badge {
                            Text(badge)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(scenario.isRecommended ? .blue : .secondary)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background((scenario.isRecommended ? Color.blue : Color.secondary).opacity(0.1))
                                .clipShape(Capsule())
                        }
                    }

                    Text(scenario.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(scenario.requestLabel)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Color.blue.opacity(0.08) : Color.white.opacity(0.7))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.blue : Color.secondary.opacity(0.24), lineWidth: isSelected ? 1.4 : 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct ModelCard: View {
    let model: DemoModel
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.blue : Color.secondary)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 8) {
                        Text(model.title)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        if let badge = model.badge {
                            Text(badge)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(model.isRecommended ? .blue : .secondary)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background((model.isRecommended ? Color.blue : Color.secondary).opacity(0.1))
                                .clipShape(Capsule())
                        }
                    }

                    Text(model.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(model.id)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Color.blue.opacity(0.08) : Color.white.opacity(0.7))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.blue : Color.secondary.opacity(0.24), lineWidth: isSelected ? 1.4 : 1)
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    RunSettingsSheet(
        selectedScenario: .constant(.authExpiry),
        selectedModel: .constant(.deepseekV4Pro)
    )
}
