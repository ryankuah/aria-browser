import SwiftUI

/// The full-window layout editor. Component files decide what each component
/// looks like and what opens it. The editor places the WebView, components and
/// hover areas in the window, and components into the slots other components render.
struct LayoutEditor: View {
    @ObservedObject var store: LayoutStore
    let windowSize: CGSize
    /// The part of the window the layout can use.
    let contentBounds: CGRect
    let tab: BrowserTab?
    /// The browser state component files render with.
    let state: RuntimeState
    let environment: LayoutEnvironment
    let windowBackground: AnyView
    let onClose: () -> Void

    /// Renders component files with the props being edited.
    @StateObject private var runtime = ComponentRuntime()
    @State private var draft: LayoutDocument
    @State private var original: LayoutDocument
    @State private var selection: String?
    /// The component shown in the inspector. Follows the selection.
    @State private var component: String?
    @State private var interaction: Interaction?
    @State private var target: DropTarget?
    @State private var pointer: CGPoint?
    @State private var regions: [EditorRegion: CGRect] = [:]
    /// Frames of components in slots, which SwiftUI lays out.
    @State private var nodeFrames: [String: CGRect] = [:]
    @State private var slotFrames: [SlotAddress: SlotFrame] = [:]
    /// Rearranged layouts of components' parts, by component name. Saving writes them into the files.
    @State private var layouts: [String: PartLayout] = [:]
    /// The placed component whose parts are being edited.
    @State private var focus: String?
    /// The selected piece of the focused component's layout, by its path.
    @State private var part: [Int]?
    @State private var partFrames: [PartAddress: CGRect] = [:]
    @State private var snapshot: NSImage?
    @State private var saveError: String?
    @State private var lastTap: (id: String?, time: Date)?

