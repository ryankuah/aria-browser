import SwiftUI

/// The kinds of prop a component can declare. The editor turns each into a control.
enum PropKind: Equatable, Sendable {
    case number(min: Double, max: Double, step: Double)
    case choice([String])
    case toggle
    case text
}

struct PropSpec: Equatable, Identifiable, Sendable {
    let name: String
    let label: String
    let kind: PropKind
    let defaultValue: JSONValue
    var id: String { name }
}

/// Where a component appears.
enum OpensAs: String, Sendable {
    /// Where it is placed in the editor: in the window, or in another component's slot.
    case placed
    /// In the middle of the window, over everything else, while something has it open.
    case overlay
    /// Nowhere: the component only adds key bindings or takes over commands.
    case nowhere = "none"
}

/// How a component appears and disappears.
enum ComponentTransition: String, Sendable {
    case fade, slide, scale, none
}

/// A key binding a component file declares in `keys`.
struct KeyBinding: Equatable, Sendable {
    var keys: String
    var shortcut: KeyShortcut
    var action: PieceAction
}

/// The parts of the browser state a component can ask for in `uses`. The rest is always given.
enum StateSection {
    static let all: Set<String> = ["tabs", "bookmarks", "downloads", "page", "settings", "scripts", "console", "notices"]
}

/// Something that opens a component, declared in its file.
struct Activator: Equatable, Sendable {
    enum Kind: String, Sendable {
        /// An invisible area placed in the editor. Open while the pointer is over it or the component.
        case hover
        /// A keyboard shortcut. Opens and closes the component.
        case shortcut
        /// A function of the browser's state. Open while it returns true.
        case when
    }

    var kind: Kind
    var edge: PanelEdge?
    var size: Double?
    var icon: String?
    var label: String?
    var help: String?
    var keys: String?
    /// How long a hover-opened component stays open after the pointer leaves, in seconds.
    var closeDelay: Double?
}

struct ComponentDefinition: Identifiable, Sendable {
    let type: String
    let title: String
    let icon: String
    let summary: String
    var props: [PropSpec]
    var activators: [Activator] = []
    var opensAs: OpensAs = .placed
    /// Its size when placed freely in the window, or as an overlay. Nil fits the content.
    var width: CGFloat?
    var height: CGFloat?
    /// The component's file.
    var source: URL?
    /// The named parts its layout arranges, in the order the file lists them.
    var parts: [PartInfo] = []
    /// How its parts are arranged, when it has parts rather than one render function.
    var layout: PartLayout?
    /// Its file marks where the layout is, so the editor can rewrite it.
    var layoutEditable = false
    /// Set by the file's `alwaysOpen`. Without it, a component with no activators is always open.
    var alwaysOpenOverride: Bool?
    /// The parts of the browser state it reads, beyond the basics.
    var uses: Set<String> = []
    /// Its own state when it opens, before anything sets it.
    var local: [String: AnyJSON] = [:]
    var keys: [KeyBinding] = []
    /// Commands it takes over, like newTab or find, and what it does instead.
    var handles: [String: PieceAction] = [:]
    var onOpen: PieceAction?
    var onClose: PieceAction?
    var transition: ComponentTransition = .fade
    /// The edge it slides in from. Defaults to its hover edge, or the window edge it sits nearest.
    var slideFrom: PanelEdge?
    /// What an overlay puts behind itself: "dim", "accent" or "none".
    var scrim = "dim"
    /// Where an overlay sits: "center" or "top".
    var overlayAlign = "center"
    /// Clicks go through it to whatever is below.
    var clickThrough = false
    var id: String { type }

    func part(_ name: String) -> PartInfo? { parts.first { $0.name == name } }

    var isWebView: Bool { type == LayoutDocument.webViewType }
    var naturalSize: CGSize { CGSize(width: width ?? 260, height: height ?? 420) }
    /// A component with nothing to open it is always open, unless its file says otherwise.
    var alwaysOpen: Bool { alwaysOpenOverride ?? activators.isEmpty }

    func prop(_ name: String) -> PropSpec? { props.first { $0.name == name } }

