import Foundation

struct DemoModel: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let subtitle: String
    let isRecommended: Bool
    let badge: String?

    static let deepseekV4Pro = DemoModel(
        id: "deepseek-v4-pro",
        title: "DeepSeek V4 Pro",
        subtitle: "Higher quality option for the main presentation.",
        isRecommended: true,
        badge: "recommended"
    )

    static let deepseekV4Flash = DemoModel(
        id: "deepseek-v4-flash",
        title: "DeepSeek V4 Flash",
        subtitle: "Faster, cheaper iteration option for rehearsals and UI checks.",
        isRecommended: false,
        badge: "fast"
    )

    static let all: [DemoModel] = [
        .deepseekV4Pro,
        .deepseekV4Flash,
    ]

    static func matching(id: String) -> DemoModel? {
        all.first { $0.id == id }
    }
}
