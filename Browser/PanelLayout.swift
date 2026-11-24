import Foundation

enum PanelEdge: String, CaseIterable, Codable {
    case left, right, top, bottom

    var vertical: Bool { self == .left || self == .right }
}

enum PanelMode: String, CaseIterable, Codable {
    case docked, overlay
}

enum PanelComponent: String, CaseIterable, Codable, Identifiable {
    case navigation, address, bookmarks, tabs, tools
    var id: Self { self }

    var title: String {
        switch self {
        case .navigation: "Navigation"
        case .address: "Address bar"
        case .bookmarks: "Bookmarks"
        case .tabs: "Tabs"
        case .tools: "Downloads & tools"
        }
    }

    var icon: String {
        switch self {
        case .navigation: "arrow.left.arrow.right"
        case .address: "text.magnifyingglass"
        case .bookmarks: "bookmark"
        case .tabs: "square.on.square"
        case .tools: "arrow.down.circle"
        }
    }
}

struct LayoutPanel: Codable, Equatable, Identifiable {
    var edge: PanelEdge
    var mode: PanelMode
    var size: CGFloat
    var visibility: String
    var components: [PanelComponent]

    var id: String { "\(edge.rawValue)-\(mode.rawValue)" }

    init(edge: PanelEdge, mode: PanelMode, components: [PanelComponent] = []) {
        self.edge = edge
        self.mode = mode
        self.components = components
        size = edge.vertical ? 236 : 72
        visibility = "always.js"
    }
}

struct PanelLayout: Codable, Equatable {
    var version = 1
    var panels: [LayoutPanel]

    static func read(from url: URL) throws -> Self {
        let layout = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
        try layout.validate()
        return layout
    }

    func validate() throws {
        let items = panels.flatMap(\.components)
        guard version == 1, Set(panels.map(\.id)).count == panels.count,
              Set(items).count == items.count,
              panels.allSatisfy({ !$0.components.isEmpty && (48...640).contains($0.size) }) else {
            throw CocoaError(.fileReadCorruptFile)
        }
    }

    func panel(for component: PanelComponent) -> LayoutPanel? {
        panels.first { $0.components.contains(component) }
    }

    mutating func place(_ component: PanelComponent, edge: PanelEdge, mode: PanelMode) {
        if let existing = panel(for: component), existing.edge == edge, existing.mode == mode { return }
        remove(component)
        if let index = panels.firstIndex(where: { $0.edge == edge && $0.mode == mode }) {
            panels[index].components.append(component)
        } else {
            panels.append(LayoutPanel(edge: edge, mode: mode, components: [component]))
        }
    }

    mutating func remove(_ component: PanelComponent) {
        for index in panels.indices { panels[index].components.removeAll { $0 == component } }
        panels.removeAll { $0.components.isEmpty }
    }
}

// The preview and the browser use the same point geometry. Opposing panels
// share the available space proportionally when the window becomes narrow.
struct PanelFrames {
    var webpage: CGRect
    var panels: [String: CGRect] = [:]

    init(in bounds: CGRect, panels visible: [LayoutPanel]) {
        webpage = bounds
        for mode in PanelMode.allCases {
            var interior = webpage
            for pair: (PanelEdge, PanelEdge) in [(.top, .bottom), (.left, .right)] {
                let first = visible.first { $0.mode == mode && $0.edge == pair.0 }
                let last = visible.first { $0.mode == mode && $0.edge == pair.1 }
                let total = (first?.size ?? 0) + (last?.size ?? 0)
                let available = pair.0.vertical ? interior.width : interior.height
                let factor = min(1, available * 0.7 / max(total, 1))
                for panel in [first, last].compactMap({ $0 }) {
                    let side: CGRectEdge = switch panel.edge {
                    case .left: .minXEdge
                    case .right: .maxXEdge
                    case .top: .minYEdge
                    case .bottom: .maxYEdge
                    }
                    let split = interior.divided(atDistance: panel.size * factor, from: side)
                    panels[panel.id] = split.slice
                    interior = split.remainder
                }
            }
            if mode == .docked { webpage = interior }
        }
    }
}
