import SwiftUI

/// The coordinate space placed components and slots report their frames in.
/// Its origin is the window's top-left corner, also inside the editor's scaled preview.
enum LayoutSpace {
    static let name = "AriaLayoutWindow"
}

struct NodeFramesKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { _, next in next }
    }
}

/// Where a slot is, and which way it lines its children up.
struct SlotFrame: Equatable {
    var rect: CGRect
    var axis: Axis
}

struct SlotFramesKey: PreferenceKey {
    static let defaultValue: [SlotAddress: SlotFrame] = [:]
    static func reduce(value: inout [SlotAddress: SlotFrame], nextValue: () -> [SlotAddress: SlotFrame]) {
        value.merge(nextValue()) { _, next in next }
    }
}

/// A piece of a placed component's layout: the component's id, and the piece's path in its layout, like "0.2".
struct PartAddress: Hashable, Sendable {
    var node: String
    var path: String

    init(node: String, path: String) {
        self.node = node
        self.path = path
    }

    init(node: String, path: [Int]) {
        self.init(node: node, path: path.map(String.init).joined(separator: "."))
    }

    var indexes: [Int] { path.isEmpty ? [] : path.split(separator: ".").compactMap { Int($0) } }
}

struct PartFramesKey: PreferenceKey {
    static let defaultValue: [PartAddress: CGRect] = [:]
    static func reduce(value: inout [PartAddress: CGRect], nextValue: () -> [PartAddress: CGRect]) {
        value.merge(nextValue()) { _, next in next }
    }
}

/// Everything the renderer needs from the browser.
struct LayoutEnvironment {
    var definition: (String) -> ComponentDefinition?
    /// Components' props, defaults filled in, by name.
    var props: [String: [String: JSONValue]]
    /// Components' rendered pieces, once their files have run, by name. Plain values,
    /// so SwiftUI redraws when a render changes.
    var trees: [String: Piece]
    var errors: [String: String]
    var isPreview = false
    /// Draws a piece only Aria can draw, like the window controls. The axis is the direction it is laid out in.
    var builtIn: (String, Axis) -> AnyView
    /// Draws a component background: "glass" or "solid", with a corner radius and which corners are rounded.
    var background: (String, CGFloat, String) -> AnyView
    /// Runs an action. Takes the component it belongs to, the id of the piece that ran it,
    /// and what happened, like the text typed or what was dropped.
    var perform: (PieceAction, String, String, AnyJSON?) -> Void = { _, _, _, _ in }
    /// Whether a button's action has its component open, so the button shows as pressed.
    var isActive: (PieceAction) -> Bool = { _ in false }
    /// Keeps a component placed in the window open while a button inside it shows a popover.
    /// Takes the button's id and the component's name, or nil when the popover closes.
    var hold: (String, String?) -> Void = { _, _ in }
    /// Whether a component is open. Closed components in slots aren't drawn.
    var isOpen: (String) -> Bool = { _ in true }
    /// Components' own state, by name.
    var local: [String: [String: AnyJSON]] = [:]
    /// Sets one key of a component's own state.
    var setLocal: (String, String, AnyJSON?) -> Void = { _, _, _ in }
    /// The image for a favicon token from the state, like a tab's `favicon`.
    var favicon: (String) -> NSImage? = { _ in nil }
    /// Address suggestions for what's typed in a text field.
    var suggest: (String) -> AnyJSON = { _ in .null }
    var accent: Color = .accentColor
}

extension PanelEdge {
    var swiftUIEdge: Edge {
        switch self { case .left: .leading; case .right: .trailing; case .top: .top; case .bottom: .bottom }
    }
}

/// How a component appears and disappears.
enum ComponentMotion {
    static func transition(_ definition: ComponentDefinition?, edge: PanelEdge) -> AnyTransition {
        switch definition?.transition ?? .fade {
        case .none: .identity
        case .fade: .opacity
        case .scale: .opacity.combined(with: .scale(scale: 0.96))
        case .slide: .move(edge: edge.swiftUIEdge)
        }
    }

