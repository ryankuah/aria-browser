import AppKit
import SwiftUI

struct BrowserSidebar: View {
    @ObservedObject var browser: BrowserState
    @Binding var isSettingsPresented: Bool
    let panel: LayoutPanel
    @Binding var draggedTabID: BrowserTab.ID?
    @Binding var dimmedTabID: BrowserTab.ID?
    let window: NSWindow?
    let cornerRadius: CGFloat
    let onOpenFullSettings: () -> Void
    let onOpenAddressPrompt: () -> Void
    let onOpenHistory: () -> Void

    @State private var isDownloadsPresented = false

    var body: some View {
        let stack = panel.edge.vertical
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(spacing: 10))
        stack {
            ForEach(panel.components) { component in
                switch component {
                case .navigation:
                    headerControls
                case .address:
                    activePageControls
                case .bookmarks:
                    bookmarkSection
                case .tabs:
                    SidebarTabList(browser: browser, draggedTabID: $draggedTabID, dimmedTabID: $dimmedTabID,
                                   horizontal: !panel.edge.vertical)
                case .tools:
                    DownloadsFooter(
                        browser: browser,
                        isPresented: $isDownloadsPresented,
                        isSettingsPresented: $isSettingsPresented,
                        usesPopovers: !panel.edge.vertical,
                        onOpenFullSettings: onOpenFullSettings,
                        onOpenHistory: onOpenHistory
                    )
                    .padding(.horizontal, 10)
                }
            }
        }
        .padding(.vertical, panel.edge.vertical ? 12 : 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: panel.edge.vertical ? .topLeading : .leading)
        .background {
            BrowserChromeBackground(
                bezelStyle: browser.bezelStyle,
                cornerRadius: cornerRadius,
                effect: .liquidGlass(
                    style: .regular,
                    tintColor: NSColor.black.withAlphaComponent(0.06)
                ),
                accentColor: browser.accentNSColor
            )
            .allowsHitTesting(false)
        }
        .contentShape(Rectangle())
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(.white.opacity(0.18))
                .frame(width: 1)
                .allowsHitTesting(false)
        }
        .onDisappear {
            isDownloadsPresented = false
            if panel.components.contains(.tools) { isSettingsPresented = false }
        }
    }

    private var headerControls: some View {
        HStack(spacing: 8) {
            TrafficLightControls(window: window)

            SidebarIconButton(systemName: "chevron.left", label: "Back") {
                browser.goBack()
            }
            .disabled(!(browser.activeTab?.canGoBack ?? false))

            SidebarIconButton(systemName: "chevron.right", label: "Forward") {
                browser.goForward()
            }
            .disabled(!(browser.activeTab?.canGoForward ?? false))

            SidebarIconButton(
                systemName: browser.activeTab?.isLoading == true ? "xmark" : "arrow.clockwise",
                label: browser.activeTab?.isLoading == true ? "Stop" : "Reload"
            ) {
                browser.reloadOrStop()
            }
            .disabled(browser.activeTab == nil)

            if panel.edge.vertical { Spacer() }
        }
        .padding(.horizontal, 16)

    }

    @ViewBuilder
    private var activePageControls: some View {
        BrowserControls(
            tab: browser.activeTab,
            onOpenAddressPrompt: onOpenAddressPrompt
        )
        .id(browser.activeTab?.id)
    }

    @ViewBuilder
    private var bookmarkSection: some View {
        if !browser.bookmarks.isEmpty || draggedTabID != nil {
            BookmarkShelf(
                browser: browser,
                draggedTabID: $draggedTabID,
                dimmedTabID: $dimmedTabID
            )
            .padding(.horizontal, 10)
        }
    }
}

struct SidebarIconButton: View {
    let systemName: String
    let label: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .background {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isHovered ? .primary.opacity(0.06) : Color.clear)
        }
        .onHover { isHovered in
            self.isHovered = isHovered
        }
        .cursor(.pointingHand)
        .accessibilityLabel(label)
        .help(label)
    }
}