    func value(_ name: String, in props: [String: JSONValue]) -> JSONValue? {
        props[name] ?? prop(name)?.defaultValue
    }

    /// Every prop with its value, defaults filled in.
    func resolved(_ props: [String: JSONValue]) -> [String: JSONValue] {
        Dictionary(uniqueKeysWithValues: self.props.map { ($0.name, props[$0.name] ?? $0.defaultValue) })
    }

    func activator(_ kind: Activator.Kind) -> Activator? { activators.first { $0.kind == kind } }

    /// The things the editor can place for this component.
    var placeableRoles: [LayoutNode.Role] {
        var roles: [LayoutNode.Role] = []
        if opensAs == .placed { roles.append(.view) }
        if activator(.hover) != nil { roles.append(.hover) }
        return roles
    }

    func natural(_ role: LayoutNode.Role) -> CGSize {
        switch role {
        case .view:
            return naturalSize
        case .hover:
            let hover = activator(.hover)
            let thickness = CGFloat(hover?.size ?? 6)
            return hover?.edge.map { $0.vertical } ?? true
                ? CGSize(width: thickness, height: 320) : CGSize(width: 320, height: thickness)
        }
    }
}

// MARK: Parts

/// A named part of a component, declared in its file's `parts`.
struct PartInfo: Equatable, Sendable, Decodable {
    var name: String
    var title: String
    var icon: String?
}