    /// The edge a placed component slides in from: the one its file names, its hover edge,
    /// or the window edge it sits nearest.
    static func edge(_ definition: ComponentDefinition?, rect: CGRect, in size: CGSize) -> PanelEdge {
        if let edge = definition?.slideFrom ?? definition?.activator(.hover)?.edge { return edge }
        let distances: [(PanelEdge, CGFloat)] = [(.left, rect.minX), (.right, size.width - rect.maxX),
                                                 (.top, rect.minY), (.bottom, size.height - rect.maxY)]
        return distances.min { $0.1 < $1.1 }?.0 ?? .left
    }
}

/// Which corners of a component are rounded: "all", or the two on one side.
struct ComponentShape: Shape {
    var radius: CGFloat
    var corners: String

    func path(in rect: CGRect) -> Path {
        let r = radius
        let radii: RectangleCornerRadii = switch corners {
        case "left": .init(topLeading: r, bottomLeading: r, bottomTrailing: 0, topTrailing: 0)
        case "right": .init(topLeading: 0, bottomLeading: 0, bottomTrailing: r, topTrailing: r)
        case "top": .init(topLeading: r, bottomLeading: 0, bottomTrailing: 0, topTrailing: r)
        case "bottom": .init(topLeading: 0, bottomLeading: r, bottomTrailing: r, topTrailing: 0)
        default: .init(topLeading: r, bottomLeading: r, bottomTrailing: r, topTrailing: r)
        }
        return UnevenRoundedRectangle(cornerRadii: radii, style: .continuous).path(in: rect)
    }
}

/// Colours a component file names: "primary", "secondary", "accent", "red" and so on,
/// or "#RRGGBB". Add "/0.2" for opacity, like "primary/0.08".
enum PieceColor {
    static func parse(_ text: String?, accent: Color) -> Color? {
        guard let text, !text.isEmpty else { return nil }
        let parts = text.split(separator: "/", maxSplits: 1).map(String.init)
        guard let first = parts.first else { return nil }
        let opacity = parts.count > 1 ? Double(parts[1]) : nil
        let name = first.trimmingCharacters(in: .whitespaces).lowercased()
        let base: Color?
        switch name {
        case "primary": base = .primary
        case "secondary": base = .secondary
        case "tertiary": base = Color.secondary.opacity(0.6)
        case "accent": base = accent
        case "clear": base = .clear
        case "red": base = .red
        case "orange": base = .orange
        case "yellow": base = .yellow
        case "green": base = .green
        case "blue": base = .blue
        case "purple": base = .purple
        case "pink": base = .pink
        case "gray", "grey": base = .gray
        case "white": base = .white
        case "black": base = .black
        default: base = hex(name)
        }
        guard let base else { return nil }
        return opacity.map { base.opacity($0) } ?? base
    }

    private static func hex(_ text: String) -> Color? {
        var value = text
        if value.hasPrefix("#") { value.removeFirst() }
        guard value.count == 6 || value.count == 8, let number = UInt64(value, radix: 16) else { return nil }
        let hasAlpha = value.count == 8
        let shift: UInt64 = hasAlpha ? 8 : 0
        return Color(.sRGB,
                     red: Double((number >> (16 + shift)) & 0xFF) / 255,
                     green: Double((number >> (8 + shift)) & 0xFF) / 255,
                     blue: Double((number >> shift) & 0xFF) / 255,
                     opacity: hasAlpha ? Double(number & 0xFF) / 255 : 1)
    }
}

/// What is placed in the window, apart from the WebView: open components and,
/// inside their slots, the components placed there. Hover areas are invisible.
struct LayoutWindowView: View {
    let document: LayoutDocument
    let frames: WindowFrames
    let size: CGSize
    let environment: LayoutEnvironment
    /// Components placed in the window that are closed.
    var hidden: Set<String> = []
    var occludesWebView = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear.allowsHitTesting(false)
            ForEach(document.root.filter {
                $0.type != LayoutDocument.webViewType && $0.role == .view && !hidden.contains($0.id)
            }) { node in
                if let rect = frames.frames[node.id], rect.width > 0, rect.height > 0 {
                    let definition = environment.definition(node.type)
                    ComponentView(node: node, host: node.type, axis: rect.height > rect.width ? .vertical : .horizontal,
                                  fills: true, environment: environment,
                                  occludes: occludesWebView && definition?.clickThrough != true)
                        .frame(width: rect.width, height: rect.height)
                        .allowsHitTesting(definition?.clickThrough != true)
                        .position(x: rect.midX, y: rect.midY)
                        .transition(ComponentMotion.transition(
                            definition, edge: ComponentMotion.edge(definition, rect: rect, in: size)))
                }
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .coordinateSpace(name: LayoutSpace.name)
        .animation(environment.isPreview ? nil : .easeInOut(duration: 0.16), value: hidden)
    }
}

