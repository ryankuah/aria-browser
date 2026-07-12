import Foundation

struct BrowserStartupData: Sendable {
    var settings: [String: String] = [:]
    var userScripts: [StoredBrowserUserScript] = []
    var loginCredentials: [StoredLoginCredential] = []
    var mediaPermissionDecisions: [StoredMediaPermissionDecision] = []
    var bookmarks: [StoredBrowserBookmark] = []
    var autocompleteSites: [StoredAutocompleteSite] = []
    var autocompletePages: [StoredAutocompletePage] = []
    var downloads: [BrowserDownload] = []
    var session: StoredBrowserSession?
}

actor BrowserPersistenceStore {
    private var database: BrowserDatabase?
    private var didAttemptOpen = false

    func loadStartupData() -> BrowserStartupData {
        var data = BrowserStartupData()
        data.settings = load(default: [:]) { try $0.loadSettings() }
        data.userScripts = load(default: []) { try $0.loadUserScripts() }
        data.loginCredentials = load(default: []) { try $0.loadLoginCredentials() }
        data.mediaPermissionDecisions = load(default: []) { try $0.loadMediaPermissionDecisions() }
        data.autocompleteSites = load(default: []) { try $0.loadAutocompleteSites(limit: 500) }
        data.autocompletePages = load(default: []) { try $0.loadAutocompletePages(limit: 1000) }
        data.downloads = load(default: []) { database in
            try Self.interruptActiveDownloads(database.loadRecentDownloads(limit: 50), database: database)
        }
        data.bookmarks = load(default: []) { try $0.loadBookmarks() }
        data.session = load(default: StoredBrowserSession?.none) { try $0.loadSession() }
        return data
    }

    func saveSession(tabs: [BrowserTabSnapshot], selectedTabID: UUID?) {
        save("Browser session save failed") {
            try $0.saveSession(tabs: tabs, selectedTabID: selectedTabID)
        }
    }

    func saveSetting(key: String, value: String) {
        save("Browser setting save failed") {
            try $0.saveSetting(key: key, value: value)
        }
    }

    func saveMediaPermissionDecision(origin: String, deviceKind: String, isAllowed: Bool) {
        save("Browser media permission decision save failed") {
            try $0.saveMediaPermissionDecision(origin: origin, deviceKind: deviceKind, isAllowed: isAllowed)
        }
    }

    func saveUserScript(_ script: StoredBrowserUserScript) {
        save("Browser user script save failed") {
            try $0.saveUserScript(script)
        }
    }

    func deleteUserScriptAndReindex(id: UUID, remainingScripts: [StoredBrowserUserScript]) {
        save("Browser user script delete failed") { database in
            try database.deleteUserScript(id: id)
            for script in remainingScripts {
                try database.saveUserScript(script)
            }
        }
    }

    func loadLoginCredentials() -> [StoredLoginCredential] {
        load(default: []) { try $0.loadLoginCredentials() }
    }

    @discardableResult
    func saveLoginCredential(_ credential: StoredLoginCredential) -> Bool {
        saveReturningBool("Browser login credential save failed") {
            try $0.saveLoginCredential(credential)
        }
    }

    @discardableResult
    func deleteLoginCredential(id: UUID) -> Bool {
        saveReturningBool("Browser login credential delete failed") {
            try $0.deleteLoginCredential(id: id)
        }
    }

    @discardableResult
    func markLoginCredentialUsed(id: UUID, usedAt: Date) -> Bool {
        saveReturningBool("Browser login credential last-used update failed") {
            try $0.markLoginCredentialUsed(id: id, usedAt: usedAt)
        }
    }

    func saveDownload(_ download: BrowserDownload) {
        save("Browser download save failed") {
            try $0.saveDownload(download)
        }
    }

    func saveBookmark(_ bookmark: StoredBrowserBookmark) {
        save("Browser bookmark save failed") {
            try $0.saveBookmark(bookmark)
        }
    }

    func deleteBookmarkAndReindex(id: UUID, remainingBookmarks: [StoredBrowserBookmark]) {
        save("Browser bookmark delete failed") { database in
            try database.deleteBookmark(id: id)
            for bookmark in remainingBookmarks {
                try database.saveBookmark(bookmark)
            }
        }
    }

    func recordHistoryVisit(
        url: URL,
        title: String,
        tabID: UUID?,
        journeyID: UUID?,
        parentVisitID: Int64?
    ) -> Int64? {
        load(default: Int64?.none) { database in
            try database.recordHistoryVisit(
                url: url,
                title: title,
                tabID: tabID,
                journeyID: journeyID,
                parentVisitID: parentVisitID
            )
        }
    }

    func loadAutocompleteSites(limit: Int) -> [StoredAutocompleteSite] {
        load(default: []) { try $0.loadAutocompleteSites(limit: limit) }
    }

    func loadAutocompletePages(limit: Int) -> [StoredAutocompletePage] {
        load(default: []) { try $0.loadAutocompletePages(limit: limit) }
    }

    func saveFavicon(origin: String, pageURL: URL, imageData: Data) {
        save("Browser favicon save failed") {
            try $0.saveFavicon(origin: origin, pageURL: pageURL, imageData: imageData)
        }
    }

    func loadHistoryVisits(limit: Int) -> [StoredHistoryVisit] {
        load(default: []) { try $0.loadRecentHistoryVisits(limit: limit) }
    }

    func loadHistoryTreeNodes(limit: Int) -> [StoredHistoryTreeNode] {
        load(default: []) { try $0.loadRecentHistoryTreeNodes(limit: limit) }
    }

    private func databaseIfAvailable() -> BrowserDatabase? {
        if didAttemptOpen {
            return database
        }

        didAttemptOpen = true
        do {
            database = try BrowserDatabase.openDefault()
        } catch {
            NSLog("Browser persistence disabled: \(error.localizedDescription)")
        }

        return database
    }

    private func load<T>(default defaultValue: T, _ operation: (BrowserDatabase) throws -> T) -> T {
        guard let database = databaseIfAvailable() else {
            return defaultValue
        }

        do {
            return try operation(database)
        } catch {
            NSLog("Browser persistence load failed: \(error.localizedDescription)")
            return defaultValue
        }
    }

    private func save(_ failureMessage: String, operation: (BrowserDatabase) throws -> Void) {
        guard let database = databaseIfAvailable() else {
            return
        }

        do {
            try operation(database)
        } catch {
            NSLog("\(failureMessage): \(error.localizedDescription)")
        }
    }

    private func saveReturningBool(_ failureMessage: String, operation: (BrowserDatabase) throws -> Void) -> Bool {
        guard let database = databaseIfAvailable() else {
            return false
        }

        do {
            try operation(database)
            return true
        } catch {
            NSLog("\(failureMessage): \(error.localizedDescription)")
            return false
        }
    }

    private static func interruptActiveDownloads(_ downloads: [BrowserDownload], database: BrowserDatabase) throws -> [BrowserDownload] {
        try downloads.map { download in
            guard download.status == .inProgress else {
                return download
            }

            var interruptedDownload = download
            interruptedDownload.status = .failed
            interruptedDownload.finishedAt = Date()
            interruptedDownload.errorMessage = "Interrupted"
            try database.saveDownload(interruptedDownload)
            return interruptedDownload
        }
    }
}