/// How a component's parts are arranged: its file's `layout`. The layout editor
/// rearranges it and writes it back into the file.
struct PartLayout: Codable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable {
        case row, column, spacer, divider, part, slot
    }

    var kind: Kind
    /// A part's or a slot's name.
    var name: String?
    var children: [PartLayout] = []
    var spacing: Double?
    var align: String?
    /// A slot's direction: "row" or "column".
    var direction: String?
    var grow: Bool?
    var width: Double?
    var height: Double?
    /// Horizontal and vertical padding.
    var padding: [Double]?

    init(kind: Kind, name: String? = nil, children: [PartLayout] = []) {
        self.kind = kind
        self.name = name
        self.children = children
    }

    private enum CodingKeys: String, CodingKey {
        case kind, name, children, spacing, align, direction, grow, width, height, padding
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try c.decode(Kind.self, forKey: .kind)
        name = try c.decodeIfPresent(String.self, forKey: .name)
        children = try c.decodeIfPresent([PartLayout].self, forKey: .children) ?? []
        spacing = try c.decodeIfPresent(Double.self, forKey: .spacing)
        align = try c.decodeIfPresent(String.self, forKey: .align)
        direction = try c.decodeIfPresent(String.self, forKey: .direction)
        grow = try c.decodeIfPresent(Bool.self, forKey: .grow)
        width = try c.decodeIfPresent(Double.self, forKey: .width)
        height = try c.decodeIfPresent(Double.self, forKey: .height)
        padding = try c.decodeIfPresent([Double].self, forKey: .padding)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(kind, forKey: .kind)
        try c.encodeIfPresent(name, forKey: .name)
        if isContainer { try c.encode(children, forKey: .children) }
        try c.encodeIfPresent(spacing, forKey: .spacing)
        try c.encodeIfPresent(align, forKey: .align)
        try c.encodeIfPresent(direction, forKey: .direction)
        try c.encodeIfPresent(grow, forKey: .grow)
        try c.encodeIfPresent(width, forKey: .width)
        try c.encodeIfPresent(height, forKey: .height)
        try c.encodeIfPresent(padding, forKey: .padding)
    }

    var isContainer: Bool { kind == .row || kind == .column }

    /// The node at a path of child indexes. The empty path is this node.
    subscript(path: [Int]) -> PartLayout? {
        var node = self
        for index in path {
            guard node.children.indices.contains(index) else { return nil }
            node = node.children[index]
        }
        return node
    }

    mutating func modify(_ path: [Int], _ change: (inout PartLayout) -> Void) {
        guard let first = path.first else { change(&self); return }
        guard children.indices.contains(first) else { return }
        children[first].modify(Array(path.dropFirst()), change)
    }

    /// Every path in the tree, depth first, starting with this node's.
    var paths: [[Int]] {
        [[]] + children.enumerated().flatMap { index, child in child.paths.map { [index] + $0 } }
    }

    /// The names of the parts this layout uses.
    var partNames: [String] { paths.compactMap { self[$0].flatMap { $0.kind == .part ? $0.name : nil } } }
    var slotNames: [String] { paths.compactMap { self[$0].flatMap { $0.kind == .slot ? $0.name : nil } } }

    @discardableResult
    mutating func remove(at path: [Int]) -> PartLayout? {
        guard let index = path.last, self[path] != nil else { return nil }
        var removed: PartLayout?
        modify(Array(path.dropLast())) { removed = $0.children.remove(at: index) }
        return removed
    }

    mutating func insert(_ node: PartLayout, into container: [Int], at index: Int) {
        modify(container) { $0.children.insert(node, at: min(max(0, index), $0.children.count)) }
    }

    /// Moves a node into a container. The index counts the container's children
    /// without the moved node. Returns the node's new path.
    @discardableResult
    mutating func move(_ path: [Int], into container: [Int], at index: Int) -> [Int]? {
        guard let removedIndex = path.last, !container.starts(with: path), self[container]?.isContainer == true else { return nil }
        let parent = Array(path.dropLast())
        var container = container
        // Taking the node out shifts later siblings of its parent's branch.
        if container.count > parent.count, container.starts(with: parent), container[parent.count] > removedIndex {
            container[parent.count] -= 1
        }
        guard let node = remove(at: path), let target = self[container] else { return nil }
        let clamped = min(max(0, index), target.children.count)
        insert(node, into: container, at: clamped)
        return container + [clamped]
    }

    /// Puts the node at `path` inside a new row or column.
    mutating func wrap(_ path: [Int], in kind: Kind) {
        modify(path) { node in node = PartLayout(kind: kind, children: [node]) }
    }

    /// Replaces a row or column with its children.
    mutating func ungroup(_ path: [Int]) {
        guard let index = path.last, let node = self[path], node.isContainer else { return }
        modify(Array(path.dropLast())) { $0.children.replaceSubrange(index...index, with: node.children) }
    }

    // MARK: Writing the file

    /// The layout as JavaScript, the way a component file writes it.
    func javaScript(indent: String = "") -> String {
        let options = optionsLiteral
        switch kind {
        case .part, .slot:
            return "\(kind.rawValue)(\(Self.string(name ?? ""))\(options.isEmpty ? "" : ", " + options))"
        case .spacer, .divider:
            return "\(kind.rawValue)(\(options))"
        case .row, .column:
            let tail = "]" + (options.isEmpty ? "" : ", " + options) + ")"
            let inline = "\(kind.rawValue)([" + children.map { $0.javaScript() }.joined(separator: ", ") + tail
            if !children.contains(where: \.isContainer), indent.count + inline.count <= 110 { return inline }
            let inner = indent + "  "
            return "\(kind.rawValue)([\n" + children.map { inner + $0.javaScript(indent: inner) + ",\n" }.joined() + indent + tail
        }
    }

    private var optionsLiteral: String {
        var entries: [String] = []
        if let spacing { entries.append("spacing: \(Self.number(spacing))") }
        if let align { entries.append("align: \(Self.string(align))") }
        if kind == .slot, direction == "column" { entries.append("direction: \"column\"") }
        if grow == true { entries.append("grow: true") }
        if let width { entries.append("width: \(Self.number(width))") }
        if let height { entries.append("height: \(Self.number(height))") }
        if let padding, padding.count == 2 {
            entries.append(padding[0] == padding[1] ? "padding: \(Self.number(padding[0]))"
                           : "padding: [\(Self.number(padding[0])), \(Self.number(padding[1]))]")
        }
        return entries.isEmpty ? "" : "{ " + entries.joined(separator: ", ") + " }"
    }

    private static func number(_ value: Double) -> String {
        value.rounded() == value && abs(value) < 1e15 ? String(Int(value)) : String(value)
    }

    private static func string(_ value: String) -> String {
        (try? JSONEncoder().encode(value)).flatMap { String(data: $0, encoding: .utf8) } ?? "\"\""
    }
}

