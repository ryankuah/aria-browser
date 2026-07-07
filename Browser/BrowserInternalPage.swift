import Foundation

enum BrowserInternalPage: String, CaseIterable, Equatable, Sendable {
    case settings
    case history

    static let scheme = "browser"

    var url: URL {
        URL(string: "\(Self.scheme)://\(rawValue)")!
    }

    var title: String {
        switch self {
        case .settings:
            return "Settings"
        case .history:
            return "History"
        }
    }

    var iconSystemName: String {
        switch self {
        case .settings:
            return "gearshape"
        case .history:
            return "clock.arrow.circlepath"
        }
    }

    static func page(for url: URL?) -> BrowserInternalPage? {
        guard let url,
              url.scheme?.lowercased() == scheme else {
            return nil
        }

        let host = url.host()?.lowercased()
        let path = url.path
            .split(separator: "/")
            .first
            .map(String.init)?
            .lowercased()
        let rawPage = host?.isEmpty == false ? host : path

        switch rawPage {
        case "settings", "preferences":
            return .settings
        case "history":
            return .history
        default:
            return nil
        }
    }

    static func url(from address: String) -> URL? {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercased = trimmed.lowercased()

        guard lowercased == scheme || lowercased.hasPrefix("\(scheme)://") else {
            return nil
        }

        if let url = URL(string: trimmed), page(for: url) != nil {
            return url
        }

        return nil
    }
}
