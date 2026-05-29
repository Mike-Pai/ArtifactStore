import Foundation

struct DemoScenario: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let subtitle: String
    let kind: String
    let target: String
    let isRecommended: Bool
    let badge: String?

    var requestLabel: String {
        "\(kind)/\(target)"
    }

    static let authExpiry = DemoScenario(
        id: "auth-expiry",
        title: "Auth expiry failure",
        subtitle: "Small deterministic pytest failure for the main presentation.",
        kind: "pytest",
        target: "auth_expiry",
        isRecommended: true,
        badge: "recommended"
    )

    static let demoAlias = DemoScenario(
        id: "demo-alias",
        title: "Demo alias",
        subtitle: "Alias for the same auth expiry fixture, useful for checking target routing.",
        kind: "pytest",
        target: "demo",
        isRecommended: false,
        badge: "alias"
    )

    static let noisyCI = DemoScenario(
        id: "noisy-ci",
        title: "Noisy CI failure",
        subtitle: "Larger pytest log with distracting failures and more evidence noise.",
        kind: "pytest",
        target: "large",
        isRecommended: false,
        badge: nil
    )

    static let grepTodos = DemoScenario(
        id: "grep-todos",
        title: "Grep TODO evidence",
        subtitle: "Search-result fixture with TODO/FIXME noise around auth evidence.",
        kind: "grep",
        target: "todos",
        isRecommended: false,
        badge: nil
    )

    static let gitAuthDiff = DemoScenario(
        id: "git-auth-diff",
        title: "Git auth diff",
        subtitle: "Diff fixture showing the auth timezone fix across changed lines.",
        kind: "git",
        target: "auth_diff",
        isRecommended: false,
        badge: nil
    )

    static let all: [DemoScenario] = [
        .authExpiry,
        .demoAlias,
        .noisyCI,
        .grepTodos,
        .gitAuthDiff,
    ]

    static func matching(kind: String, target: String) -> DemoScenario? {
        all.first { $0.kind == kind && $0.target == target }
    }
}