struct OcclusionModifier: ViewModifier {
    let enabled: Bool
    func body(content: Content) -> some View {
        if enabled { content.webViewOcclusionRegion() } else { content }
    }
}

/// A placed component: what its file renders, with the background it asks for.
struct ComponentView: View {
    let node: LayoutNode
    /// The component placed in the window that this one sits in, or this one.
    let host: String
    let axis: Axis
    /// Fill the frame the window gives it, rather than taking its own size in a slot.
    let fills: Bool
    let environment: LayoutEnvironment
    /// Keep the page from taking clicks under it. A component that draws no background
    /// only covers what it draws, so the page stays usable around it.
    var occludes = false

    var body: some View {
        let props = environment.props[node.type] ?? [:]
        let transparent = (props["background"]?.string ?? "none") == "none" && (props["border"]?.string ?? "none") == "none"
        let style = props["background"]?.string ?? "none"
        let radius = CGFloat(props["cornerRadius"]?.number ?? 14)
        let corners = props["corners"]?.string ?? "all"
        let border = props["border"]?.string ?? "none"
        let shape = ComponentShape(radius: style == "none" && border != "outline" ? 0 : radius, corners: corners)
        Group {
            if let tree = environment.trees[node.type] {
                PieceView(piece: tree, path: "0", node: node, host: host, axis: axis, environment: environment)
            } else if environment.isPreview {
                let error = environment.errors[node.type]
                Label(error ?? (environment.definition(node.type) == nil ? "Missing \(node.type)" : "Rendering…"),
                      systemImage: error == nil ? "hourglass" : "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(error == nil ? Color.secondary : Color.orange)
                    .padding(6)
            }
        }
        .padding(.horizontal, CGFloat(props["paddingX"]?.number ?? 0))
        .padding(.vertical, CGFloat(props["paddingY"]?.number ?? 0))
        .modifier(OcclusionModifier(enabled: occludes && transparent))
        .frame(maxWidth: fills ? .infinity : nil, maxHeight: fills ? .infinity : nil, alignment: .topLeading)
        .background {
            if style != "none" { environment.background(style, radius, corners).allowsHitTesting(false) }
        }
        .clipShape(shape)
        .overlay { ComponentBorder(edge: border, shape: shape).allowsHitTesting(false) }
        .modifier(SolidIf(enabled: !transparent))
        .modifier(OcclusionModifier(enabled: occludes && !transparent))
        .background {
            GeometryReader { proxy in
                Color.clear.preference(key: NodeFramesKey.self, value: [node.id: proxy.frame(in: .named(LayoutSpace.name))])
            }
        }
    }
}

/// Takes clicks across the whole frame, not only where something is drawn.
private struct SolidIf: ViewModifier {
    let enabled: Bool
    func body(content: Content) -> some View {
        if enabled { content.contentShape(Rectangle()) } else { content }
    }
}

/// A hairline along one edge of a component, or around it.
private struct ComponentBorder: View {
    let edge: String
    let shape: ComponentShape

    var body: some View {
        switch edge {
        case "outline":
            shape.stroke(Color.primary.opacity(0.14), lineWidth: 1)
        case "left", "right", "top", "bottom":
            let vertical = edge == "left" || edge == "right"
            let alignment: Alignment = switch edge { case "left": .leading; case "right": .trailing; case "top": .top; default: .bottom }
            Rectangle().fill(Color.white.opacity(0.18))
                .frame(width: vertical ? 1 : nil, height: vertical ? nil : 1)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
        default:
            EmptyView()
        }
    }
}

private struct GroupHoveredKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Whether the pointer is over the nearest piece marked `hoverGroup`.
    var ariaGroupHovered: Bool {
        get { self[GroupHoveredKey.self] }
        set { self[GroupHoveredKey.self] = newValue }
    }
}