/// Finds and rewrites the layout in a component file.
enum ComponentFile {
    static let startMarker = "<aria:layout>"
    static let endMarker = "</aria:layout>"

    /// The lines between the markers, when the file has both.
    static func layoutRange(in lines: [String]) -> Range<Int>? {
        guard let start = lines.firstIndex(where: { $0.contains(startMarker) }),
              let end = lines[(start + 1)...].firstIndex(where: { $0.contains(endMarker) }) else { return nil }
        return (start + 1)..<end
    }

    static func hasLayoutMarkers(_ source: String) -> Bool {
        layoutRange(in: source.components(separatedBy: "\n")) != nil
    }

    /// The file with everything between the markers replaced by `layout`.
    static func replacingLayout(in source: String, with layout: PartLayout) throws -> String {
        var lines = source.components(separatedBy: "\n")
        guard let range = layoutRange(in: lines) else {
            throw NSError(domain: "Aria.Components", code: 4, userInfo: [NSLocalizedDescriptionKey:
                "Put // \(startMarker) and // \(endMarker) on the lines around layout so Aria can rewrite it."])
        }
        let indent = String(lines[range.lowerBound - 1].prefix { $0 == " " || $0 == "\t" })
        let code = indent + "layout: " + layout.javaScript(indent: indent) + ","
        lines.replaceSubrange(range, with: code.components(separatedBy: "\n"))
        return lines.joined(separator: "\n")
    }
}

// MARK: Rendered pieces

/// What a button does. Commands are built in; functions run in the component's file.
struct PieceAction: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable {
        case command, open, close, toggle, openTab, navigate
        /// Sets a key of the component's own state to `arg`.
        case set
        /// A function in the component's file: by its position in the rendered tree (`index`),
        /// or by where the spec keeps it (`target`), like "keys/cmd+l" or "onOpen".
        case fn
    }

    var kind: Kind
    var target: String = ""
    var index: Int?
    /// A command's argument, or the value `set` stores.
    var arg: AnyJSON?

    init(kind: Kind, target: String = "", index: Int? = nil, arg: AnyJSON? = nil) {
        self.kind = kind
        self.target = target
        self.index = index
        self.arg = arg
    }

    private enum CodingKeys: String, CodingKey { case kind, target, index, arg }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(Kind.self, forKey: .kind)
        target = try container.decodeIfPresent(String.self, forKey: .target) ?? ""
        index = try container.decodeIfPresent(Int.self, forKey: .index)
        arg = try container.decodeIfPresent(AnyJSON.self, forKey: .arg)
    }
}

/// One piece of a component's rendered tree.
struct Piece: Decodable, Equatable, Sendable {
    var kind: String
    var children: [Piece] = []
    var text: String?
    var icon: String?
    var label: String?
    var help: String?
    var style: String?
    var align: String?
    var spacing: Double?
    var size: Double?
    var width: Double?
    var height: Double?
    /// Horizontal and vertical padding.
    var padding: [Double]?
    var grow = false
    var enabled = true
    var active = false
    var badge: Double?
    var action: PieceAction?
    /// A slot's name.
    var name: String?
    /// A slot's direction: "row" or "column".
    var direction: String?
    /// What a button shows in a popover when clicked. Empty, or one piece.
    var popover: [Piece] = []
    /// Where a piece made from the component's layout sits in it, like "0.2". The root is "".
    var at: String?

    // Options any piece takes.
    var minWidth: Double?
    var maxWidth: Double?
    var minHeight: Double?
    var maxHeight: Double?
    var color: String?
    var background: String?
    var hoverBackground: String?
    var border: String?
    var cornerRadius: Double?
    var opacity: Double?
    /// Tracks the pointer, for pieces inside it that show only on hover.
    var hoverGroup = false
    var showOnHover = false
    var menu: [MenuItem] = []
    /// What dragging the piece carries: a string the drop target's function receives.
    var drag: String?
    var onDrop: PieceAction?

