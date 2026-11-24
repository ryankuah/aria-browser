import SwiftUI
import Carbon

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    override init() {
        super.init()
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURLEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        urls.forEach { BrowserExternalURLRouter.shared.openExternalURL($0) }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        !BrowserExternalURLRouter.shared.focusExistingWindow()
    }

    @objc private func handleGetURLEvent(_ event: NSAppleEventDescriptor, withReplyEvent replyEvent: NSAppleEventDescriptor) {
        guard let urlString = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: urlString) else {
            return
        }

        BrowserExternalURLRouter.shared.openExternalURL(url)
    }
}

@main
struct BrowserApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @ObservedObject private var externalURLRouter = BrowserExternalURLRouter.shared

    var body: some Scene {
        WindowGroup {
            BrowserWindowView(
                externalURLRouter: externalURLRouter
            )
            .background(
                WindowAccessor { window in
                    externalURLRouter.registerApplicationWindow(window)
                }
            )
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            BrowserCommands()
        }
    }
}

private struct BrowserCommands: Commands {
    @FocusedValue(\.browserCommandActions) private var browserCommandActions

    @ObservedObject private var store = LayoutStore.shared

    private func command(_ label: String, _ name: String, requiresPanel: Bool = false) -> some View {
        let shortcut = store.userComponents.lazy.flatMap(\.keys).first {
            $0.action.kind == .command && $0.action.target == name && $0.action.arg == nil
        }?.shortcut.menuShortcut
        let available = !requiresPanel || store.userComponents.contains {
            $0.handles[name] != nil && ($0.opensAs != .placed || store.document.nodes(of: $0.type).contains { $0.role == .view })
        }
        return Button(label) { browserCommandActions?.run(name) }
            .keyboardShortcut(shortcut)
            .disabled(browserCommandActions == nil || !available)
    }

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            command("New Tab", "newTab")
            command("Open Location…", "editAddress", requiresPanel: true)
            command("Reopen Closed Tab", "reopenTab")
            command("Close Tab", "closeTab")
            command("Copy Page Link", "copyLink")
            command("Reload Page", "reload")
            command("Show History", "history")
        }
        CommandGroup(replacing: .appSettings) {
            command("Settings…", "settings")
        }
        CommandGroup(after: .appInfo) {
            command("Show Console", "console", requiresPanel: true)
        }
        CommandGroup(after: .toolbar) {
            Button("Customize Layout…") { browserCommandActions?.customizeLayout() }
                .keyboardShortcut("l", modifiers: [.command, .option])
                .disabled(browserCommandActions == nil)
        }
        CommandMenu("Page") {
            command("Find in Page", "find", requiresPanel: true)
            command("Find Next", "findNext", requiresPanel: true)
            command("Find Previous", "findPrevious", requiresPanel: true)
            Divider()
            command("Zoom In", "zoomIn")
            command("Zoom Out", "zoomOut")
            command("Actual Size", "resetZoom")
        }
    }
}

private extension KeyShortcut {
    var menuShortcut: KeyboardShortcut? {
        guard let character = key.first else { return nil }
        var modifiers: SwiftUI.EventModifiers = []
        if command { modifiers.insert(.command) }
        if shift { modifiers.insert(.shift) }
        if option { modifiers.insert(.option) }
        if control { modifiers.insert(.control) }
        return KeyboardShortcut(KeyEquivalent(character), modifiers: modifiers)
    }
}

struct BrowserCommandActions {
    var customizeLayout: () -> Void
    var run: (String) -> Void
}

private struct BrowserCommandActionsKey: FocusedValueKey {
    typealias Value = BrowserCommandActions
}

extension FocusedValues {
    var browserCommandActions: BrowserCommandActions? {
        get { self[BrowserCommandActionsKey.self] }
        set { self[BrowserCommandActionsKey.self] = newValue }
    }
}