/// One piece and everything inside it.
struct PieceView: View {
    let piece: Piece
    /// Its position in the tree, which identifies its buttons.
    let path: String
    /// The placed component this piece belongs to.
    let node: LayoutNode
    let host: String
    /// The direction its parent lays it out in.
    let axis: Axis
    let environment: LayoutEnvironment

    var body: some View {
        content
            .padding(.horizontal, CGFloat(piece.padding?.first ?? 0))
            .padding(.vertical, CGFloat(piece.padding?.last ?? 0))
            .frame(width: piece.width.map { CGFloat($0) }, height: piece.height.map { CGFloat($0) })
            .frame(minWidth: piece.minWidth.map { CGFloat($0) }, maxWidth: piece.maxWidth.map { CGFloat($0) },
                   minHeight: piece.minHeight.map { CGFloat($0) }, maxHeight: piece.maxHeight.map { CGFloat($0) })
            .frame(maxWidth: piece.grow && axis == .horizontal ? .infinity : nil,
                   maxHeight: piece.grow && axis == .vertical ? .infinity : nil)
            .modifier(PieceDecoration(piece: piece, id: "\(node.id)/\(path)", component: node.type, environment: environment))
            .background {
                // The editor finds the pieces of a component's layout by these frames.
                if environment.isPreview, let at = piece.at {
                    GeometryReader { proxy in
                        Color.clear.preference(key: PartFramesKey.self, value: [
                            PartAddress(node: node.id, path: at): proxy.frame(in: .named(LayoutSpace.name)),
                        ])
                    }
                }
            }
    }

    private var color: Color? { PieceColor.parse(piece.color, accent: environment.accent) }

    @ViewBuilder private var content: some View {
        switch piece.kind {
        case "row", "column":
            let vertical = piece.kind == "column"
            stack(vertical: vertical) { children(vertical: vertical) }
        case "layers":
            ZStack(alignment: Alignment(horizontal: horizontalAlignment, vertical: verticalAlignment)) {
                ForEach(Array(piece.children.enumerated()), id: \.offset) { index, child in
                    PieceView(piece: child, path: "\(path).\(index)", node: node, host: host, axis: axis, environment: environment)
                }
            }
        case "scroll":
            let vertical = piece.direction != "row"
            ScrollViewReader { proxy in
                let end = "\(node.id)/\(path)/end"
                ScrollView(vertical ? .vertical : .horizontal) {
                    if vertical {
                        LazyVStack(alignment: horizontalAlignment, spacing: CGFloat(piece.spacing ?? 8)) {
                            children(vertical: true)
                            if piece.followEnd != nil { Color.clear.frame(height: 0).id(end) }
                        }
                    } else {
                        LazyHStack(alignment: verticalAlignment, spacing: CGFloat(piece.spacing ?? 8)) {
                            children(vertical: false)
                            if piece.followEnd != nil { Color.clear.frame(width: 0).id(end) }
                        }
                    }
                }
                .scrollIndicators(piece.indicators ? .automatic : .hidden)
                .onChange(of: piece.followEnd, initial: true) { _, value in
                    if value != nil { proxy.scrollTo(end, anchor: vertical ? .bottom : .trailing) }
                }
            }
        case "slot":
            slot
        case "part":
            // A named part: what its render function returned, filling the width down a column.
            ForEach(Array(piece.children.enumerated()), id: \.offset) { index, child in
                PieceView(piece: child, path: "\(path).\(index)", node: node, host: host, axis: axis, environment: environment)
                    .frame(maxWidth: axis == .vertical ? .infinity : nil, alignment: .leading)
            }
        case "spacer":
            Spacer(minLength: 0)
        case "divider":
            Divider()
        case "text":
            Text(piece.text ?? "")
                .font(font)
                .monospacedDigit()
                .foregroundStyle(color ?? (piece.style == "secondary" || piece.style == "caption" ? .secondary : .primary))
                .lineLimit(piece.lineLimit.map { Int(min(10000, max(1, $0))) } ?? (piece.style == "title" ? 1 : nil))
                .truncationMode(piece.truncate == "middle" ? .middle : piece.truncate == "head" ? .head : .tail)
        case "icon":
            Image(systemName: piece.icon ?? "questionmark")
                .font(.system(size: CGFloat(piece.size ?? 13), weight: Self.weight(piece.weight) ?? .semibold))
                .foregroundStyle(color ?? .primary)
        case "favicon":
            let size = CGFloat(piece.size ?? 16)
            if let image = environment.favicon(piece.src ?? "") {
                Image(nsImage: image).resizable().interpolation(.high).scaledToFit()
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: max(2, size / 5), style: .continuous))
            } else {
                Image(systemName: piece.icon ?? "globe")
                    .font(.system(size: size * 0.8, weight: .medium))
                    .foregroundStyle(color ?? .secondary)
                    .frame(width: size, height: size)
            }
        case "progress":
            Group {
                if let value = piece.value { ProgressView(value: min(max(value, 0), 1)) } else { ProgressView() }
            }
            .progressViewStyle(.linear)
            .controlSize(.small)
            .tint(color ?? environment.accent)
        case "switch":
            Toggle(isOn: Binding(get: { piece.on }, set: { value in
                if let action = piece.action { environment.perform(action, node.type, "\(node.id)/\(path)", .bool(value)) }
            })) {
                if let label = piece.label { Text(label).font(.system(size: CGFloat(piece.size ?? 12))) }
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
            .disabled(!piece.enabled)
        case "textField":
            PieceTextField(piece: piece, id: "\(node.id)/\(path)", component: node.type, environment: environment)
        case "dragRegion":
            WindowDragHandle().frame(maxWidth: .infinity, maxHeight: .infinity)
        case "button":
            PieceButton(piece: piece, path: path, node: node, host: host, environment: environment)
        default:
            if Piece.builtIns.contains(piece.kind) {
                environment.builtIn(piece.kind, axis)
            } else if environment.isPreview {
                Label("Unknown piece \(piece.kind)", systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
            }
        }
    }

