import SwiftUI

struct FinalDiagnosisView: View {
    let summary: RunSummary?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Final Diagnosis")
                .font(.headline)

            if let error = summary?.error, !error.isEmpty {
                Text(error)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let text = summary?.finalText, !text.isEmpty {
                ScrollView {
                    Text(text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxHeight: 320)
            } else {
                Text("Diagnosis appears here when the run finishes.")
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
}

#Preview {
    FinalDiagnosisView(summary: .mockSucceeded)
        .padding()
}