    init(store: LayoutStore, windowSize: CGSize, contentBounds: CGRect, tab: BrowserTab?, state: RuntimeState,
         environment: LayoutEnvironment, windowBackground: AnyView, onClose: @escaping () -> Void) {
        self.store = store
        self.windowSize = windowSize
        self.contentBounds = contentBounds
        self.tab = tab
        self.state = state
        self.environment = environment
        self.windowBackground = windowBackground
        self.onClose = onClose
        _draft = State(initialValue: store.document)
        _original = State(initialValue: store.document)
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            HStack(spacing: 0) {
                layersColumn.frame(width: 230)
                Divider()
                canvasArea
                Divider()
                inspector.frame(width: 300)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .coordinateSpace(name: EditorRegion.space)
        .onPreferenceChange(EditorRegionFrames.self) { regions = $0 }
        .simultaneousGesture(editorGesture)
        .overlay(alignment: .topLeading) { dragChip }
        .task(id: renderInput) { [input = renderInput] in await runtime.update(input) }
        .task {
            if let tab, BrowserInternalPage.page(for: tab.url) == nil {
                snapshot = try? await tab.webView.takeSnapshot(configuration: nil)
            }
        }
    }

    private var renderInput: RenderInput {
        RenderInput(sources: store.sources,
                    props: Dictionary(uniqueKeysWithValues: store.userComponents.map { ($0.type, $0.resolved(draft.props(of: $0.type))) }),
                    state: state, layouts: layouts)
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack(spacing: 10) {
            Text("Customize Layout").font(.title3.bold())
            Spacer()
            if draft.webView == nil {
                Label("No WebView: pages won’t be visible", systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
            }
            Menu {
                Menu("Install Add-ons") {
                    ForEach(store.bundledFiles, id: \.self) { file in
                        Button(String(file.dropLast(3))) { installComponents([file]) }
                            .disabled(store.userComponents.contains { $0.source?.lastPathComponent == file })
                    }
                    Divider()
                    Button("Install All") { installComponents() }
                }
                Button("Use Standard Layout") {
                    do {
                        draft = try store.standardLayout()
                        layouts.removeAll()
                        select(nil)
                    } catch { saveError = error.localizedDescription }
                }
                Divider()
                Button("Start From Empty") {
                    draft.root = []
                    select(nil)
                }
                Divider()
                Button("Open Components Folder") { NSWorkspace.shared.open(store.componentsURL) }
                Button("Reload Components") { store.reloadComponents() }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .accessibilityLabel("Layout options")
            .fixedSize()
            Button("Cancel", action: onClose)
            Button("Save", action: save).keyboardShortcut("s").buttonStyle(.borderedProminent)
            // Esc clears the selection first, then closes the editor.
            Button("") {
                if part != nil { part = nil }
                else if let focus { select(focus) }
                else if selection != nil || component != nil { select(nil) }
                else { onClose() }
            }
                .keyboardShortcut(.cancelAction).frame(width: 0).opacity(0)
        }
        .padding(.horizontal, 18).padding(.vertical, 10)
        .background { WindowDragHandle() }
    }

    // MARK: Library and layers

    /// What can be placed, above the canvas: components, or the parts of the one being edited.
    @ViewBuilder private var componentStrip: some View {
        if let focus, let node = draft.node(focus) {
            partStrip(node)
        } else {
            componentChips
        }
    }

    private func partStrip(_ node: LayoutNode) -> some View {
        let definition = store.definition(for: node.type)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Label("Editing \(definition?.title ?? node.type)’s parts", systemImage: definition?.icon ?? "square")
                    .font(.callout.weight(.semibold))
                Text("Saving writes the arrangement to \(definition?.source?.lastPathComponent ?? "its file").")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                Button("Done") { select(node.id) }.controlSize(.small)
            }
            FlowLayout(spacing: 6) {
                ForEach(partPalette(node.type), id: \.self) { item in
                    Label(partTitle(item, of: node.type), systemImage: partIcon(item, of: node.type))
                        .font(.callout)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Color.secondary.opacity(0.12), in: Capsule())
                        .overlay { Capsule().strokeBorder(Color.secondary.opacity(0.2)) }
                        .fixedSize()
                        .help(item.kind == .part ? "Not in the layout. Drag it in." : "Drag it into a row or column.")
                        .editorRegion(.part(item))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var componentChips: some View {
        FlowLayout(spacing: 6) {
            chip(PlaceItem(type: LayoutDocument.webViewType, role: .view), title: "WebView", icon: "globe",
                 help: ComponentCatalog.webView.summary,
                 disabled: draft.webView != nil ? "The window already has a WebView." : nil)
            ForEach(store.userComponents) { definition in
                if definition.placeableRoles.contains(.view) {
                    chip(PlaceItem(type: definition.type, role: .view), title: definition.title, icon: definition.icon,
                         help: definition.summary, disabled: nil)
                }
                if definition.placeableRoles.contains(.hover) {
                    chip(PlaceItem(type: definition.type, role: .hover), title: "\(definition.title) hover area",
                         icon: "cursorarrow.rays",
                         help: "An invisible area that opens \(definition.title) while the pointer is over it.", disabled: nil)
                }
                if definition.placeableRoles.isEmpty {
                    Label("\(definition.title): \(openingSummary(definition))", systemImage: definition.icon)
                        .font(.callout).foregroundStyle(.secondary)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .fixedSize()
                        .help(definition.summary)
                        .editorRegion(.disabled(PlaceItem(type: definition.type, role: .view)))
                }
            }
            if !store.componentErrors.isEmpty {
                Menu {
                    ForEach(store.componentErrors.sorted(by: { $0.key < $1.key }), id: \.key) { file, error in
                        Button("\(file): \(error)") { NSWorkspace.shared.open(store.componentsURL.appendingPathComponent(file)) }
                    }
                } label: {
                    Label("\(store.componentErrors.count) not loaded", systemImage: "exclamationmark.triangle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .foregroundStyle(.orange)
                .help("Component files with errors. Choose one to open it.")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func chip(_ item: PlaceItem, title: String, icon: String, help: String, disabled: String?) -> some View {
        Label(title, systemImage: icon)
            .font(.callout)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Color.secondary.opacity(component == item.type && item.role == .view ? 0.25 : 0.12), in: Capsule())
            .overlay { Capsule().strokeBorder(Color.secondary.opacity(0.2)) }
            .fixedSize()
            .opacity(disabled == nil ? 1 : 0.4)
            .help(disabled ?? help)
            .editorRegion(disabled == nil ? .item(item) : .disabled(item))
    }

    private var layersColumn: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                Text("Layers").font(.headline).padding(.bottom, 6)
                if draft.root.isEmpty {
                    Text("Nothing placed yet.").font(.caption).foregroundStyle(.secondary)
                }
                ForEach(draft.root.reversed()) { node in
                    layerRows(node, depth: 0)
                }
                let unplaced = store.userComponents.filter { draft.nodes(of: $0.type).isEmpty }
                if !unplaced.isEmpty {
                    Text("Not placed").font(.caption.smallCaps()).foregroundStyle(.secondary).padding(.top, 12)
                    ForEach(unplaced) { definition in
                        Button { select(nil, component: definition.type) } label: {
                            row(icon: definition.icon, title: definition.title, selected: component == definition.type && selection == nil)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(14)
        }
    }

    private func layerRows(_ node: LayoutNode, depth: Int) -> AnyView {
        let definition = store.definition(for: node.type)
        let layout = node.role == .view ? layout(of: node.type) : nil
        let names = node.role == .view ? runtime.trees[node.type]?.slotNames ?? [] : []
        let slotNames = layout != nil ? [] : names + node.slots.keys.filter { !names.contains($0) }.sorted()
        return AnyView(VStack(alignment: .leading, spacing: 2) {
            Button { select(node.id) } label: {
                row(icon: node.role == .hover ? "cursorarrow.rays" : definition?.icon ?? "questionmark.square",
                    title: title(of: node), selected: selection == node.id,
                    detail: node.layout.attach != nil ? "fills gap" : runtime.errors[node.type] != nil ? "error" : nil)
                    .padding(.leading, CGFloat(depth) * 16)
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button(draft.address(of: node.id) == nil ? "Bring Forward" : "Move Earlier") {
                    draft.reorder(node.id, by: draft.address(of: node.id) == nil ? 1 : -1)
                }
                Button(draft.address(of: node.id) == nil ? "Send Backward" : "Move Later") {
                    draft.reorder(node.id, by: draft.address(of: node.id) == nil ? -1 : 1)
                }
                Divider()
                Button("Delete", role: .destructive) { delete(node.id) }
            }
            if let layout {
                if layout.isContainer {
                    ForEach(Array(layout.children.enumerated()), id: \.offset) { index, child in
                        partRows(child, path: [index], node: node, depth: depth + 1)
                    }
                } else {
                    partRows(layout, path: [], node: node, depth: depth + 1)
                }
            }
            ForEach(slotNames, id: \.self) { name in
                Text(name).font(.caption2.smallCaps()).foregroundStyle(.secondary)
                    .padding(.leading, CGFloat(depth + 1) * 16 + 6)
                ForEach(node.slots[name] ?? []) { child in
                    layerRows(child, depth: depth + 1)
                }
            }
        })
    }

    /// A piece of a component's layout, and what's inside it.
    private func partRows(_ item: PartLayout, path: [Int], node: LayoutNode, depth: Int) -> AnyView {
        let editable = canEditParts(node)
        return AnyView(VStack(alignment: .leading, spacing: 2) {
            Button { if editable { editParts(node.id, select: path) } } label: {
                row(icon: partIcon(item, of: node.type), title: partTitle(item, of: node.type),
                    selected: focus == node.id && part == path)
                    .padding(.leading, CGFloat(depth) * 16)
            }
            .buttonStyle(.plain)
            .foregroundStyle(editable ? HierarchicalShapeStyle.primary : .secondary)
            ForEach(Array(item.children.enumerated()), id: \.offset) { index, child in
                partRows(child, path: path + [index], node: node, depth: depth + 1)
            }
            if item.kind == .slot {
                ForEach(node.slots[item.name ?? ""] ?? []) { child in
                    layerRows(child, depth: depth + 1)
                }
            }
        })
    }

    private func row(icon: String, title: String, selected: Bool, detail: String? = nil) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).frame(width: 16)
            Text(title).lineLimit(1)
            Spacer(minLength: 0)
            if let detail { Text(detail).font(.caption2).foregroundStyle(.secondary) }
        }
        .padding(.horizontal, 6).padding(.vertical, 4)
        .background(selected ? Color.accentColor.opacity(0.2) : .clear, in: RoundedRectangle(cornerRadius: 5))
        .contentShape(Rectangle())
    }

    private func title(of node: LayoutNode) -> String {
        let name = store.definition(for: node.type)?.title ?? "Missing \(node.type)"
        return node.role == .hover ? "\(name) hover area" : name
    }

    // MARK: Canvas

    private var canvasArea: some View {
        VStack(spacing: 12) {
            componentStrip
            GeometryReader { proxy in
                let scale = max(0.05, min(proxy.size.width / max(1, windowSize.width),
                                          proxy.size.height / max(1, windowSize.height), 1))
                canvas(scale: scale)
                    .frame(width: windowSize.width * scale, height: windowSize.height * scale, alignment: .topLeading)
                    .editorRegion(.canvas)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Text(canvasHint).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 12)
    }

    private var canvasHint: String {
        if focus != nil {
            switch interaction {
            case .placePart, .movePart: return "Drop into a row or column; the line shows where it goes."
            default: return "Click a part to select it, and drag it to rearrange. Click outside the component, or press Esc, when you’re done."
            }
        }
        switch interaction {
        case .place, .move:
            return "Drop into a highlighted slot, or beside the WebView to fill the gap. Hold ⌥ to place freely, ⇧ to snap."
        default:
            if let selection, draft.node(selection)?.role == .hover {
                return "Double-click to show what it opens. Drag to move, or drag the handles to resize."
            }
            return "Drag from above onto the window or into a slot. Click to select; double-click a component to open its file."
        }
    }

    private func canvas(scale: CGFloat) -> some View {
        let windowFrames = self.windowFrames
        return ZStack(alignment: .topLeading) {
            preview(windowFrames)
                .frame(width: windowSize.width, height: windowSize.height, alignment: .topLeading)
                .scaleEffect(scale, anchor: .topLeading)
                .frame(width: windowSize.width * scale, height: windowSize.height * scale, alignment: .topLeading)
                .allowsHitTesting(false)
            overlays(scale: scale)
                .allowsHitTesting(false)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14 * scale + 4, style: .continuous))
        .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
    }

    private func preview(_ windowFrames: WindowFrames) -> some View {
        ZStack(alignment: .topLeading) {
            windowBackground.frame(width: windowSize.width, height: windowSize.height)
            if let web = draft.webView, let rect = windowFrames.frames[web.id] {
                let radius = CGFloat(draft.props(of: LayoutDocument.webViewType)["cornerRadius"]?.number ?? 14)
                ZStack {
                    Color.white
                    if let snapshot { Image(nsImage: snapshot).resizable().scaledToFill() }
                    else { Label("WebView", systemImage: "globe").font(.title3).foregroundStyle(.secondary) }
                }
                .frame(width: rect.width, height: rect.height)
                .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                .position(x: rect.midX, y: rect.midY)
            } else if draft.root.isEmpty {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.secondary.opacity(0.6), style: .init(lineWidth: 2, dash: [10]))
                    .overlay {
                        VStack(spacing: 8) {
                            Image(systemName: "square.dashed").font(.system(size: 40))
                            Text("An empty window. Drag a WebView here, then place components around it.").font(.title3)
                        }
                        .foregroundStyle(.secondary)
                    }
                    .frame(width: contentBounds.width, height: contentBounds.height)
                    .position(x: contentBounds.midX, y: contentBounds.midY)
            }
            LayoutWindowView(document: draft, frames: windowFrames, size: windowSize, environment: previewEnvironment,
                             hidden: hiddenViews)
                .onPreferenceChange(NodeFramesKey.self) { nodeFrames = $0 }
                .onPreferenceChange(SlotFramesKey.self) { slotFrames = $0 }
                .onPreferenceChange(PartFramesKey.self) { partFrames = $0 }
        }
    }

    @ViewBuilder
    private func overlays(scale: CGFloat) -> some View {
        let s = { (rect: CGRect) in CGRect(x: rect.minX * scale, y: rect.minY * scale,
                                           width: rect.width * scale, height: rect.height * scale) }
        ZStack(alignment: .topLeading) {
            Color.clear
            ForEach(draft.root.filter { $0.role == .hover }) { node in
                if let rect = frame(of: node.id) {
                    let shown = zoneRect(s(rect))
                    Rectangle().fill(Color.orange.opacity(node.type == component ? 0.45 : 0.28))
                        .overlay { Rectangle().strokeBorder(Color.orange, style: .init(lineWidth: 1.5, dash: [4])) }
                        .frame(width: shown.width, height: shown.height)
                        .offset(x: shown.minX, y: shown.minY)
                }
            }
            if let item = interaction?.dragged, item.role == .view, item.type != LayoutDocument.webViewType {
                ForEach(Array(acceptingSlots(excluding: interaction?.movedID)), id: \.self) { address in
                    if let rect = slotFrames[address]?.rect {
                        let shown = s(rect).insetBy(dx: -3, dy: -3)
                        RoundedRectangle(cornerRadius: 5)
                            .strokeBorder(Color.accentColor.opacity(target?.address == address ? 1 : 0.5),
                                          style: .init(lineWidth: target?.address == address ? 2 : 1, dash: [4]))
                            .background(Color.accentColor.opacity(target?.address == address ? 0.15 : 0.05))
                            .frame(width: shown.width, height: shown.height)
                            .offset(x: shown.minX, y: shown.minY)
                    }
                }
            }
            if interaction?.isDrag == true, let target { dropIndicator(target, s: s) }
            if let focus {
                focusOverlay(focus, s: s)
            } else if let selection, let rect = frame(of: selection), interaction?.movedID != selection || target == nil {
                selectionOverlay(selection, rect: s(rect), scale: scale)
            }
        }
    }

    @ViewBuilder
    private func dropIndicator(_ target: DropTarget, s: (CGRect) -> CGRect) -> some View {
        switch target {
        case .free(let rect):
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color.accentColor, style: .init(lineWidth: 2, dash: [6]))
                .background(Color.accentColor.opacity(0.12))
                .frame(width: max(4, s(rect).width), height: max(4, s(rect).height))
                .offset(x: s(rect).minX, y: s(rect).minY)
        case .attach(let side):
            if let web = windowFrames.webView {
                let gap = WindowFrames.gap(side, beside: web, in: contentBounds)
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.accentColor.opacity(0.25))
                    .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(Color.accentColor, lineWidth: 2) }
                    .overlay { Text("Fill \(side.rawValue) gap").font(.caption.bold()).foregroundStyle(Color.accentColor) }
                    .frame(width: max(8, s(gap).width), height: max(8, s(gap).height))
                    .offset(x: s(gap).minX, y: s(gap).minY)
            }
        case .slot(let address, let index):
            let line = s(insertionLine(address, index: index))
            Rectangle().fill(Color.accentColor)
                .frame(width: max(3, line.width), height: max(3, line.height))
                .offset(x: line.minX, y: line.minY)
        case .part(let container, let index):
            if let area = focus.flatMap({ partFrames[PartAddress(node: $0, path: container)] }) {
                let shown = s(area)
                Rectangle().strokeBorder(Color.accentColor.opacity(0.6), style: .init(lineWidth: 1, dash: [4]))
                    .frame(width: shown.width, height: shown.height)
                    .offset(x: shown.minX, y: shown.minY)
            }
            let line = s(partInsertionLine(container, index: index))
            Rectangle().fill(Color.accentColor)
                .frame(width: max(3, line.width), height: max(3, line.height))
                .offset(x: line.minX, y: line.minY)
        }
    }

    /// The component whose parts are being edited, its parts, and the selected one.
    private func focusOverlay(_ id: String, s: @escaping (CGRect) -> CGRect) -> some View {
        let parts = partFrames.filter { $0.key.node == id && !$0.key.path.isEmpty }
        return ZStack(alignment: .topLeading) {
            if let rect = frame(of: id).map(s) {
                Rectangle().strokeBorder(Color.accentColor.opacity(0.8), style: .init(lineWidth: 1.5, dash: [6, 3]))
                    .frame(width: rect.width, height: rect.height)
                    .offset(x: rect.minX, y: rect.minY)
            }
            ForEach(Array(parts.keys), id: \.self) { address in
                let rect = s(parts[address] ?? .zero)
                Rectangle().strokeBorder(Color.accentColor.opacity(0.3), lineWidth: 1)
                    .frame(width: rect.width, height: rect.height)
                    .offset(x: rect.minX, y: rect.minY)
            }
            if let part, interaction?.movedPart == nil || target == nil,
               let rect = partFrames[PartAddress(node: id, path: part)].map(s) {
                Rectangle().strokeBorder(Color.accentColor, lineWidth: 2)
                    .frame(width: max(4, rect.width), height: max(4, rect.height))
                    .offset(x: rect.minX, y: rect.minY)
            }
        }
    }

    private func selectionOverlay(_ id: String, rect: CGRect, scale: CGFloat) -> some View {
        let rect = draft.node(id)?.role == .hover ? zoneRect(rect) : rect
        return ZStack(alignment: .topLeading) {
            Rectangle().strokeBorder(Color.accentColor, lineWidth: 2)
                .frame(width: rect.width, height: rect.height)
                .offset(x: rect.minX, y: rect.minY)
            ForEach(Array(handles(for: id).enumerated()), id: \.offset) { _, handle in
                let point = CGPoint(x: handle.point.x * scale, y: handle.point.y * scale)
                RoundedRectangle(cornerRadius: 2)
                    .fill(.white)
                    .overlay { RoundedRectangle(cornerRadius: 2).strokeBorder(Color.accentColor, lineWidth: 1.5) }
                    .frame(width: handle.edges.count == 1 ? (handle.edges.first!.vertical ? 6 : 18) : 9,
                           height: handle.edges.count == 1 ? (handle.edges.first!.vertical ? 18 : 6) : 9)
                    .position(point)
            }
        }
    }

    private var dragLabel: (title: String, icon: String)? {
        switch interaction {
        case .place(let item), .move(_, let item, _, _):
            let definition = store.definition(for: item.type)
            return item.role == .hover
                ? ("\(definition?.title ?? item.type) hover area", "cursorarrow.rays")
                : (definition?.title ?? item.type, definition?.icon ?? "square")
        case .placePart(let item):
            return focusType.map { (partTitle(item, of: $0), partIcon(item, of: $0)) }
        case .movePart(let path):
            return focusType.flatMap { type in layout(of: type)?[path].map { (partTitle($0, of: type), partIcon($0, of: type)) } }
        default:
            return nil
        }
    }

    @ViewBuilder private var dragChip: some View {
        if let label = dragLabel, let pointer {
            Label(label.title, systemImage: label.icon)
                .font(.callout)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(.regularMaterial, in: Capsule())
                .overlay { Capsule().strokeBorder(Color.accentColor) }
                .shadow(radius: 4)
                .fixedSize()
                .offset(x: pointer.x + 12, y: pointer.y + 10)
                .allowsHitTesting(false)
        }
    }

    // MARK: Inspector

    @ViewBuilder private var inspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let focus, let path = part, let node = draft.node(focus), let item = layout(of: node.type)?[path] {
                    partInspector(item, path: path, node: node)
                } else if let selection, let node = draft.node(selection) {
                    nodeHeader(node)
                    if node.role == .view, store.definition(for: node.type)?.layout != nil {
                        partsSection(node)
                    }
                    if let address = draft.address(of: node.id) {
                        section("In \(draft.node(address.owner).map(title(of:)) ?? "a component") › \(address.name)") {
                            HStack {
                                Button("Move Earlier") { draft.reorder(node.id, by: -1) }
                                Button("Move Later") { draft.reorder(node.id, by: 1) }
                            }
                            Text("Drag it to another slot, or onto the window to place it freely.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    } else {
                        section("Position in the window") { layoutControls(node) }
                    }
                    componentInspector(node.type)
                } else if let component, let definition = store.definition(for: component) {
                    HStack(spacing: 8) {
                        Image(systemName: definition.icon).font(.title3)
                        Text(definition.title).font(.headline)
                    }
                    componentInspector(component)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Window").font(.headline)
                        Text("Each component is a file in the Components folder that decides what it looks like and what opens it. Place components in the window, or in the slots other components have, like the Sidebar’s buttons.")
                            .font(.callout).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Open Components Folder") { NSWorkspace.shared.open(store.componentsURL) }
                    }
                }
                if let message = saveError ?? store.fileError ?? runtime.errors["engine"] {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange).textSelection(.enabled)
                }
            }
            .padding(16)
        }
    }

    private func nodeHeader(_ node: LayoutNode) -> some View {
        HStack(spacing: 8) {
            Image(systemName: node.role == .hover ? "cursorarrow.rays" : store.definition(for: node.type)?.icon ?? "questionmark.square")
                .font(.title3)
            Text(title(of: node)).font(.headline)
            Spacer()
            Button { delete(node.id) } label: { Image(systemName: "trash") }
                .buttonStyle(.borderless)
                .help("Remove")
        }
    }

    @ViewBuilder
    private func partsSection(_ node: LayoutNode) -> some View {
        let file = store.definition(for: node.type)?.source?.lastPathComponent ?? "its file"
        section("Parts") {
            if focus == node.id {
                Text("Click a part to arrange it, or drag it somewhere else. Drag new pieces in from above the preview.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Button("Done Editing Parts") { select(node.id) }
            } else if canEditParts(node) {
                Text("Double-click it in the preview to rearrange its parts. Saving writes the change to \(file).")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Button("Edit Parts") { editParts(node.id) }
            } else {
                Text("\(file) has no // <aria:layout> and // </aria:layout> lines around its layout, so the editor can’t rewrite it.")
                    .font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// One piece of a component's layout: where it sits, and its size and spacing.
    @ViewBuilder
    private func partInspector(_ item: PartLayout, path: [Int], node: LayoutNode) -> some View {
        let type = node.type
        let definition = store.definition(for: type)
        let siblings = layout(of: type)?[Array(path.dropLast())]?.children.count ?? 1
        let blocking = blockingSlot(item, of: type)
        HStack(spacing: 8) {
            Image(systemName: partIcon(item, of: type)).font(.title3)
            Text(partTitle(item, of: type)).font(.headline)
            Spacer()
            if !path.isEmpty {
                Button {
                    editLayout(type) { $0.remove(at: path) }
                    part = nil
                } label: { Image(systemName: "trash") }
                    .buttonStyle(.borderless)
                    .disabled(blocking != nil)
                    .help(blocking.map { "Move the components out of the \($0) slot first." }
                          ?? (item.kind == .part ? "Take it out of the layout. It stays in the file’s parts." : "Remove"))
            }
        }
        Text("In \(definition?.title ?? type). Saving writes the change to \(definition?.source?.lastPathComponent ?? "its file").")
            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        if !path.isEmpty {
            section("Arrange") {
                HStack {
                    Button("Move Earlier") { movePart(path, by: -1, in: type) }.disabled(path.last == 0)
                    Button("Move Later") { movePart(path, by: 1, in: type) }.disabled(path.last == siblings - 1)
                }
                HStack {
                    Button("Wrap in Row") { editLayout(type) { $0.wrap(path, in: .row) }; part = path }
                    Button("Wrap in Column") { editLayout(type) { $0.wrap(path, in: .column) }; part = path }
                    if item.isContainer {
                        Button("Ungroup") { editLayout(type) { $0.ungroup(path) }; part = nil }
                    }
                }
            }
        }
        if item.isContainer {
            section("Children") {
                Picker("Direction", selection: Binding(
                    get: { layout(of: type)?[path]?.kind ?? item.kind },
                    set: { kind in editLayout(type) { $0.modify(path) { $0.kind = kind; $0.align = nil } } })) {
                    Text("Row").tag(PartLayout.Kind.row)
                    Text("Column").tag(PartLayout.Kind.column)
                }
                .pickerStyle(.segmented)
                Picker("Align", selection: Binding(
                    get: { layout(of: type)?[path]?.align ?? "" },
                    set: { value in editLayout(type) { $0.modify(path) { $0.align = value.isEmpty ? nil : value } } })) {
                    Text("Default").tag("")
                    ForEach(item.kind == .column ? ["leading", "center", "trailing"] : ["top", "center", "bottom"], id: \.self) {
                        Text($0.capitalized).tag($0)
                    }
                }
                optionalNumber("Spacing", partValue(type, path, \.spacing), placeholder: "8")
            }
        }
        if item.kind == .slot {
            section("Slot") {
                Picker("Direction", selection: Binding(
                    get: { layout(of: type)?[path]?.direction ?? "row" },
                    set: { value in editLayout(type) { $0.modify(path) { $0.direction = value == "row" ? nil : value } } })) {
                    Text("Row").tag("row")
                    Text("Column").tag("column")
                }
                .pickerStyle(.segmented)
                optionalNumber("Spacing", partValue(type, path, \.spacing), placeholder: "8")
            }
        }
        if item.kind != .divider {
            section("Size") {
                Toggle("Grow to fill the space", isOn: Binding(
                    get: { layout(of: type)?[path]?.grow == true },
                    set: { on in editLayout(type) { $0.modify(path) { $0.grow = on ? true : nil } } }))
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                    GridRow {
                        optionalNumber("Width", partValue(type, path, \.width))
                        optionalNumber("Height", partValue(type, path, \.height))
                    }
                    GridRow {
                        optionalNumber("Pad X", paddingValue(type, path, 0), placeholder: "0")
                        optionalNumber("Pad Y", paddingValue(type, path, 1), placeholder: "0")
                    }
                }
            }
        }
        if let source = definition?.source {
            Button("Open \(source.lastPathComponent)") { NSWorkspace.shared.open(source) }
        }
    }

    private func partValue(_ type: String, _ path: [Int], _ key: WritableKeyPath<PartLayout, Double?>) -> Binding<Double?> {
        Binding(get: { layout(of: type)?[path]?[keyPath: key] },
                set: { value in editLayout(type) { $0.modify(path) { $0[keyPath: key] = value } } })
    }

    private func paddingValue(_ type: String, _ path: [Int], _ index: Int) -> Binding<Double?> {
        Binding(get: { layout(of: type)?[path]?.padding?[index] },
                set: { value in
                    editLayout(type) {
                        $0.modify(path) { node in
                            var padding = node.padding ?? [0, 0]
                            padding[index] = max(0, value ?? 0)
                            node.padding = padding == [0, 0] ? nil : padding
                        }
                    }
                })
    }

    private func optionalNumber(_ label: String, _ value: Binding<Double?>, placeholder: String = "Auto") -> some View {
        HStack(spacing: 4) {
            Text(label).foregroundStyle(.secondary).frame(width: 48, alignment: .leading)
            TextField(placeholder, value: value, format: .number)
                .textFieldStyle(.roundedBorder).frame(width: 64)
        }
    }

    @ViewBuilder
    private func componentInspector(_ type: String) -> some View {
        if let definition = store.definition(for: type) {
            if !definition.isWebView {
                Text(definition.summary).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !definition.alwaysOpen || definition.opensAs == .overlay {
                    section("Opens") { openingControls(definition) }
                }
            }
            if let error = runtime.errors[type] {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !definition.props.isEmpty {
                section("Properties") {
                    ForEach(definition.props) { prop in
                        PropControl(spec: prop, value: Binding(
                            get: { draft.props(of: type)[prop.name] ?? prop.defaultValue },
                            set: { value in
                                var props = draft.props(of: type)
                                props[prop.name] = value == prop.defaultValue ? nil : value
                                draft.props[type] = props.isEmpty ? nil : props
                            }))
                    }
                }
            }
            if let source = definition.source {
                Button("Open \(source.lastPathComponent)") { NSWorkspace.shared.open(source) }
            }
        } else {
            Text("No component file defines \(type). Remove it, or add a file to the Components folder.")
                .font(.callout).foregroundStyle(.orange)
        }
    }

    @ViewBuilder
    private func openingControls(_ definition: ComponentDefinition) -> some View {
        let hoverAreas = draft.root.filter { $0.type == definition.type && $0.role == .hover }.count
        if definition.alwaysOpen {
            Label("Always open", systemImage: "checkmark.circle")
        }
        ForEach(Array(definition.activators.enumerated()), id: \.offset) { _, activator in
            switch activator.kind {
            case .hover:
                VStack(alignment: .leading, spacing: 2) {
                    Label("While the pointer is over its hover area", systemImage: "cursorarrow.rays")
                    Text(hoverAreas == 0 ? "No hover area placed yet: drag one from above the preview."
                         : hoverAreas == 1 ? "Placed once" : "Placed \(hoverAreas) times")
                        .font(.caption).foregroundStyle(hoverAreas == 0 ? .orange : .secondary)
                        .padding(.leading, 26)
                }
            case .shortcut:
                Label("With \(KeyShortcut(activator.keys ?? "")?.display ?? activator.keys ?? "")", systemImage: "keyboard")
            case .when:
                Label("When a rule in its file is true", systemImage: "function")
            }
        }
        Text("Buttons in other components can open it too.").font(.caption).foregroundStyle(.secondary)
        if definition.opensAs == .overlay {
            Label("Appears over the middle of the window", systemImage: "rectangle.center.inset.filled")
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline.weight(.semibold))
            content()
        }
    }

    @ViewBuilder
    private func layoutControls(_ node: LayoutNode) -> some View {
        if let side = node.layout.attach {
            Text("Fills the gap to the \(side.rawValue) of the WebView. Drag its inner edge to resize both.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Button("Detach") {
                if let rect = frame(of: node.id) { draft.update(node.id) { $0.layout.place(rect, in: contentBounds) } }
            }
        } else if let rect = frame(of: node.id) {
            let slot = contentBounds
            let local = rect.offsetBy(dx: -slot.minX, dy: -slot.minY)
            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 6) {
                GridRow {
                    numberField("X", value: local.minX) { setFrame(node.id, CGRect(x: slot.minX + $0, y: rect.minY, width: rect.width, height: rect.height)) }
                    numberField("Y", value: local.minY) { setFrame(node.id, CGRect(x: rect.minX, y: slot.minY + $0, width: rect.width, height: rect.height)) }
                }
                GridRow {
                    numberField("W", value: rect.width) { setFrame(node.id, CGRect(x: rect.minX, y: rect.minY, width: max(2, $0), height: rect.height)) }
                    numberField("H", value: rect.height) { setFrame(node.id, CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: max(2, $0))) }
                }
            }
            HStack(spacing: 4) {
                Text("Pinned to").foregroundStyle(.secondary)
                ForEach(PanelEdge.allCases, id: \.self) { edge in
                    Toggle(edge.rawValue.capitalized, isOn: Binding(
                        get: { node.layout.pinned(edge) },
                        set: { on in
                            var pins = Set(PanelEdge.allCases.filter(node.layout.pinned))
                            if on { pins.insert(edge) } else { pins.remove(edge) }
                            draft.update(node.id) { $0.layout.place(rect, in: slot, pins: pins) }
                        }))
                        .toggleStyle(.button).controlSize(.small)
                }
            }
            .font(.caption)
            if node.role == .view, node.type != LayoutDocument.webViewType, draft.webView != nil {
                Menu("Fill a gap beside the WebView") {
                    ForEach(PanelEdge.allCases, id: \.self) { side in
                        Button(side.rawValue.capitalized) { draft.update(node.id) { $0.layout = Placement(attach: side) } }
                    }
                }
                .fixedSize()
            }
        }
    }

    private func numberField(_ label: String, value: CGFloat, set: @escaping (CGFloat) -> Void) -> some View {
        HStack(spacing: 4) {
            Text(label).foregroundStyle(.secondary).frame(width: 14, alignment: .leading)
            TextField(label, value: Binding(get: { Double(value.rounded()) }, set: { set(CGFloat($0)) }), format: .number)
                .textFieldStyle(.roundedBorder).frame(width: 70)
        }
    }

    private func openingSummary(_ definition: ComponentDefinition) -> String {
        if let shortcut = definition.activator(.shortcut) { return "opens with \(KeyShortcut(shortcut.keys ?? "")?.display ?? "a shortcut")" }
        if definition.activator(.when) != nil { return "opens by rule" }
        return "opened by buttons"
    }

    // MARK: Geometry

    private var windowFrames: WindowFrames {
        WindowFrames(draft, in: contentBounds) { natural($0) }
    }

    private func natural(_ node: LayoutNode) -> CGSize {
        store.definition(for: node.type)?.natural(node.role) ?? CGSize(width: 240, height: 200)
    }

    /// Where a node is: from the window's layout, or as SwiftUI laid it out in a slot.
    private func frame(of id: String) -> CGRect? {
        draft.address(of: id) == nil ? windowFrames.frames[id] : nodeFrames[id]
    }

    /// The renderer's settings for the preview: the draft's props, and buttons that do nothing.
    private var previewEnvironment: LayoutEnvironment {
        var environment = self.environment
        environment.props = renderInput.props
        environment.trees = runtime.trees
        environment.errors = runtime.errors
        environment.perform = { _, _, _, _ in }
        environment.setLocal = { _, _, _ in }
        environment.isActive = { _ in false }
        environment.hold = { _, _ in }
        return environment
    }

    /// Components in the window drawn in the preview: those that are always open, the one
    /// holding the selection, and, while dragging, those with slots to drop into.
    /// Everything else only appears when something opens it.
    private var hiddenViews: Set<String> {
        let shown = (focus ?? selection).flatMap { draft.host(of: $0)?.type } ?? component
        return Set(draft.root.filter { node in
            guard node.role == .view, node.type != LayoutDocument.webViewType,
                  let definition = store.definition(for: node.type) else { return false }
            if definition.alwaysOpen || node.type == shown { return false }
            if interaction?.dragged != nil, !(runtime.trees[node.type]?.slotNames.isEmpty ?? true) { return false }
            return true
        }.map(\.id))
    }

    /// Hover areas are often a few points thick, so draw them at least 10 points across.
    private func zoneRect(_ rect: CGRect) -> CGRect {
        var rect = rect
        if rect.width < 10 { rect = rect.insetBy(dx: (rect.width - 10) / 2, dy: 0) }
        if rect.height < 10 { rect = rect.insetBy(dx: 0, dy: (rect.height - 10) / 2) }
        return rect
    }

    private struct Handle {
        var edges: Set<PanelEdge>
        var point: CGPoint
    }

    /// Resize handles for something placed in the window, in window points. Slots size their children.
    private func handles(for id: String) -> [Handle] {
        guard draft.address(of: id) == nil, let rect = frame(of: id), let node = draft.node(id) else { return [] }
        if let side = node.layout.attach {
            let inner: PanelEdge = switch side { case .left: .right; case .right: .left; case .top: .bottom; case .bottom: .top }
            return [Handle(edges: [inner], point: point(on: inner, of: rect))]
        }
        let corners: [Handle] = [
            Handle(edges: [.left, .top], point: CGPoint(x: rect.minX, y: rect.minY)),
            Handle(edges: [.right, .top], point: CGPoint(x: rect.maxX, y: rect.minY)),
            Handle(edges: [.left, .bottom], point: CGPoint(x: rect.minX, y: rect.maxY)),
            Handle(edges: [.right, .bottom], point: CGPoint(x: rect.maxX, y: rect.maxY)),
        ]
        return corners + PanelEdge.allCases.map { Handle(edges: [$0], point: point(on: $0, of: rect)) }
    }

    private func point(on edge: PanelEdge, of rect: CGRect) -> CGPoint {
        switch edge {
        case .left: CGPoint(x: rect.minX, y: rect.midY)
        case .right: CGPoint(x: rect.maxX, y: rect.midY)
        case .top: CGPoint(x: rect.midX, y: rect.minY)
        case .bottom: CGPoint(x: rect.midX, y: rect.maxY)
        }
    }

    /// What can be clicked, frontmost first: components in slots, hover areas,
    /// visible components in the window, then the WebView.
    private var selectableNodes: [LayoutNode] {
        let hidden = hiddenViews
        let visible = draft.root.filter { $0.role == .view && $0.type != LayoutDocument.webViewType && !hidden.contains($0.id) }
        return visible.reversed().flatMap { $0.flattened.dropFirst().reversed() }
            + draft.root.filter { $0.role == .hover }.reversed()
            + visible.reversed()
            + draft.root.filter { $0.type == LayoutDocument.webViewType }
    }

    private func node(at point: CGPoint) -> LayoutNode? {
        let scale = (regions[.canvas]?.width ?? windowSize.width) / max(1, windowSize.width)
        return selectableNodes.first { node in
            guard var rect = frame(of: node.id) else { return false }
            if node.role == .hover {
                let shown = zoneRect(CGRect(x: rect.minX * scale, y: rect.minY * scale, width: rect.width * scale, height: rect.height * scale))
                rect = CGRect(x: shown.minX / scale, y: shown.minY / scale, width: shown.width / scale, height: shown.height / scale)
            }
            return rect.contains(point)
        }
    }

    /// Slots on screen that can take a component, leaving out the moved one's own slots.
    private func acceptingSlots(excluding moved: String?) -> [SlotAddress] {
        let excluded = Set(moved.flatMap { draft.node($0) }?.flattened.map(\.id) ?? [])
        return slotFrames.keys.filter { !excluded.contains($0.owner) && draft.node($0.owner) != nil }
    }

    private func dropTarget(for item: PlaceItem, at point: CGPoint, moving id: String?) -> DropTarget? {
        guard contentBounds.insetBy(dx: -40, dy: -40).contains(point) else { return nil }
        if item.type == LayoutDocument.webViewType {
            return .free(contentBounds)
        }
        if item.role == .view {
            // The smallest slot under the pointer is the innermost.
            let slots = acceptingSlots(excluding: id).compactMap { address in
                slotFrames[address].map { (address, $0) }
            }.filter { $0.1.rect.insetBy(dx: -4, dy: -4).contains(point) }
            if let (address, slot) = slots.min(by: { $0.1.rect.width * $0.1.rect.height < $1.1.rect.width * $1.1.rect.height }) {
                let index = draft.children(of: address).filter { $0.id != id }.filter { sibling in
                    guard let rect = nodeFrames[sibling.id] else { return false }
                    return slot.axis == .vertical ? rect.midY < point.y : rect.midX < point.x
                }.count
                return .slot(address, index: index)
            }
        }
        let size = id.flatMap { draft.address(of: $0) == nil ? frame(of: $0)?.size : nil }
            ?? store.definition(for: item.type)?.natural(item.role) ?? CGSize(width: 240, height: 200)
        if item.role == .view, let web = windowFrames.webView, !web.contains(point), contentBounds.contains(point),
           !NSEvent.modifierFlags.contains(.option) {
            if point.x < web.minX { return .attach(.left) }
            if point.x > web.maxX { return .attach(.right) }
            return .attach(point.y < web.minY ? .top : .bottom)
        }
        // A new hover area runs along the edge its file names.
        if id == nil, item.role == .hover, let hover = store.definition(for: item.type)?.activator(.hover), let edge = hover.edge {
            let thickness = CGFloat(hover.size ?? 6)
            let b = contentBounds
            let rect: CGRect = switch edge {
            case .left: CGRect(x: b.minX, y: b.minY, width: thickness, height: b.height)
            case .right: CGRect(x: b.maxX - thickness, y: b.minY, width: thickness, height: b.height)
            case .top: CGRect(x: b.minX, y: b.minY, width: b.width, height: thickness)
            case .bottom: CGRect(x: b.minX, y: b.maxY - thickness, width: b.width, height: thickness)
            }
            return .free(rect)
        }
        return .free(centred(size, at: point, in: contentBounds))
    }

    private func insertionLine(_ address: SlotAddress, index: Int) -> CGRect {
        guard let slot = slotFrames[address] else { return .zero }
        let siblings = draft.children(of: address).filter { $0.id != interaction?.movedID }.compactMap { nodeFrames[$0.id] }
        return line(in: slot.rect, vertical: slot.axis == .vertical, siblings: siblings, index: index)
    }

    /// Where an insertion line goes among a row's or column's children.
    private func line(in area: CGRect, vertical: Bool, siblings: [CGRect], index: Int) -> CGRect {
        let position: CGFloat
        if siblings.isEmpty {
            position = vertical ? area.minY + 2 : area.minX + 2
        } else if index < siblings.count {
            position = vertical ? siblings[index].minY - 2 : siblings[index].minX - 2
        } else {
            position = vertical ? siblings.last!.maxY + 2 : siblings.last!.maxX + 2
        }
        return vertical
            ? CGRect(x: area.minX, y: position - 1.5, width: area.width, height: 3)
            : CGRect(x: position - 1.5, y: area.minY, width: 3, height: area.height)
    }

    private func centred(_ size: CGSize, at point: CGPoint, in area: CGRect) -> CGRect {
        let w = min(size.width, area.width), h = min(size.height, area.height)
        return CGRect(x: min(max(area.minX, point.x - w / 2), area.maxX - w),
                      y: min(max(area.minY, point.y - h / 2), area.maxY - h), width: w, height: h)
    }

    // MARK: Parts

    private func layout(of type: String) -> PartLayout? {
        layouts[type] ?? store.definition(for: type)?.layout
    }

    private func editLayout(_ type: String, _ change: (inout PartLayout) -> Void) {
        guard var layout = layout(of: type) else { return }
        change(&layout)
        layouts[type] = layout
    }

    private var focusType: String? { focus.flatMap { draft.node($0)?.type } }

    private func canEditParts(_ node: LayoutNode) -> Bool {
        node.role == .view && store.definition(for: node.type)?.layoutEditable == true
    }

    private func editParts(_ id: String, select path: [Int]? = nil) {
        select(id)
        focus = id
        part = path
    }

    private func partTitle(_ item: PartLayout, of type: String) -> String {
        switch item.kind {
        case .part: store.definition(for: type)?.part(item.name ?? "")?.title ?? item.name ?? "Part"
        case .slot: "\(item.name ?? "") slot"
        case .row: "Row"
        case .column: "Column"
        case .spacer: "Spacer"
        case .divider: "Divider"
        }
    }

    private func partIcon(_ item: PartLayout, of type: String) -> String {
        switch item.kind {
        case .part: store.definition(for: type)?.part(item.name ?? "")?.icon ?? "puzzlepiece"
        case .slot: "square.dashed"
        case .row: "rectangle.split.3x1"
        case .column: "rectangle.split.1x2"
        case .spacer: "arrow.left.and.right"
        case .divider: "minus"
        }
    }

    /// Parts the file defines that the layout doesn't use, then pieces any layout can add.
    private func partPalette(_ type: String) -> [PartLayout] {
        let used = Set(layout(of: type)?.partNames ?? [])
        let unused = (store.definition(for: type)?.parts ?? []).filter { !used.contains($0.name) }
            .map { PartLayout(kind: .part, name: $0.name) }
        return unused + [PartLayout(kind: .spacer), PartLayout(kind: .divider), PartLayout(kind: .row), PartLayout(kind: .column)]
    }

    private func area(_ rect: CGRect) -> CGFloat { rect.width * rect.height }

    /// The innermost piece of the focused component under the point. Nil when the point is
    /// outside the component, or on a component in one of its slots.
    private func partPath(at point: CGPoint, in id: String) -> [Int]? {
        guard let rect = frame(of: id), rect.contains(point) else { return nil }
        if let hit = node(at: point), hit.id != id,
           draft.node(id)?.flattened.contains(where: { $0.id == hit.id }) == true { return nil }
        let hits = partFrames.filter { $0.key.node == id && $0.value.contains(point) }
        let best = hits.min { a, b in
            area(a.value) != area(b.value) ? area(a.value) < area(b.value) : a.key.indexes.count > b.key.indexes.count
        }
        return best?.key.indexes ?? []
    }

    /// The row or column under the pointer, and where among its children a piece would go.
    private func partDropTarget(at point: CGPoint, moving: [Int]?) -> DropTarget? {
        guard let focus, let type = focusType, let layout = layout(of: type) else { return nil }
        let hits = layout.paths.filter { path in
            layout[path]?.isContainer == true && !(moving.map { path.starts(with: $0) } ?? false)
        }.compactMap { path in
            partFrames[PartAddress(node: focus, path: path)].map { (path: path, rect: $0) }
        }.filter { $0.rect.insetBy(dx: -4, dy: -4).contains(point) }
        guard let best = hits.min(by: { a, b in
            area(a.rect) != area(b.rect) ? area(a.rect) < area(b.rect) : a.path.count > b.path.count
        }), let container = layout[best.path] else { return nil }
        let vertical = container.kind == .column
        let index = container.children.indices.filter { best.path + [$0] != moving }.filter { index in
            guard let rect = partFrames[PartAddress(node: focus, path: best.path + [index])] else { return false }
            return vertical ? rect.midY < point.y : rect.midX < point.x
        }.count
        return .part(container: best.path, index: index)
    }

    private func partInsertionLine(_ container: [Int], index: Int) -> CGRect {
        guard let focus, let type = focusType, let node = layout(of: type)?[container],
              let area = partFrames[PartAddress(node: focus, path: container)] else { return .zero }
        let moving = interaction?.movedPart
        let siblings = node.children.indices.map { container + [$0] }.filter { $0 != moving }
            .compactMap { partFrames[PartAddress(node: focus, path: $0)] }
        return line(in: area, vertical: node.kind == .column, siblings: siblings, index: index)
    }

    private func movePart(_ path: [Int], by offset: Int, in type: String) {
        guard let index = path.last else { return }
        var moved: [Int]?
        editLayout(type) { moved = $0.move(path, into: Array(path.dropLast()), at: index + offset) }
        part = moved ?? path
    }

    /// A slot with components in it, in any placed copy of the component, stays until it's empty.
    private func blockingSlot(_ item: PartLayout, of type: String) -> String? {
        item.slotNames.first { name in draft.allNodes.contains { $0.type == type && !($0.slots[name]?.isEmpty ?? true) } }
    }

    // MARK: Gestures

    private var editorGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(EditorRegion.space))
            .onChanged { value in
                if interaction == nil {
                    guard hypot(value.translation.width, value.translation.height) > 3 else { return }
                    interaction = begin(at: value.startLocation) ?? .idle
                }
                pointer = value.location
                if let canvas = regions[.canvas] {
                    let scale = canvas.width / max(1, windowSize.width)
                    let point = CGPoint(x: (value.location.x - canvas.minX) / scale, y: (value.location.y - canvas.minY) / scale)
                    update(point: point, translation: CGSize(width: value.translation.width / scale,
                                                             height: value.translation.height / scale),
                           inCanvas: canvas.contains(value.location), scale: scale)
                }
            }
            .onEnded { value in
                if interaction == nil {
                    tap(at: value.location)
                } else {
                    finish()
                }
                interaction = nil
                target = nil
                pointer = nil
            }
    }

    private func windowPoint(_ point: CGPoint) -> CGPoint? {
        guard let canvas = regions[.canvas], canvas.contains(point) else { return nil }
        let scale = canvas.width / max(1, windowSize.width)
        return CGPoint(x: (point.x - canvas.minX) / scale, y: (point.y - canvas.minY) / scale)
    }

    private func item(at location: CGPoint) -> (item: PlaceItem, enabled: Bool)? {
        for (region, rect) in regions where rect.contains(location) {
            switch region {
            case .item(let item): return (item, true)
            case .disabled(let item): return (item, false)
            case .canvas, .part: continue
            }
        }
        return nil
    }

    private func begin(at location: CGPoint) -> Interaction? {
        if let template = partItem(at: location) { return .placePart(template) }
        if let (item, enabled) = item(at: location) {
            return enabled ? .place(item) : nil
        }
        guard let point = windowPoint(location), let canvas = regions[.canvas] else { return nil }
        if let focus, let path = partPath(at: point, in: focus) {
            part = path
            return path.isEmpty ? nil : .movePart(path)
        }
        let tolerance = 7 / (canvas.width / max(1, windowSize.width))
        if focus == nil, let selection, let node = draft.node(selection), let rect = frame(of: selection) {
            for handle in handles(for: selection) where hypot(point.x - handle.point.x, point.y - handle.point.y) < tolerance * 1.4 {
                if let side = node.layout.attach, let web = draft.webView, let webRect = windowFrames.webView {
                    return .resizeGap(webID: web.id, side: side, start: webRect)
                }
                return .resize(id: selection, edges: handle.edges, start: rect)
            }
        }
        guard let node = node(at: point), let rect = frame(of: node.id) else { return nil }
        select(node.id)
        return .move(id: node.id, item: PlaceItem(type: node.type, role: node.role),
                     grab: CGSize(width: point.x - rect.minX, height: point.y - rect.minY), start: rect)
    }

    private func partItem(at location: CGPoint) -> PartLayout? {
        for (region, rect) in regions where rect.contains(location) {
            if case .part(let item) = region { return item }
        }
        return nil
    }

    private func update(point: CGPoint, translation: CGSize, inCanvas: Bool, scale: CGFloat) {
        guard let interaction else { return }
        // Things move freely; holding Shift lines them up with edges and neighbours.
        let tolerance = NSEvent.modifierFlags.contains(.shift) ? 6 / scale : 0
        switch interaction {
        case .place(let item):
            let next = inCanvas ? dropTarget(for: item, at: point, moving: nil) : nil
            if next != target { target = next }
        case .move(let id, let item, let grab, let start):
            let next = inCanvas ? dropTarget(for: item, at: point, moving: id) : nil
            // In the window, unless it is about to fill a gap or go into a slot, it follows the pointer.
            if case .free = next, draft.address(of: id) == nil, draft.node(id)?.layout.attach == nil,
               item.type != LayoutDocument.webViewType {
                var rect = CGRect(origin: CGPoint(x: point.x - grab.width, y: point.y - grab.height), size: start.size)
                rect = snap(rect, edges: Set(PanelEdge.allCases), id: id, tolerance: tolerance, moving: true)
                setFrame(id, rect)
                if target != nil { target = nil }
            } else if next != target {
                target = next
            }
        case .resize(let id, let edges, let start):
            var rect = start
            if edges.contains(.left) { rect.origin.x += translation.width; rect.size.width -= translation.width }
            if edges.contains(.right) { rect.size.width += translation.width }
            if edges.contains(.top) { rect.origin.y += translation.height; rect.size.height -= translation.height }
            if edges.contains(.bottom) { rect.size.height += translation.height }
            rect = rect.standardized
            rect.size.width = max(2, rect.width)
            rect.size.height = max(2, rect.height)
            setFrame(id, snap(rect, edges: edges, id: id, tolerance: tolerance, moving: false))
        case .resizeGap(let webID, let side, let start):
            var web = start
            switch side {
            case .left: web.origin.x += translation.width; web.size.width -= translation.width
            case .right: web.size.width += translation.width
            case .top: web.origin.y += translation.height; web.size.height -= translation.height
            case .bottom: web.size.height += translation.height
            }
            web = web.standardized.intersection(contentBounds)
            guard web.width > 80, web.height > 80 else { return }
            draft.update(webID) { $0.layout.place(web, in: contentBounds) }
        case .placePart:
            let next = inCanvas ? partDropTarget(at: point, moving: nil) : nil
            if next != target { target = next }
        case .movePart(let path):
            let next = inCanvas ? partDropTarget(at: point, moving: path) : nil
            if next != target { target = next }
        case .idle:
            break
        }
    }

    private func finish() {
        guard let interaction, let target else { return }
        switch interaction {
        case .place(let item):
            var node = LayoutNode(type: item.type, role: item.role)
            if item.type == LayoutDocument.webViewType {
                node.layout = Placement(left: 0, top: 0, right: 0, bottom: 0)
                draft.insert(node, at: 0)
            } else {
                drop(&node, at: target)
            }
            select(node.id)
        case .move(let id, _, _, _):
            if case .part = target { return }
            guard var node = draft.remove(id) else { return }
            drop(&node, at: target)
            select(id)
        case .placePart(let template):
            guard case .part(let container, let index) = target, let type = focusType else { return }
            editLayout(type) { $0.insert(template, into: container, at: index) }
            part = container + [index]
        case .movePart(let path):
            guard case .part(let container, let index) = target, let type = focusType else { return }
            var moved: [Int]?
            editLayout(type) { moved = $0.move(path, into: container, at: index) }
            part = moved ?? path
        default:
            break
        }
    }

    /// Puts a node where it was dropped: into a slot, or into the window.
    private func drop(_ node: inout LayoutNode, at target: DropTarget) {
        switch target {
        case .slot(let address, let index):
            node.layout = Placement()
            draft.insert(node, into: address, at: index)
        case .free(let rect):
            node.layout.place(rect, in: contentBounds, pins: node.layout.attach == nil ? nil : [])
            draft.insert(node)
        case .attach(let side):
            node.layout = Placement(attach: side)
            draft.insert(node)
        case .part:
            break
        }
    }

    private func tap(at location: CGPoint) {
        if let (item, _) = item(at: location) {
            if item.type != LayoutDocument.webViewType { select(nil, component: item.type) }
            return
        }
        guard let point = windowPoint(location) else { return }
        if let focus, let path = partPath(at: point, in: focus) {
            part = path
            return
        }
        let hit = node(at: point)
        let now = Date()
        defer { lastTap = (hit?.id, now) }
        if let last = lastTap, last.id == hit?.id, now.timeIntervalSince(last.time) < 0.35, let hit {
            if hit.role == .hover {
                // Show what a hover area opens.
                if let view = draft.view(of: hit.type) { select(view.id) } else { select(nil, component: hit.type) }
            } else if canEditParts(hit) {
                editParts(hit.id)
            } else if let source = store.definition(for: hit.type)?.source {
                NSWorkspace.shared.open(source)
            }
            return
        }
        select(hit?.id)
    }

    /// Lines up a rectangle with the window's edges and everything else placed.
    private func snap(_ rect: CGRect, edges: Set<PanelEdge>, id: String, tolerance: CGFloat, moving: Bool) -> CGRect {
        let slot = contentBounds
        guard tolerance > 0 else {
            if moving {
                return CGRect(x: min(max(slot.minX, rect.minX), slot.maxX - rect.width),
                              y: min(max(slot.minY, rect.minY), slot.maxY - rect.height),
                              width: rect.width, height: rect.height)
            }
            return rect.intersection(slot)
        }
        let others = draft.root.filter { $0.id != id }.compactMap { frame(of: $0.id) }
        let xs = [slot.minX, slot.maxX] + others.flatMap { [$0.minX, $0.maxX] }
        let ys = [slot.minY, slot.maxY] + others.flatMap { [$0.minY, $0.maxY] }
        func nearest(_ value: CGFloat, _ lines: [CGFloat]) -> CGFloat? {
            lines.min { abs($0 - value) < abs($1 - value) }.flatMap { abs($0 - value) < tolerance ? $0 : nil }
        }
        var rect = rect
        if moving {
            if let x = nearest(rect.minX, xs) { rect.origin.x = x }
            else if let x = nearest(rect.maxX, xs) { rect.origin.x = x - rect.width }
            if let y = nearest(rect.minY, ys) { rect.origin.y = y }
            else if let y = nearest(rect.maxY, ys) { rect.origin.y = y - rect.height }
            rect.origin.x = min(max(slot.minX, rect.minX), slot.maxX - rect.width)
            rect.origin.y = min(max(slot.minY, rect.minY), slot.maxY - rect.height)
        } else {
            if edges.contains(.left), let x = nearest(rect.minX, xs) { rect.size.width += rect.minX - x; rect.origin.x = x }
            if edges.contains(.right), let x = nearest(rect.maxX, xs) { rect.size.width = x - rect.minX }
            if edges.contains(.top), let y = nearest(rect.minY, ys) { rect.size.height += rect.minY - y; rect.origin.y = y }
            if edges.contains(.bottom), let y = nearest(rect.maxY, ys) { rect.size.height = y - rect.minY }
            rect = rect.intersection(slot)
        }
        return rect
    }

    private func setFrame(_ id: String, _ rect: CGRect) {
        draft.update(id) { node in
            var layout = node.layout
            layout.place(rect, in: contentBounds)
            if layout != node.layout { node.layout = layout }
        }
    }

    // MARK: Editing

    private func select(_ id: String?, component: String? = nil) {
        selection = id
        self.component = id.flatMap { draft.node($0)?.type } ?? component
        focus = nil
        part = nil
    }

    private func delete(_ id: String) {
        draft.remove(id)
        if selection.map({ draft.node($0) == nil }) ?? false { selection = nil }
    }

    private func installComponents(_ files: [String]? = nil) {
        do {
            try store.installComponents(named: files)
            store.reloadComponents()
            saveError = nil
        } catch { saveError = error.localizedDescription }
    }

    private func save() {
        guard store.document == original else {
            saveError = "The layout changed in another window. Reopen the editor to use the latest layout."
            return
        }
        do {
            try draft.validate()
            // Rearranged parts go back into their components' files.
            for (type, layout) in layouts.sorted(by: { $0.key < $1.key })
            where layout != store.definition(for: type)?.layout {
                try store.writeLayout(layout, for: type)
            }
            try store.save(draft)
            onClose()
        } catch {
            saveError = error.localizedDescription
        }
    }
}