    private func children(vertical: Bool) -> some View {
        ForEach(Array(piece.children.enumerated()), id: \.offset) { index, child in
            let view = PieceView(piece: child, path: "\(path).\(index)", node: node, host: host,
                                 axis: vertical ? .vertical : .horizontal, environment: environment)
            // Down a column, pieces take the full width unless they are spacers.
            if vertical && child.kind != "spacer" {
                view.frame(maxWidth: .infinity, alignment: Alignment(horizontal: horizontalAlignment, vertical: .center))
            } else {
                view
            }
        }
    }

    private func stack<Content: View>(vertical: Bool, @ViewBuilder content: () -> Content) -> some View {
        let spacing = CGFloat(piece.spacing ?? 8)
        let layout = vertical
            ? AnyLayout(VStackLayout(alignment: horizontalAlignment, spacing: spacing))
            : AnyLayout(HStackLayout(alignment: verticalAlignment, spacing: spacing))
        return layout { content() }
    }

    /// The components placed in this slot that are open, lined up in a row or column.
    private var slot: some View {
        let name = piece.name ?? ""
        let all = node.slots[name] ?? []
        let children = environment.isPreview ? all : all.filter { environment.isOpen($0.type) }
        let vertical = piece.direction == "column"
        let empty = all.isEmpty && environment.isPreview
        return stack(vertical: vertical) {
            ForEach(children) { child in
                let definition = environment.definition(child.type)
                ComponentView(node: child, host: host, axis: vertical ? .vertical : .horizontal, fills: false,
                              environment: environment)
                    .transition(ComponentMotion.transition(definition, edge: definition?.slideFrom ?? (vertical ? .bottom : .right)))
            }
        }
        .animation(environment.isPreview ? nil : .easeInOut(duration: 0.16), value: children.map(\.id))
        .frame(minWidth: empty ? 60 : nil, minHeight: empty ? 28 : nil)
        .overlay {
            if empty {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.secondary.opacity(0.6), style: .init(lineWidth: 1, dash: [4]))
                    .overlay { Text(name).font(.caption2).foregroundStyle(.secondary).lineLimit(1) }
            }
        }
        .background {
            GeometryReader { proxy in
                Color.clear.preference(key: SlotFramesKey.self, value: [
                    SlotAddress(owner: node.id, name: name):
                        SlotFrame(rect: proxy.frame(in: .named(LayoutSpace.name)), axis: vertical ? .vertical : .horizontal),
                ])
            }
        }
    }

    private var horizontalAlignment: HorizontalAlignment {
        switch piece.align { case "center": .center; case "trailing": .trailing; default: .leading }
    }

    private var verticalAlignment: VerticalAlignment {
        switch piece.align { case "top": .top; case "bottom": .bottom; default: .center }
    }

    static func weight(_ name: String?) -> Font.Weight? {
        switch name {
        case "light": .light
        case "regular": .regular
        case "medium": .medium
        case "semibold": .semibold
        case "bold": .bold
        case "heavy": .heavy
        default: nil
        }
    }

    private var font: Font {
        if let size = piece.size {
            return .system(size: CGFloat(size), weight: Self.weight(piece.weight) ?? .regular,
                           design: piece.monospaced ? .monospaced : .default)
        }
        let base: Font = switch piece.style {
        case "title": .headline
        case "caption": .caption
        case "secondary": .callout
        default: .body
        }
        let weighted = base.weight(Self.weight(piece.weight) ?? (piece.style == "title" ? .semibold : .regular))
        return piece.monospaced ? weighted.monospacedDigit() : weighted
    }
}

