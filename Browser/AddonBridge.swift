import AppKit
import SwiftUI

// What component files can see of the browser, and what they can ask it to do.
// Aria draws no chrome of its own: every button, list and panel is a component
// file reading this state and running these commands.

// MARK: State

extension BrowserState {
    /// The state component files read. `isDefaultBrowser` comes from macOS, which
    /// answers separately.
    func addonState(isDefaultBrowser: Bool, uses: Set<String>) -> RuntimeState {
        let tab = activeTab
        var base: [String: AnyJSON] = [
            "tabCount": AnyJSON(tabs.count),
            "activeDownloadCount": AnyJSON(downloads.filter { $0.status == .inProgress }.count),
            "hasPage": AnyJSON(tab != nil),
            "canGoBack": AnyJSON(tab?.canGoBack ?? false),
            "canGoForward": AnyJSON(tab?.canGoForward ?? false),
            "isLoading": AnyJSON(tab?.isLoading ?? false),
            "url": AnyJSON(tab?.addressText ?? ""),
            "host": AnyJSON(tab?.url?.host ?? ""),
            "title": AnyJSON(tab?.displayTitle ?? ""),
            "isFullscreen": AnyJSON(isElementFullscreenActive),
        ]
        base["appearance"] = ["dark": AnyJSON(!accentPrefersDarkForeground), "accent": AnyJSON(accentColorHex)]

        var sections: [String: AnyJSON] = [:]
        if uses.contains("tabs") {
            sections["tabs"] = .array(visibleTabs.map { tab in
                [
                    "id": AnyJSON(tab.id.uuidString),
                    "title": AnyJSON(tab.displayTitle),
                    "url": AnyJSON(tab.addressText),
                    "host": AnyJSON(tab.url?.host ?? ""),
                    "subtitle": AnyJSON(tab.displaySubtitle),
                    "isActive": AnyJSON(tab.id == selectedTabID),
                    "isLoading": AnyJSON(tab.isLoading),
                    "isAudible": AnyJSON(tab.isPlayingAudio),
                    "isMuted": AnyJSON(tab.isMuted),
                    "isBookmarked": AnyJSON(isTabBookmarked(id: tab.id)),
                    "favicon": AnyJSON("tab:\(tab.id.uuidString)"),
                ]
            })
        }
        if uses.contains("bookmarks") {
            sections["bookmarks"] = .array(bookmarks.map { bookmark in
                [
                    "id": AnyJSON(bookmark.id.uuidString),
                    "title": AnyJSON(bookmark.displayTitle),
                    "url": AnyJSON(bookmark.url.absoluteString),
                    "host": AnyJSON(bookmark.url.host ?? ""),
                    "tabId": AnyJSON(bookmark.tabID?.uuidString),
                    "isOpen": AnyJSON(bookmark.tabID != nil),
                    "isActive": AnyJSON(isBookmarkActive(id: bookmark.id)),
                    "favicon": AnyJSON("bookmark:\(bookmark.id.uuidString)"),
                ]
            })
        }
        if uses.contains("downloads") {
            sections["downloads"] = .array(downloads.map { download in
                [
                    "id": AnyJSON(download.id.uuidString),
                    "name": AnyJSON(download.displayName),
                    "status": AnyJSON(Self.addonStatus(download.status)),
                    "receivedBytes": AnyJSON(Double(download.receivedBytes)),
                    "expectedBytes": AnyJSON(download.expectedBytes.map(Double.init)),
                    "speedBytesPerSecond": AnyJSON(download.speedBytesPerSecond.map(Double.init)),
                    "progress": AnyJSON(download.progressFraction.map { ($0 * 100).rounded() / 100 }),
                    "detail": AnyJSON(download.detailText),
                    "canCancel": AnyJSON(download.canCancel),
                    "canRetry": AnyJSON(download.canRetry),
                    "source": AnyJSON(download.sourceURL?.absoluteString),
                ]
            })
        }
        if uses.contains("page") {
            let permissions = activeMediaPermissionSnapshot
            sections["page"] = [
                "zoom": AnyJSON(Double(tab?.pageZoom ?? 1)),
                "zoomText": AnyJSON(tab?.pageZoomPercentText ?? "100%"),
                // Set briefly after the zoom changes, for a component that shows it.
                "zoomFlash": AnyJSON(zoomHUD?.percentText),
                "security": AnyJSON(Self.addonSecurity(tab?.originSecurityState ?? .noPage)),
                "securityLabel": AnyJSON((tab?.originSecurityState ?? .noPage).accessibilityLabel),
                "securityIcon": AnyJSON((tab?.originSecurityState ?? .noPage).iconSystemName),
                "canSetPermissions": AnyJSON(permissions.hasActivePage),
                "camera": AnyJSON(permissions.isCameraAllowed),
                "microphone": AnyJSON(permissions.isMicrophoneAllowed),
                "find": ["query": AnyJSON(findQuery), "matched": findMatched.map(AnyJSON.bool) ?? .null],
                "failed": AnyJSON(tab?.pageFailure != nil),
            ]
        }
        if uses.contains("settings") {
            sections["settings"] = [
                "bezelStyle": AnyJSON(bezelStyle.rawValue),
                "bezelStyles": .array(BrowserBezelStyle.availableCases.map { ["id": AnyJSON($0.rawValue), "label": AnyJSON($0.label)] }),
                "searchEngine": AnyJSON(searchEngine.rawValue),
                "searchEngines": .array(BrowserSearchEngine.allCases.map { ["id": AnyJSON($0.rawValue), "label": AnyJSON($0.label)] }),
                "passwordAutofill": AnyJSON(isPasswordAutofillEnabled),
                "passwordSavePrompt": AnyJSON(isPasswordSavePromptEnabled),
                "removeQuarantine": AnyJSON(isDownloadQuarantineRemovalEnabled),
                "isDefaultBrowser": AnyJSON(isDefaultBrowser),
                "downloadsFolder": AnyJSON(downloadsDirectoryDisplayPath),
                "scriptsFolder": AnyJSON(userScriptsDirectoryDisplayPath),
            ]
        }
        if uses.contains("scripts") {
            sections["scripts"] = .array(userScripts.map { script in
                var entry: [String: AnyJSON] = [
                    "id": AnyJSON(script.id),
                    "name": AnyJSON(script.displayName),
                    "enabled": AnyJSON(script.isEnabled),
                ]
                if let item = script.sidebarItem {
                    entry["button"] = ["icon": AnyJSON(item.systemName), "label": AnyJSON(item.label)]
                }
                return .object(entry)
            })
        }
        if uses.contains("console") {
            sections["console"] = .array(consoleMessages.map { message in
                [
                    "id": AnyJSON(message.id.uuidString),
                    "level": AnyJSON(message.level),
                    "source": AnyJSON(message.source),
                    "message": AnyJSON(message.message),
                    "url": AnyJSON(message.url),
                    "time": AnyJSON(Self.consoleTime.string(from: message.date)),
                ]
            })
        }
        if uses.contains("notices") {
            sections["notices"] = .array(toasts.filter { $0.kind == .download }.map { toast in
                [
                    "id": AnyJSON(toast.id.uuidString),
                    "title": AnyJSON(toast.title),
                    "message": AnyJSON(toast.message),
                    "icon": AnyJSON(toast.iconSystemName),
                    "status": AnyJSON(Self.addonStatus(toast.status)),
                    "progress": AnyJSON(toast.progressFraction.map { ($0 * 100).rounded() / 100 }),
                    "downloadId": AnyJSON(toast.downloadID?.uuidString),
                ]
            })
        }
        return RuntimeState(base: base, sections: sections)
    }

