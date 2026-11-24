import SwiftUI

struct PanelLayoutEditor: View {
    @ObservedObject var store: PanelLayoutStore
    @ObservedObject var runtime: PanelVisibility
    let windowSize: CGSize
    let tab: BrowserTab?
    @Environment(\.dismiss) private var dismiss
    @State private var draft: PanelLayout
    @State private var selected: PanelComponent = .tabs
    @State private var mode: PanelMode = .docked
    @State private var target: PanelEdge?
    @State private var dragging: PanelComponent?
    @State private var hitRegions: [EditorRegion: CGRect] = [:]
    @State private var snapshot: NSImage?
    @State private var saveError: String?
    @State private var original: PanelLayout

    init(store: PanelLayoutStore, runtime: PanelVisibility, windowSize: CGSize, tab: BrowserTab?) {
        self.store = store
        self.runtime = runtime
        self.windowSize = windowSize
        self.tab = tab
        _original = State(initialValue: store.layout)
        _draft = State(initialValue: store.layout)
    }

    private var preview: PanelLayout {
        var layout = draft
        if let target { layout.place(selected, edge: target, mode: mode) }
        return layout
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Customize Layout").font(.title2.bold())
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save Layout", action: save).keyboardShortcut(.defaultAction)
            }.padding(16)
            Divider()
            HStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Components").font(.headline)
                        ForEach(PanelComponent.allCases) { item in
                            Button { selected = item } label: {
                                HStack {
                                    Label(item.title, systemImage: item.icon)
                                    Spacer()
                                    Image(systemName: "line.3.horizontal").foregroundStyle(.secondary)
                                }
                                .padding(7)
                                .background(selected == item ? Color.accentColor.opacity(0.18) : .clear,
                                            in: RoundedRectangle(cornerRadius: 6))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .editorRegion(.library(item))
                        }
                        Divider()
                        inspector
                        Divider()
                        Button("Open Scripts Folder") { NSWorkspace.shared.open(store.scriptsURL) }
                        Button("Reload Scripts") { store.reloadScripts() }
                    }.padding(14)
                }.frame(width: 218)
                Divider()
                VStack(spacing: 12) {
                    Picker("Placement", selection: $mode) {
                        Text("Docked").tag(PanelMode.docked)
                        Text("Overlay").tag(PanelMode.overlay)
                    }.pickerStyle(.segmented).frame(maxWidth: 240)
                    targetButton(.top)
                    HStack(spacing: 5) {
                        targetButton(.left)
                        GeometryReader { proxy in
                            canvas(in: proxy.size)
                        }
                        targetButton(.right)
                    }
                    targetButton(.bottom)
                    Text("Drag a component to an edge, or select it and click an edge.")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(14)
            }
            if let message = saveError ?? store.fileError ?? store.scriptReadError ?? runtime.errors.sorted(by: { $0.key < $1.key })
                .map({ "\($0.key): \($0.value)" }).first {
                Divider()
                Text(message).font(.caption).textSelection(.enabled).padding(8)
            }
        }
        .frame(width: min(900, (NSScreen.main?.visibleFrame.width ?? 940) - 40),
               height: min(550, (NSScreen.main?.visibleFrame.height ?? 650) - 100))
        .coordinateSpace(name: EditorRegion.space)
        .onPreferenceChange(EditorRegionFrames.self) { hitRegions = $0 }
        .simultaneousGesture(componentDrag)
        .task {
            if let tab, BrowserInternalPage.page(for: tab.url) == nil {
                snapshot = try? await tab.webView.takeSnapshot(configuration: nil)
            }
        }
    }

    @ViewBuilder private var inspector: some View {
        if let index = draft.panels.firstIndex(where: { $0.components.contains(selected) }) {
            let panel = draft.panels[index]
            Text("\(panel.edge.rawValue.capitalized) \(panel.mode.rawValue) panel").font(.headline)
            Text("\(panel.edge.vertical ? "Width" : "Height") · \(Int(panel.size)) pt").font(.caption)
            Slider(value: $draft.panels[index].size, in: (panel.edge.vertical ? 160.0 : 48.0)...640.0, step: 4)
                .accessibilityLabel(panel.edge.vertical ? "Panel width" : "Panel height")
            Picker("Visibility", selection: $draft.panels[index].visibility) {
                ForEach(Set(store.scripts.keys).union([panel.visibility]).sorted(), id: \.self) { file in
                    Text(file).tag(file)
                }
            }
            let position = panel.components.firstIndex(of: selected) ?? 0
            HStack {
                Button("Earlier") { draft.panels[index].components.swapAt(position, position - 1) }
                    .disabled(position == 0)
                Button("Later") { draft.panels[index].components.swapAt(position, position + 1) }
                    .disabled(position + 1 >= panel.components.count)
            }
            Button("Remove from Layout") { draft.remove(selected) }
        }
    }

    private func canvas(in available: CGSize) -> some View {
        let scale = min(available.width / max(1, windowSize.width), available.height / max(1, windowSize.height))
        let size = CGSize(width: windowSize.width * scale, height: windowSize.height * scale)
        let frames = PanelFrames(in: CGRect(origin: .zero, size: windowSize), panels: preview.panels)
        return ZStack(alignment: .topLeading) {
            ZStack {
                Color(nsColor: .textBackgroundColor)
                if let snapshot { Image(nsImage: snapshot).resizable().scaledToFill() }
                Label("Webpage", systemImage: "globe")
                    .padding(6).background(.regularMaterial, in: Capsule())
            }
            .frame(width: frames.webpage.width * scale, height: frames.webpage.height * scale)
            .clipped()
            .offset(x: frames.webpage.minX * scale, y: frames.webpage.minY * scale)
            ForEach(preview.panels) { panel in
                if let rect = frames.panels[panel.id] {
                    let stack = panel.edge.vertical ? AnyLayout(VStackLayout(spacing: 2)) : AnyLayout(HStackLayout(spacing: 2))
                    stack {
                        ForEach(panel.components) { item in
                            Button { selected = item } label: {
                                ViewThatFits {
                                    Label(item.title, systemImage: item.icon)
                                    Image(systemName: item.icon)
                                }
                                .font(.caption)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(selected == item ? Color.accentColor.opacity(0.3) : Color.secondary.opacity(0.09))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain).help(item.title)
                            .editorRegion(.component(item))
                        }
                    }
                    .frame(width: rect.width * scale, height: rect.height * scale)
                    .background(.regularMaterial)
                    .clipped()
                    .border(panel.mode == .overlay ? Color.accentColor : Color.secondary.opacity(0.55))
                    .offset(x: rect.minX * scale, y: rect.minY * scale)
                }
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(.secondary.opacity(0.5)) }
        .editorRegion(.canvas)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func targetButton(_ edge: PanelEdge) -> some View {
        Button(edge.rawValue.capitalized) {
            draft.place(selected, edge: edge, mode: mode)
        }
        .buttonStyle(.bordered)
        .tint(target == edge ? .accentColor : .secondary)
        .help("Place \(selected.title) in the \(edge.rawValue) \(mode.rawValue) panel")
        .editorRegion(.edge(edge))
    }

    private var componentDrag: some Gesture {
        DragGesture(minimumDistance: 5, coordinateSpace: .named(EditorRegion.space))
            .onChanged { value in
                if dragging == nil {
                    dragging = component(at: value.startLocation)
                }
                guard let dragging else { return }
                selected = dragging
                target = destination(at: value.location)
            }
            .onEnded { value in
                if let dragging, let edge = destination(at: value.location) {
                    draft.place(dragging, edge: edge, mode: mode)
                }
                dragging = nil
                target = nil
            }
    }

    private func component(at point: CGPoint) -> PanelComponent? {
        PanelComponent.allCases.first {
            hitRegions[.library($0)]?.contains(point) == true || hitRegions[.component($0)]?.contains(point) == true
        }
    }

    private func destination(at point: CGPoint) -> PanelEdge? {
        if let button = PanelEdge.allCases.first(where: { hitRegions[.edge($0)]?.contains(point) == true }) {
            return button
        }
        guard let canvas = hitRegions[.canvas], canvas.contains(point) else { return nil }
        let x = (point.x - canvas.minX) / max(1, canvas.width)
        let y = (point.y - canvas.minY) / max(1, canvas.height)
        let distances: [(PanelEdge, CGFloat)] = [(.left, x), (.right, 1 - x), (.top, y), (.bottom, 1 - y)]
        return distances.min { $0.1 < $1.1 }?.0
    }

    private func save() {
        guard store.layout == original else {
            saveError = "The layout changed in another window. Reopen the editor to use the latest layout."
            return
        }
        do { try store.save(draft); dismiss() }
        catch { saveError = error.localizedDescription }
    }
}

private enum EditorRegion: Hashable {
    static let space = "AriaLayoutEditor"
    case canvas, library(PanelComponent), component(PanelComponent), edge(PanelEdge)
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