/// The options any piece takes: colours, borders, a tap action, a menu, dragging and dropping, hover.
private struct PieceDecoration: ViewModifier {
    let piece: Piece
    let id: String
    let component: String
    let environment: LayoutEnvironment

    @Environment(\.ariaGroupHovered) private var groupHovered
    @State private var isHovered = false
    @State private var isTargeted = false

    private var tracksHover: Bool { piece.hoverGroup || piece.hoverBackground != nil }
    /// Buttons, switches and text fields run their own actions.
    private var tappable: Bool { piece.action != nil && !["button", "switch", "textField"].contains(piece.kind) }

    func body(content: Content) -> some View {
        let radius = CGFloat(piece.cornerRadius ?? 7)
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let fill = (isHovered ? PieceColor.parse(piece.hoverBackground, accent: environment.accent) : nil)
            ?? PieceColor.parse(piece.background, accent: environment.accent)
        content
            .background {
                if piece.background == "glass" {
                    environment.background("glass", radius, "all").allowsHitTesting(false)
                } else if let fill {
                    shape.fill(fill)
                }
            }
            .overlay {
                if let border = PieceColor.parse(piece.border, accent: environment.accent) {
                    shape.strokeBorder(border, lineWidth: 1).allowsHitTesting(false)
                }
                if isTargeted {
                    shape.fill(environment.accent.opacity(0.14))
                        .overlay { shape.strokeBorder(environment.accent.opacity(0.8), lineWidth: 1) }
                        .allowsHitTesting(false)
                }
            }
            .modifier(ShapeIf(enabled: tappable || piece.drag != nil || piece.onDrop != nil || !piece.menu.isEmpty || tracksHover, shape: shape))
            .onTapGestureIf(tappable && !environment.isPreview) {
                if let action = piece.action { environment.perform(action, component, id, nil) }
            }
            .modifier(HelpIf(text: piece.kind == "button" ? nil : piece.help))
            .modifier(MenuIf(items: piece.menu, run: { action in environment.perform(action, component, id, nil) }))
            .modifier(DragIf(payload: environment.isPreview ? nil : piece.drag))
            .modifier(DropIf(enabled: piece.onDrop != nil && !environment.isPreview, isTargeted: $isTargeted) { text in
                if let action = piece.onDrop { environment.perform(action, component, id, .string(text)) }
            })
            .modifier(HoverIf(enabled: tracksHover, isHovered: $isHovered))
            .environment(\.ariaGroupHovered, piece.hoverGroup ? isHovered : groupHovered)
            .opacity(piece.opacity ?? 1)
            .opacity(piece.showOnHover && !groupHovered && !environment.isPreview ? 0 : 1)
            .allowsHitTesting(!(piece.showOnHover && !groupHovered && !environment.isPreview))
            .cursor(tappable ? .pointingHand : .arrow)
    }
}

private struct ShapeIf: ViewModifier {
    let enabled: Bool
    let shape: RoundedRectangle
    func body(content: Content) -> some View {
        if enabled { content.contentShape(shape) } else { content }
    }
}

private struct HelpIf: ViewModifier {
    let text: String?
    func body(content: Content) -> some View {
        if let text { content.help(text) } else { content }
    }
}