    // Text.
    var weight: String?
    var lineLimit: Double?
    var truncate: String?
    var monospaced = false

    // Text fields.
    var bind: String?
    var placeholder: String?
    var suggest: String?
    var autofocus = false
    var selectAll = false
    var onSubmit: PieceAction?
    var onChange: PieceAction?
    var onKey: [String: PieceAction] = [:]

    // Favicons, progress bars, switches and scroll areas.
    var src: String?
    var value: Double?
    var on = false
    var followEnd: String?
    var indicators = false

    private enum CodingKeys: String, CodingKey {
        case kind, children, text, icon, label, help, style, align, spacing, size, width, height, padding
        case grow, enabled, active, badge, action, name, direction, popover, at
        case minWidth, maxWidth, minHeight, maxHeight, color, background, hoverBackground, border, cornerRadius, opacity
        case hoverGroup, showOnHover, menu, drag, onDrop, weight, lineLimit, truncate, monospaced
        case bind, placeholder, suggest, autofocus, selectAll, onSubmit, onChange, onKey, src, value, on, indicators, followEnd
    }

    init(kind: String, children: [Piece] = []) {
        self.kind = kind
        self.children = children
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try c.decode(String.self, forKey: .kind)
        children = try c.decodeIfPresent([Piece].self, forKey: .children) ?? []
        text = try c.decodeIfPresent(String.self, forKey: .text)
        icon = try c.decodeIfPresent(String.self, forKey: .icon)
        label = try c.decodeIfPresent(String.self, forKey: .label)
        help = try c.decodeIfPresent(String.self, forKey: .help)
        style = try c.decodeIfPresent(String.self, forKey: .style)
        align = try c.decodeIfPresent(String.self, forKey: .align)
        spacing = try c.decodeIfPresent(Double.self, forKey: .spacing)
        size = try c.decodeIfPresent(Double.self, forKey: .size)
        width = try c.decodeIfPresent(Double.self, forKey: .width)
        height = try c.decodeIfPresent(Double.self, forKey: .height)
        padding = try c.decodeIfPresent([Double].self, forKey: .padding)
        grow = try c.decodeIfPresent(Bool.self, forKey: .grow) ?? false
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        active = try c.decodeIfPresent(Bool.self, forKey: .active) ?? false
        badge = try c.decodeIfPresent(Double.self, forKey: .badge)
        action = try c.decodeIfPresent(PieceAction.self, forKey: .action)
        name = try c.decodeIfPresent(String.self, forKey: .name)
        direction = try c.decodeIfPresent(String.self, forKey: .direction)
        popover = try c.decodeIfPresent([Piece].self, forKey: .popover) ?? []
        at = try c.decodeIfPresent(String.self, forKey: .at)
        minWidth = try c.decodeIfPresent(Double.self, forKey: .minWidth)
        maxWidth = try c.decodeIfPresent(Double.self, forKey: .maxWidth)
        minHeight = try c.decodeIfPresent(Double.self, forKey: .minHeight)
        maxHeight = try c.decodeIfPresent(Double.self, forKey: .maxHeight)
        color = try c.decodeIfPresent(String.self, forKey: .color)
        background = try c.decodeIfPresent(String.self, forKey: .background)
        hoverBackground = try c.decodeIfPresent(String.self, forKey: .hoverBackground)
        border = try c.decodeIfPresent(String.self, forKey: .border)
        cornerRadius = try c.decodeIfPresent(Double.self, forKey: .cornerRadius)
        opacity = try c.decodeIfPresent(Double.self, forKey: .opacity)
        hoverGroup = try c.decodeIfPresent(Bool.self, forKey: .hoverGroup) ?? false
        showOnHover = try c.decodeIfPresent(Bool.self, forKey: .showOnHover) ?? false
        menu = try c.decodeIfPresent([MenuItem].self, forKey: .menu) ?? []
        drag = try c.decodeIfPresent(String.self, forKey: .drag)
        onDrop = try c.decodeIfPresent(PieceAction.self, forKey: .onDrop)
        weight = try c.decodeIfPresent(String.self, forKey: .weight)
        lineLimit = try c.decodeIfPresent(Double.self, forKey: .lineLimit)
        truncate = try c.decodeIfPresent(String.self, forKey: .truncate)
        monospaced = try c.decodeIfPresent(Bool.self, forKey: .monospaced) ?? false
        bind = try c.decodeIfPresent(String.self, forKey: .bind)
        placeholder = try c.decodeIfPresent(String.self, forKey: .placeholder)
        suggest = try c.decodeIfPresent(String.self, forKey: .suggest)
        autofocus = try c.decodeIfPresent(Bool.self, forKey: .autofocus) ?? false
        selectAll = try c.decodeIfPresent(Bool.self, forKey: .selectAll) ?? false
        onSubmit = try c.decodeIfPresent(PieceAction.self, forKey: .onSubmit)
        onChange = try c.decodeIfPresent(PieceAction.self, forKey: .onChange)
        onKey = try c.decodeIfPresent([String: PieceAction].self, forKey: .onKey) ?? [:]
        src = try c.decodeIfPresent(String.self, forKey: .src)
        value = try c.decodeIfPresent(Double.self, forKey: .value)
        on = try c.decodeIfPresent(Bool.self, forKey: .on) ?? false
        followEnd = try c.decodeIfPresent(String.self, forKey: .followEnd)
        indicators = try c.decodeIfPresent(Bool.self, forKey: .indicators) ?? false
    }

