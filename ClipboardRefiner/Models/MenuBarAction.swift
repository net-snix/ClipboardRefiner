import Foundation

enum MenuBarAction: String {
    case rewrite
    case explain

    init(userData: String?) {
        let normalized = userData?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        if normalized == "explain" {
            self = .explain
        } else {
            self = .rewrite
        }
    }
}