private struct HoverIf: ViewModifier {
    let enabled: Bool
    @Binding var isHovered: Bool
    func body(content: Content) -> some View {
        if enabled { content.onHover { isHovered = $0 } } else { content }
    }
}

private struct MenuIf: ViewModifier {
    let items: [MenuItem]
    let run: (PieceAction) -> Void
    func body(content: Content) -> some View {
        if items.isEmpty {
            content
        } else {
            content.contextMenu {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    if item.divider {
                        Divider()
                    } else {
                        Button(role: item.destructive ? .destructive : nil) {
                            if let action = item.action { run(action) }
                        } label: {
                            if let icon = item.icon { Label(item.label ?? "", systemImage: icon) } else { Text(item.label ?? "") }
                        }
                        .disabled(!item.enabled)
                    }
                }
            }
        }
    }
}

private struct DragIf: ViewModifier {
    let payload: String?
    func body(content: Content) -> some View {
        if let payload { content.onDrag { NSItemProvider(object: payload as NSString) } } else { content }
    }
}

/// Accepts dropped text or links, and hands what was dropped to the piece's function.
private struct DropIf: ViewModifier {
    let enabled: Bool
    @Binding var isTargeted: Bool
    let received: (String) -> Void

    func body(content: Content) -> some View {
        if enabled {
            content.onDrop(of: [.plainText, .url], isTargeted: $isTargeted) { providers in
                guard let provider = providers.first else { return false }
                if provider.canLoadObject(ofClass: NSString.self) {
                    _ = provider.loadObject(ofClass: NSString.self) { value, _ in
                        guard let text = value as? String else { return }
                        DispatchQueue.main.async { received(text) }
                    }
                } else {
                    _ = provider.loadObject(ofClass: NSURL.self) { value, _ in
                        guard let url = value as? URL else { return }
                        DispatchQueue.main.async { received(url.absoluteString) }
                    }
                }
                return true
            }
        } else {
            content
        }
    }
}

private extension View {
    @ViewBuilder func onTapGestureIf(_ enabled: Bool, perform: @escaping () -> Void) -> some View {
        if enabled { onTapGesture(perform: perform) } else { self }
    }
}

/// A text field bound to a key of its component's own state. It can keep address
/// suggestions for what's typed in another key, and run actions on keys.
struct PieceTextField: View {
    let piece: Piece
    let id: String
    let component: String
    let environment: LayoutEnvironment

    @FocusState private var isFocused: Bool
    @State private var monitor: Any?
    /// The latest piece and environment, for the key monitor, which outlives a render.
    @State private var latest = Latest()

    final class Latest {
        weak var window: NSWindow?
        var piece: Piece?
        var environment: LayoutEnvironment?
    }

    private var key: String { piece.bind ?? "text" }

    private var text: Binding<String> {
        Binding(get: { environment.local[component]?[key]?.string ?? "" }, set: { change($0) })
    }

    var body: some View {
        let _ = latest.piece = piece
        let _ = latest.environment = environment
        TextField(piece.placeholder ?? "", text: text)
            .textFieldStyle(.plain)
            .font(.system(size: CGFloat(piece.size ?? 13), weight: PieceView.weight(piece.weight) ?? .regular))
            .foregroundStyle(PieceColor.parse(piece.color, accent: environment.accent) ?? .primary)
            .focused($isFocused)
            .background(WindowAccessor { latest.window = $0 })
            .disabled(!piece.enabled || environment.isPreview)
            .onSubmit {
                if let action = piece.onSubmit { environment.perform(action, component, id, .string(text.wrappedValue)) }
            }
            .onChange(of: text.wrappedValue) { _, value in
                // However the text changed, typed or set by the component, suggestions follow it.
                if let suggest = piece.suggest, environment.local[component]?[suggest]?["query"]?.string != value {
                    environment.setLocal(component, suggest, environment.suggest(value))
                }
            }
            .onAppear {
                if let suggest = piece.suggest, environment.local[component]?[suggest]?["query"]?.string != text.wrappedValue {
                    environment.setLocal(component, suggest, environment.suggest(text.wrappedValue))
                }
                guard piece.autofocus, !environment.isPreview else { return }
                DispatchQueue.main.async {
                    isFocused = true
                    if piece.selectAll {
                        DispatchQueue.main.async { (latest.window?.firstResponder as? NSTextView)?.selectAll(nil) }
                    }
                }
            }
            .onChange(of: isFocused) { _, focused in focused ? installMonitor() : removeMonitor() }
            .onDisappear(perform: removeMonitor)
    }