/// A control generated from a prop declaration.
private struct PropControl: View {
    let spec: PropSpec
    @Binding var value: JSONValue

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            switch spec.kind {
            case .toggle:
                Toggle(spec.label, isOn: Binding(get: { value.bool ?? false }, set: { value = .bool($0) }))
            case .choice(let options):
                Picker(spec.label, selection: Binding(get: { value.string ?? options[0] }, set: { value = .string($0) })) {
                    ForEach(options, id: \.self) { Text($0.capitalized).tag($0) }
                }
            case .text:
                TextField(spec.label, text: Binding(get: { value.string ?? "" }, set: { value = .string($0) }))
                    .textFieldStyle(.roundedBorder)
            case .number(let low, let high, let step):
                Text(spec.label).font(.callout)
                HStack {
                    Slider(value: Binding(get: { value.number ?? low }, set: { value = .number(($0 / step).rounded() * step) }),
                           in: low...max(high, low + step))
                    TextField("", value: Binding(get: { value.number ?? low }, set: { value = .number(min(high, max(low, $0))) }),
                              format: .number)
                        .textFieldStyle(.roundedBorder).frame(width: 60)
                }
            }
        }
    }
}

/// Places views left to right, wrapping onto new rows when they run out of width.
private struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let frames = arrange(subviews, width: proposal.width ?? .infinity)
        let bounds = frames.reduce(CGRect.zero) { $0.union($1) }
        return CGSize(width: proposal.width ?? bounds.width, height: bounds.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (subview, frame) in zip(subviews, arrange(subviews, width: bounds.width)) {
            subview.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                          proposal: ProposedViewSize(frame.size))
        }
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [CGRect] {
        var frames: [CGRect] = []
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width {
                x = 0
                y += row + spacing
                row = 0
            }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            x += size.width + spacing
            row = max(row, size.height)
        }
        return frames
    }
}