    private static let consoleTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    private static func addonStatus(_ status: BrowserDownloadStatus) -> String {
        switch status {
        case .inProgress: "downloading"
        case .finished: "finished"
        case .failed: "failed"
        }
    }

    private static func addonStatus(_ status: BrowserToastStatus) -> String {
        switch status {
        case .pending: "pending"
        case .success: "success"
        case .failure: "failure"
        }
    }

    private static func addonSecurity(_ state: OriginSecurityState) -> String {
        switch state {
        case .noPage: "none"
        case .secure: "secure"
        case .local: "local"
        case .insecure: "insecure"
        case .certificateError: "certificateError"
        }
    }

    // MARK: Favicons

    /// The image for a favicon token from the state: "tab:<id>", "bookmark:<id>",
    /// "site:<host>" or "page:<url>".
    func addonFavicon(_ token: String) -> NSImage? {
        let parts = token.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        let value = parts[1]
        switch parts[0] {
        case "tab":
            return tabs.first { $0.id.uuidString == value }?.favicon
        case "bookmark":
            guard let bookmark = bookmarks.first(where: { $0.id.uuidString == value }) else { return nil }
            return bookmark.favicon ?? bookmark.tabID.flatMap { id in tabs.first { $0.id == id }?.favicon }
        case "site":
            return autocompleteSites.first { $0.host == value }?.favicon
        case "page":
            return autocompletePages.first { $0.url.absoluteString == value }?.favicon
        default:
            return nil
        }
    }

