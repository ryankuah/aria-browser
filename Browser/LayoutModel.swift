import CoreGraphics
import Foundation

/// A prop value as it appears in the layout file.
enum JSONValue: Codable, Hashable, Sendable {
    case number(Double)
    case string(String)
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else { self = .string(try container.decode(String.self)) }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .number(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    var number: Double? { if case .number(let value) = self { value } else { nil } }
    var string: String? { if case .string(let value) = self { value } else { nil } }
    var bool: Bool? { if case .bool(let value) = self { value } else { nil } }

    /// A Foundation value that WebKit can pass to JavaScript.
    var foundation: Any {
        switch self {
        case .number(let value): value
        case .string(let value): value
        case .bool(let value): value
        case .null: NSNull()
        }
    }
}

/// Any JSON value: browser state, a component's own state, and the values actions carry.
enum AnyJSON: Codable, Hashable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([AnyJSON])
    case object([String: AnyJSON])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([AnyJSON].self) { self = .array(value) }
        else { self = .object(try container.decode([String: AnyJSON].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }

    var string: String? { if case .string(let value) = self { value } else { nil } }
    var number: Double? { if case .number(let value) = self { value } else { nil } }
    var bool: Bool? { if case .bool(let value) = self { value } else { nil } }
    var array: [AnyJSON]? { if case .array(let value) = self { value } else { nil } }
    var object: [String: AnyJSON]? { if case .object(let value) = self { value } else { nil } }
    subscript(key: String) -> AnyJSON? { object?[key] }

    /// A Foundation value that WebKit can pass to JavaScript.
    var foundation: Any {
        switch self {
        case .null: NSNull()
        case .bool(let value): value
        case .number(let value): value
        case .string(let value): value
        case .array(let value): value.map(\.foundation)
        case .object(let value): value.mapValues(\.foundation)
        }
    }
}

extension AnyJSON: ExpressibleByStringLiteral, ExpressibleByBooleanLiteral, ExpressibleByFloatLiteral,
                   ExpressibleByIntegerLiteral, ExpressibleByArrayLiteral, ExpressibleByDictionaryLiteral, ExpressibleByNilLiteral {
    init(stringLiteral value: String) { self = .string(value) }
    init(booleanLiteral value: Bool) { self = .bool(value) }
    init(floatLiteral value: Double) { self = .number(value) }
    init(integerLiteral value: Int) { self = .number(Double(value)) }
    init(arrayLiteral elements: AnyJSON...) { self = .array(elements) }
    init(dictionaryLiteral elements: (String, AnyJSON)...) { self = .object(Dictionary(elements) { _, last in last }) }
    init(nilLiteral: ()) { self = .null }

    init(_ value: String?) { self = value.map(AnyJSON.string) ?? .null }
    init(_ value: Double?) { self = value.map(AnyJSON.number) ?? .null }
    init(_ value: Int) { self = .number(Double(value)) }
    init(_ value: Bool) { self = .bool(value) }
}

enum PanelEdge: String, CaseIterable, Codable, Sendable {
    case left, right, top, bottom

    var vertical: Bool { self == .left || self == .right }
}

/// Where something sits in the window. Edges that have a value are pinned,
/// so it follows that edge when the window resizes, like CSS absolute positioning.
struct Placement: Codable, Equatable, Sendable {
    var left: Double?
    var top: Double?
    var right: Double?
    var bottom: Double?
    var width: Double?
    var height: Double?
    /// Fill the gap between the WebView and this window edge.
    var attach: PanelEdge?

    var isEmpty: Bool { self == Placement() }

    func pinned(_ edge: PanelEdge) -> Bool {
        switch edge {
        case .left: left != nil
        case .right: right != nil
        case .top: top != nil
        case .bottom: bottom != nil
        }
    }

    /// Resolves the placement inside `area`.
    func rect(in area: CGRect, natural: CGSize) -> CGRect {
        func axis(_ start: Double?, _ length: Double?, _ end: Double?, from low: CGFloat, to high: CGFloat,
                  natural: CGFloat) -> (CGFloat, CGFloat) {
            switch (start, end) {
            case let (start?, end?): return (low + start, max(0, high - low - start - end))
            case let (start?, nil): return (low + start, length ?? natural)
            case let (nil, end?): let size = length ?? natural; return (high - end - size, size)
            case (nil, nil): let size = length ?? natural; return ((low + high - size) / 2, size)
            }
        }
        let x = axis(left, width, right, from: area.minX, to: area.maxX, natural: natural.width)
        let y = axis(top, height, bottom, from: area.minY, to: area.maxY, natural: natural.height)
        return CGRect(x: x.0, y: y.0, width: max(0, x.1), height: max(0, y.1))
    }

    /// Places it at `rect` while keeping which edges are pinned.
    /// With no pins at all, it is pinned to the top-left corner.
    mutating func place(_ rect: CGRect, in area: CGRect, pins: Set<PanelEdge>? = nil) {
        var pins = pins ?? Set(PanelEdge.allCases.filter(pinned))
        if !pins.contains(.left) && !pins.contains(.right) { pins.insert(.left) }
        if !pins.contains(.top) && !pins.contains(.bottom) { pins.insert(.top) }
        left = pins.contains(.left) ? (rect.minX - area.minX).rounded() : nil
        right = pins.contains(.right) ? (area.maxX - rect.maxX).rounded() : nil
        top = pins.contains(.top) ? (rect.minY - area.minY).rounded() : nil
        bottom = pins.contains(.bottom) ? (area.maxY - rect.maxY).rounded() : nil
        width = pins.contains(.left) && pins.contains(.right) ? nil : rect.width.rounded()
        height = pins.contains(.top) && pins.contains(.bottom) ? nil : rect.height.rounded()
        attach = nil
    }
}

/// One thing placed in the window or in a component's slot: the WebView,
/// a component, or a hover area that opens a component.
struct LayoutNode: Codable, Equatable, Identifiable, Sendable {
    enum Role: String, Codable, Sendable {
        /// The component itself.
        case view
        /// An invisible area that opens the component while the pointer is over it.
        case hover
    }

    var id: String
    /// "WebView", or the name of a component.
    var type: String
    var role: Role = .view
    /// Where it sits in the window. Unused inside a slot, which lines its children up.
    var layout = Placement()
    /// Components placed in the slots its file renders, by slot name, in order.
    var slots: [String: [LayoutNode]] = [:]

    init(id: String = LayoutNode.newID(), type: String, role: Role = .view, layout: Placement = Placement(),
         slots: [String: [LayoutNode]] = [:]) {
        self.id = id
        self.type = type
        self.role = role
        self.layout = layout
        self.slots = slots
    }

    static func newID() -> String { UUID().uuidString.prefix(8).lowercased() }

    private enum CodingKeys: String, CodingKey { case id, type, role, layout, slots }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        type = try container.decode(String.self, forKey: .type)
        role = try container.decodeIfPresent(Role.self, forKey: .role) ?? .view
        layout = try container.decodeIfPresent(Placement.self, forKey: .layout) ?? Placement()
        slots = try container.decodeIfPresent([String: [LayoutNode]].self, forKey: .slots) ?? [:]
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(type, forKey: .type)
        if role != .view { try container.encode(role, forKey: .role) }
        if !layout.isEmpty { try container.encode(layout, forKey: .layout) }
        let filled = slots.filter { !$0.value.isEmpty }
        if !filled.isEmpty { try container.encode(filled, forKey: .slots) }
    }

    /// This node and everything in its slots, depth first.
    var flattened: [LayoutNode] {
        [self] + slots.keys.sorted().flatMap { slots[$0]!.flatMap(\.flattened) }
    }
}

/// A named slot of a placed component.
struct SlotAddress: Hashable, Sendable {
    var owner: String
    var name: String
}

struct LayoutDocument: Codable, Equatable, Sendable {
    static let currentVersion = 8
    static let webViewType = "WebView"