    /// The names of the slots in this piece and everything inside it.
    var slotNames: [String] {
        (kind == "slot" ? [name ?? ""] : []) + children.flatMap(\.slotNames)
    }

    /// Pieces Aria draws itself, because only it can.
    static let builtIns: Set<String> = ["windowControls"]
}

/// One item of a piece's right-click menu, or a divider.
struct MenuItem: Decodable, Equatable, Sendable {
    var label: String?
    var icon: String?
    var action: PieceAction?
    var destructive = false
    var enabled = true
    var divider = false

    private enum CodingKeys: String, CodingKey { case label, icon, action, destructive, enabled, divider }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        label = try c.decodeIfPresent(String.self, forKey: .label)
        icon = try c.decodeIfPresent(String.self, forKey: .icon)
        action = try c.decodeIfPresent(PieceAction.self, forKey: .action)
        destructive = try c.decodeIfPresent(Bool.self, forKey: .destructive) ?? false
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        divider = try c.decodeIfPresent(Bool.self, forKey: .divider) ?? false
    }
}

enum ComponentCatalog {
    /// Style props every component gets. A file can change their defaults.
    static func containerStyle(background: String, cornerRadius: Double, paddingX: Double, paddingY: Double,
                               corners: String = "all", border: String = "none") -> [PropSpec] {
        [
            PropSpec(name: "background", label: "Background", kind: .choice(["glass", "solid", "none"]), defaultValue: .string(background)),
            PropSpec(name: "cornerRadius", label: "Corner radius", kind: .number(min: 0, max: 40, step: 1), defaultValue: .number(cornerRadius)),
            PropSpec(name: "corners", label: "Rounded corners", kind: .choice(edgeChoices(first: "all")), defaultValue: .string(corners)),
            PropSpec(name: "border", label: "Border", kind: .choice(edgeChoices(first: "none") + ["outline"]), defaultValue: .string(border)),
            PropSpec(name: "paddingX", label: "Horizontal padding", kind: .number(min: 0, max: 60, step: 1), defaultValue: .number(paddingX)),
            PropSpec(name: "paddingY", label: "Vertical padding", kind: .number(min: 0, max: 60, step: 1), defaultValue: .number(paddingY)),
        ]
    }

    private static func edgeChoices(first: String) -> [String] { [first, "left", "right", "top", "bottom"] }

    static let webView = ComponentDefinition(
        type: LayoutDocument.webViewType, title: "WebView", icon: "globe",
        summary: "The page. Drag its edges to make room for components.",
        props: [
            PropSpec(name: "fillWhenNeighbourHidden", label: "Fill gaps of closed components", kind: .toggle, defaultValue: .bool(true)),
            PropSpec(name: "cornerRadius", label: "Corner radius", kind: .number(min: 0, max: 40, step: 1), defaultValue: .number(14)),
        ],
        width: 800, height: 600)