    // MARK: Commands

    /// Runs a command a component asked for. Returns false for a name Aria doesn't know.
    /// Commands that open windows or prompts Aria doesn't draw (like "console") do nothing
    /// unless a component takes them over with `handles`.
    @discardableResult
    func runAddonCommand(_ name: String, _ arg: AnyJSON?, defaultBrowser: DefaultBrowserController) -> Bool {
        let text = arg?.string ?? ""
        let uuid = UUID(uuidString: text)
        switch name {
        // The page.
        case "back": goBack()
        case "forward": goForward()
        case "reload": reloadOrStop()
        case "stop": if activeTab?.isLoading == true { reloadOrStop() }
        case "retry": retryActivePageFailure()
        case "zoomIn": zoomInActiveTab()
        case "zoomOut": zoomOutActiveTab()
        case "resetZoom": resetActiveTabZoom()
        case "copyLink": copyActivePageLink()
        case "copy":
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        case "togglePermission":
            if let kind = BrowserMediaDeviceKind(rawValue: text) { toggleActivePageMediaPermission(kind) }
        case "find":
            find(arg?["query"]?.string ?? text, backwards: arg?["backwards"]?.bool ?? false)
        case "findNext": findAgain(backwards: false)
        case "findPrevious": findAgain(backwards: true)
        case "clearFind": clearActiveFindSelection()

        // Tabs and bookmarks.
        case "newTab":
            if text.isEmpty { newTab() } else { _ = openNewTab(from: text) }
        case "closeTab":
            if let uuid { closeTab(id: uuid) } else if arg == nil { closeActiveTab() }
        case "reopenTab": reopenLastClosedTab()
        case "selectTab", "switchToTab":
            if let uuid { selectTab(id: uuid) }
        case "selectItem":
            if let value = arg?.number, let index = Int(exactly: value) { selectNavigationItem(atShortcutIndex: index) }
        case "moveTab":
            if let id = arg?["id"]?.string.flatMap(UUID.init(uuidString:)) {
                moveVisibleTab(id: id, before: arg?["before"]?.string.flatMap(UUID.init(uuidString:)))
            }
        case "muteTab":
            if let id = uuid ?? activeTab?.id { toggleMuteTab(id: id) }
        case "bookmarkTab":
            if let id = uuid ?? activeTab?.id { bookmarkTab(id: id) }
        case "unpinTab":
            if let uuid { unpinTab(id: uuid) }
        case "openBookmark":
            if let uuid { openBookmark(id: uuid) }
        case "editBookmark":
            if let uuid { promptToEditBookmarkURL(id: uuid) }
        case "copyBookmark":
            if let uuid { copyBookmarkURL(id: uuid) }
        case "removeBookmark":
            if let uuid { unpinBookmark(id: uuid) }

        // Downloads.
        case "openDownload":
            if let uuid { openDownloadedFile(id: uuid) }
        case "revealDownload", "copyDownloadPath", "copyDownloadSource":
            guard let download = downloads.first(where: { $0.id == uuid }) else { break }
            switch name {
            case "revealDownload": showDownloadInFinder(download)
            case "copyDownloadPath": copyDownloadFilePath(download)
            default: copyDownloadSourceURL(download)
            }
        case "cancelDownload":
            if let uuid { cancelDownload(id: uuid) }
        case "retryDownload":
            if let uuid { retryDownload(id: uuid) }
        case "openDownloadsFolder": openDownloadsFolder()
        case "dismissNotice":
            if let uuid, toasts.contains(where: { $0.id == uuid && $0.kind == .download }) { dismissToast(id: uuid) }

        // Settings.
        case "setBezelStyle":
            if let style = BrowserBezelStyle(rawValue: text) { setBezelStyle(style) }
        case "setSearchEngine":
            if let engine = BrowserSearchEngine(rawValue: text) { setSearchEngine(engine) }
        case "setPasswordAutofill": setPasswordAutofillEnabled(arg?.bool ?? !isPasswordAutofillEnabled)
        case "setPasswordSavePrompt": setPasswordSavePromptEnabled(arg?.bool ?? !isPasswordSavePromptEnabled)
        case "makeDefaultBrowser": defaultBrowser.setAsDefaultBrowser()

        // User scripts and the console.
        case "runScript": performUserScriptSidebarAction(id: text)
        case "setScriptEnabled":
            if let id = arg?["id"]?.string, let enabled = arg?["enabled"]?.bool { setUserScriptEnabled(id: id, isEnabled: enabled) }
        case "reloadScripts": refreshUserScripts()
        case "openScriptsFolder": openUserScriptsFolder()
        case "clearConsole": clearConsoleMessages()
        case "copyConsole":
            let lines = consoleMessages.map { message in
                [Self.consoleTime.string(from: message.date), message.level.uppercased(), message.source,
                 message.message, message.url ?? ""].filter { !$0.isEmpty }.joined(separator: " ")
            }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)

        // Prompts and panels a component draws. Nothing happens unless one takes them over.
        case "console", "editAddress":
            break
        default:
            return false
        }
        return true
    }

    // MARK: Address suggestions

    /// Suggestions for what's typed in an address field: open tabs, sites and pages from
    /// history. `completion` is what the top site or page would complete the typing to.
    func addressSuggestions(_ typed: String) -> AnyJSON {
        let trimmed = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        let query = Self.normalizedQuery(trimmed)
        let openTabURLs = Set(tabs.compactMap { $0.url?.absoluteString })
        let sites = siteSuggestions(query: query)
        var items: [AnyJSON] = openTabSuggestions(query: query).map { tab in
            ["id": AnyJSON("tab-\(tab.id.uuidString)"), "kind": "tab", "title": AnyJSON(tab.displayTitle),
             "subtitle": AnyJSON(tab.addressText), "address": AnyJSON(tab.addressText),
             "tabId": AnyJSON(tab.id.uuidString), "favicon": AnyJSON("tab:\(tab.id.uuidString)")]
        }
        items += sites.map { site in
            ["id": AnyJSON("site-\(site.id)"), "kind": "site", "title": AnyJSON(site.displayTitle),
             "subtitle": AnyJSON(site.displayURL), "address": AnyJSON(site.displayURL), "favicon": AnyJSON("site:\(site.host)")]
        }
        let pages = pageSuggestions(query: query, topSite: sites.first, openTabURLs: openTabURLs)
        items += pages.map { page in
            ["id": AnyJSON("page-\(page.id)"), "kind": "page", "title": AnyJSON(page.displayTitle),
             "subtitle": AnyJSON(page.displayURL), "address": AnyJSON(page.url.absoluteString),
             "favicon": AnyJSON("page:\(page.url.absoluteString)")]
        }
        items = Array(items.prefix(7))
        let completion = (sites.map(\.displayURL) + pages.map(\.displayURL)).first { candidate in
            !trimmed.isEmpty && candidate.lowercased().hasPrefix(trimmed.lowercased()) && candidate.count > trimmed.count
        }
        return ["query": AnyJSON(typed), "items": .array(items), "completion": AnyJSON(completion)]
    }

    private func openTabSuggestions(query: String) -> [BrowserTab] {
        let candidates = tabs.filter { $0.url != nil && $0.id != selectedTabID }
        guard !query.isEmpty else { return Array(candidates.prefix(3)) }
        let strict = candidates.filter { tabMatches($0, query: query, allowWWWFallback: false) }
        let matches = strict.isEmpty ? candidates.filter { tabMatches($0, query: query, allowWWWFallback: true) } : strict
        return Array(matches.sorted { tabScore($0, query: query) > tabScore($1, query: query) }.prefix(3))
    }

    private func siteSuggestions(query: String) -> [BrowserAutocompleteSite] {
        guard !query.isEmpty, !query.contains("/") else { return [] }
        return Array(autocompleteSites
            .filter { site in
                [site.host, site.registrableDomain, site.subdomain ?? "", site.displayTitle]
                    .contains { Self.normalizedQuery($0).contains(query) }
            }
            .sorted { siteScore($0, query: query) > siteScore($1, query: query) }
            .prefix(3))
    }

    private func pageSuggestions(query: String, topSite: BrowserAutocompleteSite?,
                                 openTabURLs: Set<String>) -> [BrowserAutocompletePage] {
        guard !query.isEmpty else { return [] }
        let domainPages = topSite.map {
            query == Self.normalizedQuery($0.host) || query == Self.normalizedQuery($0.registrableDomain)
        } ?? false
        guard domainPages || query.contains("/") || query.contains(" ") else { return [] }
        return Array(autocompletePages
            .filter { page in
                !openTabURLs.contains(page.url.absoluteString) && (topSite?.host == page.host
                    || [page.displayTitle, page.displayURL, page.host].contains { Self.normalizedQuery($0).contains(query) })
            }
            .sorted { pageScore($0, query: query, topSite: topSite) > pageScore($1, query: query, topSite: topSite) }
            .prefix(3))
    }

    private func tabMatches(_ tab: BrowserTab, query: String, allowWWWFallback: Bool) -> Bool {
        let host = (tab.url?.host() ?? "").lowercased()
        return Self.normalizedQuery(tab.displayTitle).contains(query)
            || Self.normalizedQuery(tab.addressText).contains(query)
            || (allowWWWFallback ? host.removingWWWPrefix : host).contains(query)
    }

    private func tabScore(_ tab: BrowserTab, query: String) -> Int {
        let host = (tab.url?.host() ?? "").lowercased()
        let title = Self.normalizedQuery(tab.displayTitle)
        if host == query { return 1000 }
        if host.hasPrefix(query) { return 800 }
        if title.hasPrefix(query) { return 600 }
        if host.contains(query) { return 450 }
        if title.contains(query) { return 300 }
        return 0
    }

    private func siteScore(_ site: BrowserAutocompleteSite, query: String) -> Int {
        let names = [site.host, site.registrableDomain, site.subdomain ?? ""].map(Self.normalizedQuery)
        let match = names.contains(query) ? 2000 : names.contains { $0.hasPrefix(query) } ? 1500 : 800
        return match + min(site.visitCount, 500)
    }

    private func pageScore(_ page: BrowserAutocompletePage, query: String, topSite: BrowserAutocompleteSite?) -> Int {
        let boost = topSite?.host == page.host ? 1000 : 0
        let prefixed = Self.normalizedQuery(page.displayTitle).hasPrefix(query) || Self.normalizedQuery(page.displayURL).hasPrefix(query)
        return boost + (prefixed ? 600 : 250) + min(page.visitCount, 500)
    }

    private static func normalizedQuery(_ value: String) -> String {
        var value = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if value.hasPrefix("http://") { value.removeFirst(7) } else if value.hasPrefix("https://") { value.removeFirst(8) }
        return value.removingWWWPrefix
    }
}