    private func change(_ value: String) {
        environment.setLocal(component, key, .string(value))
        if let suggest = piece.suggest { environment.setLocal(component, suggest, environment.suggest(value)) }
        if let action = piece.onChange { environment.perform(action, component, id, .string(value)) }
    }

    /// Arrow keys, Tab and Escape, which the field would otherwise keep for itself.
    private func installMonitor() {
        guard monitor == nil else { return }
        let latest = latest
        let component = component, id = id
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard latest.window?.isKeyWindow == true, let piece = latest.piece, let environment = latest.environment,
                  event.modifierFlags.intersection([.command, .option, .control]).isEmpty else { return event }
            let shift = event.modifierFlags.contains(.shift)
            let name: String? = switch event.keyCode {
            case 126: "up"
            case 125: "down"
            case 53: "escape"
            case 48: shift ? "shift+tab" : "tab"
            case 36, 76: shift ? "shift+enter" : nil
            default: nil
            }
            guard let name, let action = piece.onKey[name] else { return event }
            let value = environment.local[component]?[piece.bind ?? "text"]?.string ?? ""
            environment.perform(action, component, id, .string(value))
            return nil
        }
    }

    private func removeMonitor() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}

/// A button from a component file. Clicking runs its action and shows its popover.
struct PieceButton: View {
    let piece: Piece
    let path: String
    let node: LayoutNode
    let host: String
    let environment: LayoutEnvironment

    @State private var isHovered = false
    @State private var isPopoverShown = false

    private var id: String { "\(node.id)/\(path)" }

    var body: some View {
        let active = piece.active || isPopoverShown || piece.action.map(environment.isActive) == true
        let color = PieceColor.parse(piece.color, accent: environment.accent)
        Button {
            if let action = piece.action { environment.perform(action, node.type, id, nil) }
            if !piece.popover.isEmpty { isPopoverShown.toggle() }
        } label: {
            HStack(spacing: 6) {
                if let icon = piece.icon {
                    Image(systemName: icon).font(.system(size: CGFloat(piece.size ?? 12), weight: .semibold))
                }
                if let label = piece.label {
                    Text(label).font(.system(size: 13, weight: PieceView.weight(piece.weight) ?? .regular)).lineLimit(1)
                }
                ForEach(Array(piece.children.enumerated()), id: \.offset) { index, child in
                    PieceView(piece: child, path: "\(path).\(index)", node: node, host: host, axis: .horizontal,
                              environment: environment)
                }
            }
            .padding(.horizontal, piece.label == nil && piece.children.isEmpty ? 0 : 8)
            .frame(minWidth: 28, minHeight: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(color ?? .primary)
        .background {
            if piece.background == nil {
                RoundedRectangle(cornerRadius: CGFloat(piece.cornerRadius ?? 7), style: .continuous)
                    .fill(active || isHovered ? Color.primary.opacity(active ? 0.1 : 0.06) : Color.clear)
            }
        }
        .overlay(alignment: .topTrailing) {
            if let badge = piece.badge, badge > 0 {
                Text(badge.formatted())
                    .font(.system(size: 9, weight: .bold)).monospacedDigit()
                    .frame(minWidth: 14, minHeight: 14)
                    .background { Capsule().fill(environment.accent.opacity(0.28)) }
                    .offset(x: 5, y: -5)
            }
        }
        .disabled(!piece.enabled)
        .opacity(piece.enabled ? 1 : 0.4)
        .onHover { isHovered = $0 }
        .cursor(.pointingHand)
        .help(piece.help ?? piece.label ?? "")
        .accessibilityLabel(piece.help ?? piece.label ?? piece.icon ?? "Button")
        .popover(isPresented: $isPopoverShown) {
            if let content = piece.popover.first {
                PieceView(piece: content, path: "\(path).popover", node: node, host: host, axis: .vertical,
                          environment: environment)
                    .padding(8)
            }
        }
        .onChange(of: isPopoverShown) { _, shown in environment.hold(id, shown ? host : nil) }
        .onDisappear { if isPopoverShown { environment.hold(id, nil) } }
    }
}
