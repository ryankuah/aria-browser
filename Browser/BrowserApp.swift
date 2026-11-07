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

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Tab") {
                browserCommandActions?.newTab()
            }
            .keyboardShortcut("t", modifiers: [.command])
            .disabled(browserCommandActions == nil)

            Button("Reopen Closed Tab") {
                browserCommandActions?.reopenClosedTab()
            }
            .keyboardShortcut("t", modifiers: [.command, .shift])
            .disabled(browserCommandActions == nil)

            Button("Close Tab") {
                browserCommandActions?.closeTab()
            }
            .keyboardShortcut("w", modifiers: [.command])
            .disabled(browserCommandActions == nil)

            Button("Copy Page Link") {
                browserCommandActions?.copyPageLink()
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])
            .disabled(browserCommandActions == nil)

            Button("Reload Page") {
                browserCommandActions?.reload()
            }
            .keyboardShortcut("r", modifiers: [.command])
            .disabled(browserCommandActions == nil)

            Button("Show History") {
                browserCommandActions?.showHistory()
            }
            .keyboardShortcut("y", modifiers: [.command])
            .disabled(browserCommandActions == nil)
        }

        CommandGroup(after: .appInfo) {
            Button("Show Console") {
                browserCommandActions?.toggleConsole()
            }
            .keyboardShortcut("j", modifiers: [.command, .option])
            .disabled(browserCommandActions == nil)
        }

        CommandMenu("Page") {
            Button("Find in Page") {
                browserCommandActions?.showFind()
            }
            .keyboardShortcut("f", modifiers: [.command])
            .disabled(browserCommandActions == nil)

            Button("Find Next") {
                browserCommandActions?.findNext()
            }
            .keyboardShortcut("g", modifiers: [.command])
            .disabled(browserCommandActions == nil)

            Button("Find Previous") {
                browserCommandActions?.findPrevious()
            }
            .keyboardShortcut("g", modifiers: [.command, .shift])
            .disabled(browserCommandActions == nil)

            Divider()

            Button("Zoom In") {
                browserCommandActions?.zoomIn()
            }
            .keyboardShortcut("+", modifiers: [.command])
            .disabled(browserCommandActions == nil)

            Button("Zoom Out") {
                browserCommandActions?.zoomOut()
            }
            .keyboardShortcut("-", modifiers: [.command])
            .disabled(browserCommandActions == nil)

            Button("Actual Size") {
                browserCommandActions?.resetZoom()
            }
            .keyboardShortcut("0", modifiers: [.command])
            .disabled(browserCommandActions == nil)
        }
    }
}

struct BrowserCommandActions {
    var newTab: () -> Void
    var reopenClosedTab: () -> Void
    var closeTab: () -> Void
    var copyPageLink: () -> Void
    var reload: () -> Void
    var toggleConsole: () -> Void
    var showFind: () -> Void
    var findNext: () -> Void
    var findPrevious: () -> Void
    var showHistory: () -> Void
    var zoomIn: () -> Void
    var zoomOut: () -> Void
    var resetZoom: () -> Void
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