// MARK: Default browser

/// Whether Aria is the default browser, and making it so.
@MainActor
final class DefaultBrowserController: ObservableObject {
    static let shared = DefaultBrowserController()

    @Published private(set) var isDefaultBrowser = false
    @Published private(set) var isUpdating = false

    private let urlSchemes = ["http", "https"]

    func refresh() {
        let value = urlSchemes.allSatisfy(Self.isCurrentAppDefaultHandler(for:))
        if value != isDefaultBrowser { isDefaultBrowser = value }
    }

    func setAsDefaultBrowser() {
        guard !isUpdating else { return }
        isUpdating = true
        Task { @MainActor in
            for scheme in urlSchemes {
                try? await Self.setCurrentAppAsDefaultHandler(for: scheme)
            }
            refresh()
            isUpdating = false
        }
    }

    private static func isCurrentAppDefaultHandler(for scheme: String) -> Bool {
        guard let probeURL = URL(string: "\(scheme)://example.com"),
              let defaultApplicationURL = NSWorkspace.shared.urlForApplication(toOpen: probeURL),
              let defaultBundleIdentifier = Bundle(url: defaultApplicationURL)?.bundleIdentifier,
              let currentBundleIdentifier = Bundle.main.bundleIdentifier else {
            return false
        }
        return defaultBundleIdentifier == currentBundleIdentifier
    }

    private static func setCurrentAppAsDefaultHandler(for scheme: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL, toOpenURLsWithScheme: scheme) { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            }
        }
    }
}
