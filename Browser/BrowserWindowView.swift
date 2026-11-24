import AppKit
import SwiftUI

private struct PanelPointerRegion: NSViewRepresentable {
    let moved: (CGPoint?) -> Void

    func makeNSView(context: Context) -> Tracker { Tracker() }
    func updateNSView(_ view: Tracker, context: Context) { view.moved = moved }

    final class Tracker: NSView {
        var moved: ((CGPoint?) -> Void)?
        override var isFlipped: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(rect: .zero,
                options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow, .inVisibleRect],
                owner: self, userInfo: nil))
        }
        override func mouseEntered(with event: NSEvent) { mouseMoved(with: event) }
        override func mouseMoved(with event: NSEvent) { moved?(convert(event.locationInWindow, from: nil)) }
        override func mouseExited(with event: NSEvent) { moved?(nil) }
    }
}

private struct BrowserContentView: View {
    @ObservedObject var tab: BrowserTab
    @ObservedObject var browser: BrowserState

    let shouldMountWebView: Bool
    let webCornerRadius: CGFloat
    let occlusionRects: [CGRect]
    let onWebViewMounted: () -> Void
    let onRetryFailure: () -> Void

    @ViewBuilder
    var body: some View {
        if let page = BrowserInternalPage.page(for: tab.url) {
            ZStack(alignment: .topLeading) {
                Color.white
                    .allowsHitTesting(false)

                BrowserInternalPageView(
                    page: page,
                    browser: browser,
                    onClose: {
                        browser.closeTab(id: tab.id)
                    }
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: webCornerRadius, style: .continuous))
        } else if let failure = tab.pageFailure {
            ZStack(alignment: .topLeading) {
                Color.white
                    .allowsHitTesting(false)

                BrowserFailureView(
                    failure: failure,
                    onRetry: onRetryFailure
                )
            }
            // The white error surface needs light-mode foreground colors, independently of the browser chrome.
            .environment(\.colorScheme, .light)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: webCornerRadius, style: .continuous))
            .transition(.opacity)
        } else if shouldMountWebView {
            WebView(
                webView: tab.webView,
                cornerRadius: webCornerRadius,
                occlusionRects: occlusionRects,
                onMount: onWebViewMounted
            )
            .id(tab.id)
        } else {
            Color.white
                .clipShape(RoundedRectangle(cornerRadius: webCornerRadius, style: .continuous))
                .allowsHitTesting(false)
        }
    }
}

private struct BrowserInternalPageView: View {
    let page: BrowserInternalPage
    @ObservedObject var browser: BrowserState
    let onClose: () -> Void

    var body: some View {
        switch page {
        case .settings:
            BrowserFullSettingsPage(browser: browser, onClose: onClose)
        case .history:
            BrowserHistoryPage(browser: browser, onClose: onClose)
        }
    }
}

struct BrowserWindowView: View {
    @StateObject private var browser = BrowserState()
    @StateObject private var windowReference = WindowReference()
    @ObservedObject var externalURLRouter: BrowserExternalURLRouter

    @ObservedObject private var layoutStore = LayoutStore.shared
    @ObservedObject private var defaultBrowser = DefaultBrowserController.shared
    @StateObject private var runtime = ComponentRuntime()
    /// Components open because the pointer is over their hover area or over them,
    /// including for a moment after it leaves.
    @State private var hovered: Set<String> = []
    @State private var pendingHoverClose: [String: DispatchWorkItem] = [:]
    @State private var isEditingLayout = false
    @State private var commandKeyMonitor: Any?
    @State private var webViewOcclusionRootRects: [CGRect] = []
    @State private var externalURLRegistrationID: UUID?
    private let topChromeHeight: CGFloat = 6
    private let contentInset: CGFloat = 6
    private let shellCornerRadius: CGFloat = 20
    private var webCornerRadius: CGFloat {
        max(shellCornerRadius - contentInset, 0)
    }

    private var preferredColorScheme: ColorScheme? {
        browser.accentPrefersDarkForeground ? .light : .dark
    }