/// Something that can be dragged from the strip: the WebView, a component, or a hover area.
private struct PlaceItem: Hashable {
    var type: String
    var role: LayoutNode.Role
}

private enum Interaction: Equatable {
    case place(PlaceItem)
    case move(id: String, item: PlaceItem, grab: CGSize, start: CGRect)
    case resize(id: String, edges: Set<PanelEdge>, start: CGRect)
    /// Dragging the inner edge of a component that fills a gap moves the WebView's edge.
    case resizeGap(webID: String, side: PanelEdge, start: CGRect)
    /// Dragging a new piece into the focused component's layout.
    case placePart(PartLayout)
    /// Dragging a piece of the focused component's layout, by its path.
    case movePart([Int])
    /// A drag that began on nothing draggable.
    case idle

    var isDrag: Bool {
        switch self {
        case .place, .move, .placePart, .movePart: true
        default: false
        }
    }

    var movedPart: [Int]? {
        if case .movePart(let path) = self { path } else { nil }
    }

    var dragged: PlaceItem? {
        switch self {
        case .place(let item), .move(_, let item, _, _): item
        default: nil
        }
    }

    var movedID: String? {
        if case .move(let id, _, _, _) = self { id } else { nil }
    }
}

private enum DropTarget: Equatable {
    case free(CGRect)
    case attach(PanelEdge)
    case slot(SlotAddress, index: Int)
    /// Into a row or column of the focused component's layout. The index leaves out the moved piece.
    case part(container: [Int], index: Int)

    var address: SlotAddress? {
        if case .slot(let address, _) = self { address } else { nil }
    }
}

private enum EditorRegion: Hashable {
    static let space = "AriaLayoutEditor"
    case canvas, item(PlaceItem), disabled(PlaceItem), part(PartLayout)
}

private struct EditorRegionFrames: PreferenceKey {
    static let defaultValue: [EditorRegion: CGRect] = [:]
    static func reduce(value: inout [EditorRegion: CGRect], nextValue: () -> [EditorRegion: CGRect]) {
        value.merge(nextValue()) { _, next in next }
    }
}

private extension View {
    func editorRegion(_ region: EditorRegion) -> some View {
        background {
            GeometryReader { proxy in
                Color.clear.preference(key: EditorRegionFrames.self,
                                       value: [region: proxy.frame(in: .named(EditorRegion.space))])
            }
        }
    }
}