    var version = currentVersion
    /// Everything placed in the window. Later nodes draw on top.
    var root: [LayoutNode]
    /// Prop values set in the editor, by component name.
    var props: [String: [String: JSONValue]] = [:]

    init(root: [LayoutNode], props: [String: [String: JSONValue]] = [:]) {
        self.root = root
        self.props = props
    }

    private enum CodingKeys: String, CodingKey { case version, root, props }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        root = try container.decode([LayoutNode].self, forKey: .root)
        props = try container.decodeIfPresent([String: [String: JSONValue]].self, forKey: .props) ?? [:]
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(root, forKey: .root)
        let set = props.filter { !$0.value.isEmpty }
        if !set.isEmpty { try container.encode(set, forKey: .props) }
    }

    static func read(from url: URL) throws -> Self {
        let document = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
        try document.validate()
        return document
    }

    var webView: LayoutNode? { root.first { $0.type == Self.webViewType } }

    /// Everything placed, including what sits in slots.
    var allNodes: [LayoutNode] { root.flatMap(\.flattened) }

    /// Where a component is placed directly in the window, if it is.
    func view(of type: String) -> LayoutNode? {
        root.first { $0.type == type && $0.role == .view }
    }

    func nodes(of type: String) -> [LayoutNode] { allNodes.filter { $0.type == type } }

    func node(_ id: String) -> LayoutNode? { allNodes.first { $0.id == id } }

    func props(of type: String) -> [String: JSONValue] { props[type] ?? [:] }

    /// The slot holding `id`, or nil when it sits directly in the window.
    func address(of id: String) -> SlotAddress? {
        for node in allNodes {
            for (name, children) in node.slots where children.contains(where: { $0.id == id }) {
                return SlotAddress(owner: node.id, name: name)
            }
        }
        return nil
    }

    /// The node placed directly in the window that holds `id`, or `id` itself.
    func host(of id: String) -> LayoutNode? {
        root.first { $0.flattened.contains { $0.id == id } }
    }

    func children(of address: SlotAddress) -> [LayoutNode] {
        node(address.owner)?.slots[address.name] ?? []
    }