    private var runtimeState: RuntimeState {
        browser.addonState(isDefaultBrowser: defaultBrowser.isDefaultBrowser, uses: Set(layoutStore.userComponents.flatMap(\.uses)))
    }

    private var componentProps: [String: [String: JSONValue]] {
        Dictionary(uniqueKeysWithValues: layoutStore.userComponents.map {
            ($0.type, $0.resolved(layoutStore.document.props(of: $0.type)))
        })
    }

    private var renderInput: RenderInput {
        RenderInput(sources: layoutStore.sources, props: componentProps, state: runtimeState)
    }

    var body: some View {
        GeometryReader { proxy in
            let isElementFullscreenActive = browser.isElementFullscreenActive
            let bounds = CGRect(x: contentInset, y: topChromeHeight,
                                width: max(0, proxy.size.width - 2 * contentInset),
                                height: max(0, proxy.size.height - topChromeHeight - contentInset))
            let document = layoutStore.document
            let hidden = closedViews(in: document)
            let frames = WindowFrames(document, in: bounds, hidden: hidden) { natural($0) }
            let webRect = isElementFullscreenActive ? bounds : document.webView.flatMap { frames.frames[$0.id] } ?? .zero
            let webOrigin = webRect.origin
            let webSize = webRect.size
            let webRadius = document.props(of: LayoutDocument.webViewType)["cornerRadius"]?.number.map { CGFloat($0) }
                ?? webCornerRadius
            ZStack(alignment: .topLeading) {
                BrowserChromeBackground(
                    bezelStyle: browser.bezelStyle,
                    cornerRadius: shellCornerRadius,
                    effect: .liquidGlass(style: .clear),
                    accentColor: browser.accentNSColor
                )
                    .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
                    .allowsHitTesting(false)

                Group {
                    if let activeTab = browser.activeTab {
                        BrowserContentView(
                            tab: activeTab,
                            browser: browser,
                            shouldMountWebView: browser.shouldMountWebView(for: activeTab),
                            webCornerRadius: webRadius,
                            occlusionRects: isElementFullscreenActive ? [] : webViewOcclusionRects(
                                rootRects: webViewOcclusionRootRects,
                                webOrigin: webOrigin,
                                webSize: webSize
                            ),
                            onWebViewMounted: {
                                browser.webViewDidMount(for: activeTab.id)
                            },
                            onRetryFailure: {
                                browser.retryActivePageFailure()
                            }
                        )
                        .id(activeTab.id)
                    } else {
                        Color.white
                    }
                }
                .frame(width: webSize.width, height: webSize.height, alignment: .topLeading)
                .offset(x: webOrigin.x, y: webOrigin.y)

                if !isElementFullscreenActive {
                    // The window frame: it moves the window, and shows when the page is loading.
                    WindowDragHandle()
                        .frame(width: proxy.size.width, height: topChromeHeight)
                        .contentShape(Rectangle())

                    if browser.activeTab?.isLoading == true {
                        LoadingBezelPill()
                            .frame(width: proxy.size.width, height: topChromeHeight)
                            .allowsHitTesting(false)
                            .transition(.opacity)
                    }

                    LayoutWindowView(document: document, frames: frames, size: proxy.size,
                                     environment: layoutEnvironment(isPreview: false), hidden: hidden,
                                     occludesWebView: true)
                        .zIndex(1)

                    let overlays = overlayComponents
                    if !overlays.isEmpty {
                        overlayLayer(overlays, size: proxy.size)
                            .zIndex(3)
                    }

                    PanelPointerRegion { point in
                        trackPointer(point, frames: frames, bounds: bounds, size: proxy.size)
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .zIndex(1)
                }

                if isEditingLayout {
                    LayoutEditor(
                        store: layoutStore, windowSize: proxy.size, contentBounds: bounds,
                        tab: browser.activeTab, state: runtimeState,
                        environment: layoutEnvironment(isPreview: true),
                        windowBackground: AnyView(
                            BrowserChromeBackground(bezelStyle: browser.bezelStyle, cornerRadius: shellCornerRadius,
                                                    effect: .material, accentColor: browser.accentNSColor)
                        ),
                        onClose: { isEditingLayout = false }
                    )
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipShape(RoundedRectangle(cornerRadius: shellCornerRadius, style: .continuous))
                    .webViewOcclusionRegion()
                    .zIndex(20)
                }

                // Camera, microphone and password prompts. Aria keeps these so no component can answer them.
                BrowserToastStack(browser: browser)
                    .frame(width: min(max(proxy.size.width - 32, 0), 320), alignment: .topTrailing)
                    .offset(
                        x: webOrigin.x + max(webSize.width - min(max(proxy.size.width - 32, 0), 320) - 12, 0),
                        y: webOrigin.y + 12
                    )
                    .zIndex(5)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .coordinateSpace(name: BrowserWindowCoordinateSpace.root)
            .onPreferenceChange(WebViewOcclusionPreferenceKey.self) { rects in
                webViewOcclusionRootRects = rects
            }
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 0.16), value: runtime.toggled)
            .animation(.easeInOut(duration: 0.16), value: browser.bezelStyle)
            .animation(.easeInOut(duration: 0.16), value: browser.accentColorHex)
            .animation(.spring(response: 0.24, dampingFraction: 0.86), value: browser.toasts)
            .onChange(of: openComponents) { before, after in componentsChanged(from: before, to: after) }
        }
        .ignoresSafeArea()
        .preferredColorScheme(preferredColorScheme)
        .background(
            WindowAccessor { window in
                WindowAccessor.configureBrowserWindow(
                    window,
                    bezelStyle: browser.bezelStyle,
                    accentColor: browser.accentNSColor
                )
                windowReference.update(window)
                externalURLRegistrationID = externalURLRouter.register(
                    browser: browser,
                    window: window,
                    existingID: externalURLRegistrationID
                )
            }
        )
        // Menu commands go through components first, so one can take them over.
        .focusedSceneValue(\.browserCommandActions, BrowserCommandActions(
            customizeLayout: { isEditingLayout = true },
            run: { runCommand($0) }
        ))
        .task(id: renderInput) { [input = renderInput] in await runtime.update(input) }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            layoutStore.reloadComponents()
            defaultBrowser.refresh()
        }
        .onAppear {
            defaultBrowser.refresh()
            installCommandKeyMonitorIfNeeded()
        }
        .onChange(of: browser.isElementFullscreenActive) { _, isActive in
            guard isActive else {
                return
            }

            clearHover()
            webViewOcclusionRootRects = []
        }
        .onDisappear {
            externalURLRouter.unregister(id: externalURLRegistrationID)
            externalURLRegistrationID = nil
            removeCommandKeyMonitor()
        }
    }

    /// Open overlay components over the window, behind whatever their files ask for.
    private func overlayLayer(_ overlays: [ComponentDefinition], size: CGSize) -> some View {
        let scrim = overlays.last { !$0.clickThrough && $0.scrim != "none" }?.scrim ?? "none"
        let top = overlays.contains { $0.overlayAlign == "top" }
        return ZStack(alignment: top ? .top : .center) {
            if scrim != "none" {
                (scrim == "accent" ? Color(nsColor: browser.accentNSColor).opacity(0.24) : Color.black.opacity(0.18))
                    .contentShape(Rectangle())
                    .webViewOcclusionRegion()
                    .onTapGesture { overlays.forEach { runtime.close($0.type) } }
            }
            VStack(spacing: 12) {
                ForEach(overlays) { definition in
                    sizedComponent(definition)
                        .allowsHitTesting(!definition.clickThrough)
                        .modifier(OcclusionModifier(enabled: !definition.clickThrough))
                        .shadow(color: .black.opacity(0.22), radius: 14, y: 7)
                        .transition(ComponentMotion.transition(definition, edge: definition.slideFrom ?? .top))
                }
            }
            .padding(.top, top ? max(72, size.height * 0.3) : 0)
        }
        .frame(width: size.width, height: size.height, alignment: top ? .top : .center)
        .transition(.opacity)
    }

    private func installCommandKeyMonitorIfNeeded() {
        guard commandKeyMonitor == nil else {
            return
        }

        // Keys come from component files: their `keys`, and their shortcut() activators.
        commandKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard windowReference.window?.isKeyWindow == true, !isEditingLayout else {
                return event
            }

            let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
            // Esc closes components opened by a button, shortcut or command.
            if modifiers.isEmpty && event.keyCode == 53 && !runtime.toggled.isEmpty {
                runtime.closeAll()
                return nil
            }

            for definition in layoutStore.userComponents {
                if let binding = definition.keys.first(where: { $0.shortcut.matches(event) }) {
                    perform(binding.action, in: definition.type, opener: "keys", event: nil)
                    return nil
                }
                for activator in definition.activators where activator.kind == .shortcut {
                    if let shortcut = KeyShortcut(activator.keys ?? ""), shortcut.matches(event) {
                        runtime.toggle(definition.type)
                        return nil
                    }
                }
            }
            return event
        }
    }

    private func removeCommandKeyMonitor() {
        guard let commandKeyMonitor else {
            return
        }

        NSEvent.removeMonitor(commandKeyMonitor)
        self.commandKeyMonitor = nil
    }

    private func openInternalPage(_ page: BrowserInternalPage) {
        runtime.closeAll()
        browser.openInternalPage(page)
    }

    // MARK: Components

    private func natural(_ node: LayoutNode) -> CGSize {
        layoutStore.definition(for: node.type)?.natural(node.role) ?? CGSize(width: 240, height: 200)
    }

    /// Whether a component is open: always, by its button or shortcut, by a when() rule,
    /// while the pointer is over its hover area or over it, or while something it opened is.
    private func isOpen(_ name: String) -> Bool {
        guard runtime.trees[name] != nil, let definition = layoutStore.definition(for: name), definition.opensAs != .nowhere else { return false }
        return definition.alwaysOpen || runtime.toggled.contains(name) || runtime.conditions[name] == true
            || hovered.contains(name) || runtime.parents.values.contains(name)
            || runtime.holds.values.contains(name)
    }

    /// Every component that is open right now.
    private var openComponents: Set<String> {
        Set(layoutStore.userComponents.map(\.type).filter(isOpen))
    }

    /// Runs components' onOpen and onClose, and puts closed components back to their starting state.
    private func componentsChanged(from before: Set<String>, to after: Set<String>) {
        for name in after.subtracting(before) {
            if let hook = layoutStore.definition(for: name)?.onOpen { perform(hook, in: name, opener: "onOpen", event: nil) }
        }
        for name in before.subtracting(after) {
            runtime.resetLocal(name)
            if let hook = layoutStore.definition(for: name)?.onClose { perform(hook, in: name, opener: "onClose", event: nil) }
            // Panels opened inside a component's slots close with it.
            for node in layoutStore.document.root where node.type == name {
                for child in node.flattened.dropFirst() where runtime.toggled.contains(child.type) {
                    runtime.close(child.type)
                }
            }
        }
    }

    /// Placed views of components that are closed, or no longer appear where they were placed.
    private func closedViews(in document: LayoutDocument) -> Set<String> {
        Set(document.root.filter { node in
            guard node.role == .view, node.type != LayoutDocument.webViewType else { return false }
            return layoutStore.definition(for: node.type)?.opensAs != .placed || !isOpen(node.type)
        }.map(\.id))
    }

    /// Open overlay components, shown over the middle of the window.
    private var overlayComponents: [ComponentDefinition] {
        layoutStore.userComponents.filter { $0.opensAs == .overlay && isOpen($0.type) }
    }

    private func sizedComponent(_ definition: ComponentDefinition) -> some View {
        ComponentView(node: LayoutNode(id: "overlay-\(definition.type)", type: definition.type), host: definition.type,
                      axis: .vertical, fills: definition.height != nil, environment: layoutEnvironment(isPreview: false))
            .frame(width: definition.width, height: definition.height)
            .fixedSize(horizontal: definition.width == nil, vertical: definition.height == nil)
    }

    /// Runs an action from `component`. `event` is what happened, like the text typed.
    private func perform(_ action: PieceAction, in component: String, opener: String, event: AnyJSON?, handled: Set<String> = []) {
        let name = action.target.isEmpty ? component : action.target
        // A component opened from inside another keeps that one open until it closes.
        let parent = component.isEmpty || name == component ? nil : component
        switch action.kind {
        case .open, .toggle:
            guard layoutStore.definition(for: name) != nil else {
                runtime.report(component, "There’s no component called \(name).")
                return
            }
            if action.kind == .open { runtime.open(name, in: parent) }
            else { runtime.toggle(name, in: parent) }
        case .close:
            runtime.close(name)
        case .command:
            runCommand(action.target, action.arg ?? event, from: component, handled: handled)
        case .openTab:
            _ = browser.openNewTab(from: action.target.isEmpty ? event?.string ?? "" : action.target)
        case .navigate:
            _ = browser.navigateAddress(action.target.isEmpty ? event?.string ?? "" : action.target)
        case .set:
            guard !component.isEmpty else { return }
            runtime.setLocal(component, action.target, action.arg ?? event)
        case .fn:
            Task {
                for next in await runtime.call(component, action, event: event) where next.kind != .fn {
                    perform(next, in: component, opener: opener, event: nil, handled: handled)
                }
            }
        }
    }

    /// Runs a command. A component that `handles` it runs instead, unless that component
    /// is the one asking: then Aria does it, so a component can take over a command and
    /// still use it.
    private func runCommand(_ command: String, _ arg: AnyJSON? = nil, from component: String = "", handled: Set<String> = []) {
        if !handled.contains(command),
           layoutStore.definition(for: component)?.handles[command] == nil,
           let handler = layoutStore.userComponents.first(where: { $0.type != component && $0.handles[command] != nil }),
           let action = handler.handles[command] {
            perform(action, in: handler.type, opener: "handles", event: arg, handled: handled.union([command]))
            return
        }
        switch command {
        case "history": openInternalPage(.history)
        case "settings": openInternalPage(.settings)
        case "customize": isEditingLayout = true
        default:
            if !browser.runAddonCommand(command, arg, defaultBrowser: defaultBrowser) {
                runtime.report(component.isEmpty ? "engine" : component, "Unknown command \"\(command)\".")
            }
        }
    }

    private func layoutEnvironment(isPreview: Bool) -> LayoutEnvironment {
        LayoutEnvironment(
            definition: { layoutStore.definition(for: $0) },
            props: componentProps,
            trees: runtime.trees,
            errors: runtime.errors,
            isPreview: isPreview,
            builtIn: { kind, _ in AnyView(builtInPiece(kind)) },
            background: { style, radius, corners in
                AnyView(containerBackground(style, radius: radius, corners: corners, isPreview: isPreview))
            },
            perform: { action, component, opener, event in perform(action, in: component, opener: opener, event: event) },
            isActive: { action in action.kind == .toggle && !action.target.isEmpty && isOpen(action.target) },
            hold: { button, host in runtime.hold(button, host: host) },
            isOpen: { isOpen($0) },
            local: Dictionary(uniqueKeysWithValues: layoutStore.userComponents.map { ($0.type, runtime.localState($0.type)) }),
            setLocal: { name, key, value in runtime.setLocal(name, key, value) },
            favicon: { browser.addonFavicon($0) },
            suggest: { browser.addressSuggestions($0) },
            accent: Color(nsColor: browser.accentNSColor)
        )
    }

    /// The pieces only Aria can draw.
    @ViewBuilder
    private func builtInPiece(_ kind: String) -> some View {
        if kind == "windowControls" {
            TrafficLightControls(window: windowReference.window)
        }
    }

    @ViewBuilder
    private func containerBackground(_ style: String, radius: CGFloat, corners: String, isPreview: Bool) -> some View {
        if style == "solid" {
            ComponentShape(radius: radius, corners: corners).fill(Color(nsColor: browser.accentNSColor))
        } else {
            // The editor's scaled preview avoids AppKit-backed glass.
            BrowserChromeBackground(
                bezelStyle: browser.bezelStyle,
                cornerRadius: radius,
                maskedCorners: Self.cornerMask(corners),
                effect: isPreview ? .material : .liquidGlass(style: .regular,
                                                             tintColor: NSColor.black.withAlphaComponent(0.06)),
                accentColor: browser.accentNSColor
            )
        }
    }

    private static func cornerMask(_ corners: String) -> CACornerMask {
        switch corners {
        case "left": [.layerMinXMinYCorner, .layerMinXMaxYCorner]
        case "right": [.layerMaxXMinYCorner, .layerMaxXMaxYCorner]
        case "top": [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        case "bottom": [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        default: [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        }
    }

    /// Opens components whose hover area or open view the pointer is over. They close a
    /// moment after it leaves, so crossing a gap doesn't close them. Hover areas on the edge
    /// of the content reach the window's edge, so flinging the pointer there opens them.
    private func trackPointer(_ point: CGPoint?, frames: WindowFrames, bounds: CGRect, size: CGSize) {
        var inside = Set<String>()
        if let point {
            for node in layoutStore.document.root {
                guard var rect = frames.frames[node.id] else { continue }
                switch node.role {
                case .hover:
                    if rect.minX <= bounds.minX + 0.5 { rect = CGRect(x: 0, y: rect.minY, width: rect.maxX, height: rect.height) }
                    if rect.maxX >= bounds.maxX - 0.5 { rect.size.width = size.width - rect.minX }
                    if rect.minY <= bounds.minY + 0.5 { rect = CGRect(x: rect.minX, y: 0, width: rect.width, height: rect.maxY) }
                    if rect.maxY >= bounds.maxY - 0.5 { rect.size.height = size.height - rect.minY }
                    if rect.contains(point) { inside.insert(node.type) }
                // A closed component still has a frame, but the pointer can't be inside it.
                case .view where layoutStore.definition(for: node.type)?.activator(.hover) != nil && isOpen(node.type):
                    if rect.contains(point) { inside.insert(node.type) }
                default:
                    break
                }
            }
        }
        for name in inside {
            pendingHoverClose.removeValue(forKey: name)?.cancel()
            if !hovered.contains(name) { hovered.insert(name) }
        }
        for name in hovered.subtracting(inside) where pendingHoverClose[name] == nil {
            let delay = layoutStore.definition(for: name)?.activator(.hover)?.closeDelay ?? 0.1
            let work = DispatchWorkItem {
                pendingHoverClose[name] = nil
                hovered.remove(name)
            }
            pendingHoverClose[name] = work
            DispatchQueue.main.asyncAfter(deadline: .now() + min(3600, max(0, delay)), execute: work)
        }
    }

    private func clearHover() {
        pendingHoverClose.values.forEach { $0.cancel() }
        pendingHoverClose = [:]
        hovered = []
    }

    private func webViewOcclusionRects(rootRects: [CGRect], webOrigin: CGPoint, webSize: CGSize) -> [CGRect] {
        let webRect = CGRect(origin: webOrigin, size: webSize)

        return rootRects.compactMap { rootRect in
            let intersection = rootRect.intersection(webRect)
            guard !intersection.isNull,
                  intersection.width > 0,
                  intersection.height > 0 else {
                return nil
            }

            return CGRect(
                x: intersection.minX - webOrigin.x,
                y: intersection.minY - webOrigin.y,
                width: intersection.width,
                height: intersection.height
            )
        }
    }
}