    // MARK: Component files

    /// The shape `defineComponent` describes, after the sandbox normalises it.
    struct UserSpec: Decodable {
        struct Prop: Decodable {
            var name: String
            var kind: String
            var label: String?
            var `default`: JSONValue?
            var min: Double?
            var max: Double?
            var step: Double?
            var options: [String]?
        }
        struct Activate: Decodable {
            var kind: String
            var edge: String?
            var size: Double?
            var icon: String?
            var label: String?
            var help: String?
            var keys: String?
            var closeDelay: Double?
        }
        var name: String
        var title: String?
        var icon: String?
        var summary: String?
        var opensAs: String?
        var width: Double?
        var height: Double?
        var background: String?
        var cornerRadius: Double?
        var paddingX: Double?
        var paddingY: Double?
        var activate: [Activate]
        var props: [Prop]
        var hasRender: Bool
        var parts: [PartInfo]?
        var layout: PartLayout?
        var corners: String?
        var border: String?
        var alwaysOpen: Bool?
        var uses: [String]?
        var local: [String: AnyJSON]?
        var keys: [String: PieceAction]?
        var handles: [String: PieceAction]?
        var onOpen: PieceAction?
        var onClose: PieceAction?
        var transition: String?
        var slideFrom: String?
        var scrim: String?
        var align: String?
        var clickThrough: Bool?
    }