    func validate() throws {
        let nodes = allNodes
        let numbers = root.flatMap { node in
            [node.layout.left, node.layout.top, node.layout.right, node.layout.bottom,
             node.layout.width, node.layout.height].compactMap { $0 }
        }
        let nested = nodes.filter { node in !root.contains { $0.id == node.id } }
        guard version == Self.currentVersion,
              Set(nodes.map(\.id)).count == nodes.count,
              root.filter({ $0.type == Self.webViewType }).count <= 1,
              !root.contains(where: { $0.type == Self.webViewType && $0.role != .view }),
              // Slots hold components; the page and hover areas belong to the window.
              !nested.contains(where: { $0.type == Self.webViewType || $0.role != .view }),
              numbers.allSatisfy(\.isFinite) else {
            throw CocoaError(.fileReadCorruptFile)
        }
    }

    // MARK: Editing

    mutating func update(_ id: String, _ change: (inout LayoutNode) -> Void) {
        func visit(_ nodes: inout [LayoutNode]) -> Bool {
            for index in nodes.indices {
                if nodes[index].id == id { change(&nodes[index]); return true }
                for key in nodes[index].slots.keys where visit(&nodes[index].slots[key]!) { return true }
            }
            return false
        }
        _ = visit(&root)
    }

    private mutating func edit(_ address: SlotAddress?, _ change: (inout [LayoutNode]) -> Void) {
        guard let address else { change(&root); return }
        update(address.owner) { node in
            var children = node.slots[address.name] ?? []
            change(&children)
            node.slots[address.name] = children.isEmpty ? nil : children
        }
    }

    /// Takes the node out of the layout and returns it.
    @discardableResult
    mutating func remove(_ id: String) -> LayoutNode? {
        var removed: LayoutNode?
        edit(address(of: id)) { children in
            if let index = children.firstIndex(where: { $0.id == id }) { removed = children.remove(at: index) }
        }
        return removed
    }

    /// Inserts into a slot, or into the window when `address` is nil.
    mutating func insert(_ node: LayoutNode, into address: SlotAddress? = nil, at index: Int? = nil) {
        edit(address) { children in
            children.insert(node, at: min(max(0, index ?? children.count), children.count))
        }
    }

    /// Moves a node within its slot or the window. In the window, later nodes draw on top.
    mutating func reorder(_ id: String, by offset: Int) {
        edit(address(of: id)) { children in
            guard let index = children.firstIndex(where: { $0.id == id }) else { return }
            let target = min(max(0, index + offset), children.count - 1)
            children.insert(children.remove(at: index), at: target)
        }
    }
}

// MARK: Window layout

/// Frames of everything placed in the window.
struct WindowFrames: Equatable {
    var frames: [String: CGRect] = [:]
    /// The WebView's frame, before it grows into the gaps of closed components.
    var webView: CGRect?

    /// Lays out the window inside `bounds`. `hidden` holds views of closed components.
    init(_ document: LayoutDocument, in bounds: CGRect, hidden: Set<String> = [],
         natural: (LayoutNode) -> CGSize) {
        guard let web = document.webView else {
            for node in document.root { frames[node.id] = node.layout.rect(in: bounds, natural: natural(node)) }
            return
        }
        let base = web.layout.rect(in: bounds, natural: bounds.size).intersection(bounds)
        webView = base
        var grown = base
        for node in document.root where node.id != web.id {
            if let side = node.layout.attach {
                frames[node.id] = Self.gap(side, beside: base, in: bounds)
            } else {
                frames[node.id] = node.layout.rect(in: bounds, natural: natural(node))
            }
        }
        if document.props(of: web.type)["fillWhenNeighbourHidden"]?.bool ?? true {
            for side in PanelEdge.allCases {
                let attached = document.root.filter { $0.layout.attach == side && $0.id != web.id }
                guard !attached.isEmpty, attached.allSatisfy({ hidden.contains($0.id) }) else { continue }
                switch side {
                case .left: grown = CGRect(x: bounds.minX, y: grown.minY, width: grown.maxX - bounds.minX, height: grown.height)
                case .right: grown.size.width = bounds.maxX - grown.minX
                case .top: grown = CGRect(x: grown.minX, y: bounds.minY, width: grown.width, height: grown.maxY - bounds.minY)
                case .bottom: grown.size.height = bounds.maxY - grown.minY
                }
            }
        }
        frames[web.id] = grown
    }

    /// The space between the WebView and one window edge. Side gaps run the
    /// full height; top and bottom gaps run between them.
    static func gap(_ side: PanelEdge, beside web: CGRect, in bounds: CGRect) -> CGRect {
        switch side {
        case .left: CGRect(x: bounds.minX, y: bounds.minY, width: max(0, web.minX - bounds.minX), height: bounds.height)
        case .right: CGRect(x: web.maxX, y: bounds.minY, width: max(0, bounds.maxX - web.maxX), height: bounds.height)
        case .top: CGRect(x: web.minX, y: bounds.minY, width: web.width, height: max(0, web.minY - bounds.minY))
        case .bottom: CGRect(x: web.minX, y: web.maxY, width: web.width, height: max(0, bounds.maxY - web.maxY))
        }
    }
}