    static func definition(from spec: UserSpec, source: URL) throws -> ComponentDefinition {
        func fail(_ message: String) -> Error {
            NSError(domain: "Aria.Components", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
        }
        guard spec.name.range(of: "^[A-Z][A-Za-z0-9]*$", options: .regularExpression) != nil else {
            throw fail("name must start with a capital letter and use only letters and digits.")
        }
        guard spec.name != LayoutDocument.webViewType else { throw fail("WebView is built in.") }
        guard spec.hasRender || spec.layout != nil else {
            throw fail("give render, a function that returns pieces, or parts and a layout.")
        }
        guard let opensAs = OpensAs(rawValue: spec.opensAs ?? "placed") else {
            throw fail("opensAs must be \"placed\", \"overlay\" or \"none\". For a popover, give a button a popover.")
        }
        let activators: [Activator] = try spec.activate.map { item in
            if item.kind == "button" {
                throw fail("button() is a piece: render one, and give it an action or a popover.")
            }
            guard let kind = Activator.Kind(rawValue: item.kind) else { throw fail("unknown activator \"\(item.kind)\".") }
            var activator = Activator(kind: kind, size: item.size, icon: item.icon, label: item.label, help: item.help,
                                      keys: item.keys, closeDelay: item.closeDelay)
            if let edge = item.edge {
                guard let parsed = PanelEdge(rawValue: edge) else { throw fail("hover edge must be left, right, top or bottom.") }
                activator.edge = parsed
            }
            if kind == .shortcut, KeyShortcut(item.keys ?? "") == nil {
                throw fail("shortcut \"\(item.keys ?? "")\" needs modifiers and one key, like \"cmd+shift+d\".")
            }
            return activator
        }
        guard activators.filter({ $0.kind == .hover }).count <= 1 else {
            throw fail("declare at most one hover; place its area as often as you like in the editor.")
        }
        var props: [PropSpec] = try spec.props.map { prop in
            let label = prop.label ?? prop.name
            switch prop.kind {
            case "number":
                let low = prop.min ?? 0, high = prop.max ?? max(low + 1, 1000)
                return PropSpec(name: prop.name, label: label, kind: .number(min: low, max: high, step: prop.step ?? 1),
                                defaultValue: prop.default ?? .number(low))
            case "choice":
                guard let options = prop.options, !options.isEmpty else { throw fail("\(prop.name) needs options.") }
                return PropSpec(name: prop.name, label: label, kind: .choice(options),
                                defaultValue: prop.default ?? .string(options[0]))
            case "toggle":
                return PropSpec(name: prop.name, label: label, kind: .toggle, defaultValue: prop.default ?? .bool(false))
            case "text":
                return PropSpec(name: prop.name, label: label, kind: .text, defaultValue: prop.default ?? .string(""))
            default:
                throw fail("\(prop.name) has unknown kind \"\(prop.kind)\".")
            }
        }
        guard Set(props.map(\.name)).count == props.count else { throw fail("prop names must be unique.") }
        let declared = Set(props.map(\.name))
        // Components draw only what they render, unless the file asks for a background.
        props += containerStyle(background: spec.background ?? "none",
                                cornerRadius: spec.cornerRadius ?? 14,
                                paddingX: spec.paddingX ?? 0, paddingY: spec.paddingY ?? 0,
                                corners: spec.corners ?? "all", border: spec.border ?? "none")
            .filter { !declared.contains($0.name) }
        let uses = Set(spec.uses ?? [])
        if let unknown = uses.subtracting(StateSection.all).sorted().first {
            throw fail("uses lists \"\(unknown)\"; it can list \(StateSection.all.sorted().joined(separator: ", ")).")
        }
        let keys: [KeyBinding] = try (spec.keys ?? [:]).sorted { $0.key < $1.key }.map { keys, action in
            guard let shortcut = KeyShortcut(keys) else {
                throw fail("keys \"\(keys)\" needs modifiers and one key, like \"cmd+shift+d\".")
            }
            return KeyBinding(keys: keys, shortcut: shortcut, action: action)
        }
        guard let transition = ComponentTransition(rawValue: spec.transition ?? "fade") else {
            throw fail("transition must be \"fade\", \"slide\", \"scale\" or \"none\".")
        }
        var slideFrom: PanelEdge?
        if let edge = spec.slideFrom {
            guard let parsed = PanelEdge(rawValue: edge) else { throw fail("slideFrom must be left, right, top or bottom.") }
            slideFrom = parsed
        }
        var definition = ComponentDefinition(
            type: spec.name, title: spec.title ?? spec.name, icon: spec.icon ?? "square.on.square",
            summary: spec.summary ?? source.lastPathComponent, props: props, activators: activators,
            opensAs: opensAs, width: spec.width.map { CGFloat($0) }, height: spec.height.map { CGFloat($0) },
            source: source, parts: spec.parts ?? [], layout: spec.layout)
        definition.alwaysOpenOverride = spec.alwaysOpen
        definition.uses = uses
        definition.local = spec.local ?? [:]
        definition.keys = keys
        definition.handles = spec.handles ?? [:]
        definition.onOpen = spec.onOpen
        definition.onClose = spec.onClose
        definition.transition = transition
        definition.slideFrom = slideFrom
        definition.scrim = spec.scrim ?? "dim"
        definition.overlayAlign = spec.align ?? "center"
        definition.clickThrough = spec.clickThrough ?? false
        return definition
    }
}

/// A shortcut written like "cmd+shift+d".
struct KeyShortcut: Equatable, Sendable {
    var command = false, shift = false, option = false, control = false
    var key: String

    init?(_ text: String) {
        let parts = text.lowercased().split(separator: "+").map { $0.trimmingCharacters(in: .whitespaces) }
        guard var last = parts.last else { return nil }
        // "+" can't be written after a "+", so it has a name. So does "-", for symmetry.
        last = ["plus": "+", "minus": "-", "equals": "="][last] ?? last
        guard last.count == 1 else { return nil }
        key = last
        for part in parts.dropLast() {
            switch part {
            case "cmd", "command": command = true
            case "shift": shift = true
            case "opt", "option", "alt": option = true
            case "ctrl", "control": control = true
            default: return nil
            }
        }
        guard command || control || option else { return nil }
    }

    func matches(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags
        return flags.contains(.command) == command && flags.contains(.shift) == shift
            && flags.contains(.option) == option && flags.contains(.control) == control
            && event.charactersIgnoringModifiers?.lowercased() == key
    }

    var display: String {
        (control ? "⌃" : "") + (option ? "⌥" : "") + (shift ? "⇧" : "") + (command ? "⌘" : "") + key.uppercased()
    }
}
