import AppKit
import Foundation
import WebKit

@MainActor
final class BrowserTab: NSObject, ObservableObject, Identifiable, WKNavigationDelegate {
    let id: UUID
    let webView: BrowserWebView

    @Published private(set) var title = "New Tab"
    @Published private(set) var url: URL?
    @Published private(set) var isLoading = false
    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false
    @Published private(set) var originSecurityState: OriginSecurityState = .noPage
    @Published private(set) var favicon: NSImage?
    @Published private(set) var pageFailure: BrowserPageFailure?
    @Published private(set) var pageZoom: CGFloat = 1.0
    @Published private(set) var isPlayingAudio = false
    @Published private(set) var isMuted = false

    var onStateDidChange: ((BrowserTab) -> Void)?
    var onNavigationDidFinish: ((BrowserTab) -> Void)?
    var onURLDidChange: ((BrowserTab, URL) -> Void)?
    var onFaviconDidLoad: ((BrowserTab, NSImage) -> Void)?
    var onFullscreenStateDidChange: ((BrowserTab) -> Void)?
    var onDownloadDidBegin: ((BrowserTab, WKDownload, URL?) -> Void)?
    var onExternalApplicationNavigationRequest: ((BrowserTab, URL, URL?) -> Void)?

    private var fullscreenObservation: NSKeyValueObservation?
    private var urlObservation: NSKeyValueObservation?
    private var faviconLoadTask: Task<Void, Never>?
    private var faviconRequestID: UUID?
    private var lastReportedURLString: String?
    private var pendingNavigationURL: URL?
    private var audibleMediaFrameIDs: Set<String> = []
    private var mediaFramesByID: [String: WKFrameInfo] = [:]
    private var mainMediaFrameID: String?
    private var mediaPlaybackPollTimer: Timer?
    private var nativeMediaIsPlaying = false

    static let zoomLevels: [CGFloat] = [0.50, 0.67, 0.75, 0.90, 1.0, 1.10, 1.25, 1.50, 1.75, 2.0]

    var displayTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "New Tab" : title
    }

    var displaySubtitle: String {
        if let page = BrowserInternalPage.page(for: url) {
            return page.url.absoluteString
        }

        return url?.absoluteString ?? "No page loaded"
    }

    var addressText: String {
        url?.absoluteString ?? ""
    }

    var displayAddressText: String {
        guard let url else {
            return ""
        }

        return BrowserNavigation.displayAddressText(for: url)
    }

    var pageZoomPercentText: String {
        "\(Int((pageZoom * 100).rounded()))%"
    }

    init(
        id: UUID = UUID(),
        webView: BrowserWebView = BrowserWebView(frame: .zero, configuration: BrowserWebView.makeConfiguration()),
        title: String = "New Tab",
        url: URL? = nil,
        favicon: NSImage? = nil
    ) {
        self.id = id
        self.webView = webView
        super.init()

        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? BrowserNavigation.defaultTitle(for: url) : title
        self.url = url
        self.favicon = favicon

        webView.navigationDelegate = self
        webView.pageZoom = pageZoom
        fullscreenObservation = webView.observe(\.fullscreenState, options: [.new]) { [weak self] webView, change in
            Task { @MainActor in
                webView.updateElementFullscreenPresentation(for: change.newValue ?? webView.fullscreenState)

                guard let self else {
                    return
                }

                self.onFullscreenStateDidChange?(self)
            }
        }
        urlObservation = webView.observe(\.url, options: [.new]) { [weak self] webView, change in
            Task { @MainActor in
                await self?.handleObservedURLChange(change.newValue ?? webView.url)
            }
        }
        refreshFromWebView(notify: false)
    }

    isolated deinit {
        faviconLoadTask?.cancel()
        mediaPlaybackPollTimer?.invalidate()
    }

    func attachUIDelegate(_ delegate: WKUIDelegate) {
        webView.uiDelegate = delegate
    }

    func prepareDeferredLoad(_ url: URL) {
        guard BrowserNavigation.isAllowedNavigationURL(url) else {
            return
        }

        clearFaviconIfNeeded(for: url)
        self.url = url
        title = BrowserNavigation.defaultTitle(for: url)
        isLoading = false
        canGoBack = false
        canGoForward = false
        originSecurityState = BrowserNavigation.originSecurityState(for: url)
        pageFailure = nil
        onStateDidChange?(self)
    }

    func load(_ url: URL) {
        guard BrowserNavigation.isAllowedNavigationURL(url) else {
            return
        }

        clearFaviconIfNeeded(for: url)
        self.url = url
        pendingNavigationURL = url
        title = BrowserNavigation.defaultTitle(for: url)
        isLoading = !BrowserNavigation.isInternalPageURL(url)
        canGoBack = BrowserNavigation.isInternalPageURL(url) ? false : canGoBack
        canGoForward = BrowserNavigation.isInternalPageURL(url) ? false : canGoForward
        originSecurityState = BrowserNavigation.originSecurityState(for: url)
        pageFailure = nil
        if BrowserNavigation.isInternalPageURL(url) {
            pendingNavigationURL = nil
            onStateDidChange?(self)
            return
        }

        if let invalidPort = BrowserNavigation.invalidPort(in: url) {
            pendingNavigationURL = nil
            isLoading = false
            pageFailure = .navigationRejected(url: url, detail: "Invalid port \(invalidPort)")
            onStateDidChange?(self)
            return
        }

        guard webView.load(URLRequest(url: url)) != nil else {
            pendingNavigationURL = nil
            isLoading = false
            pageFailure = .navigationRejected(url: url)
            onStateDidChange?(self)
            return
        }

        refreshFromWebView()
    }

    func goBack() {
        guard !BrowserNavigation.isInternalPageURL(url) else {
            return
        }

        guard webView.canGoBack else {
            return
        }

        pageFailure = nil
        webView.goBack()
        refreshFromWebView()
    }

    func goForward() {
        guard !BrowserNavigation.isInternalPageURL(url) else {
            return
        }

        guard webView.canGoForward else {
            return
        }

        pageFailure = nil
        webView.goForward()
        refreshFromWebView()
    }

    func reloadOrStop() {
        guard !BrowserNavigation.isInternalPageURL(url) else {
            return
        }

        if webView.isLoading {
            webView.stopLoading()
        } else if pageFailure != nil {
            retryPageFailure()
        } else {
            pageFailure = nil
            webView.reload()
        }

        refreshFromWebView()
    }

    func retryPageFailure() {
        guard !BrowserNavigation.isInternalPageURL(url) else {
            return
        }

        guard let retryURL = pageFailure?.url ?? webView.url ?? url else {
            return
        }

        load(retryURL)
    }

    func setPageZoom(_ zoom: CGFloat) {
        let resolvedZoom = Self.nearestZoomLevel(to: zoom)
        guard pageZoom != resolvedZoom else {
            return
        }

        pageZoom = resolvedZoom
        webView.pageZoom = resolvedZoom
        onStateDidChange?(self)
    }

    func zoomIn() {
        let currentIndex = Self.zoomLevelIndex(for: pageZoom)
        setPageZoom(Self.zoomLevels[min(currentIndex + 1, Self.zoomLevels.count - 1)])
    }

    func zoomOut() {
        let currentIndex = Self.zoomLevelIndex(for: pageZoom)
        setPageZoom(Self.zoomLevels[max(currentIndex - 1, 0)])
    }

    func resetZoom() {
        setPageZoom(1.0)
    }

    func findInPage(_ query: String, backwards: Bool, completion: @escaping (Bool) -> Void) {
        guard !BrowserNavigation.isInternalPageURL(url) else {
            completion(false)
            return
        }

        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            clearFindSelection()
            completion(true)
            return
        }

        let configuration = WKFindConfiguration()
        configuration.backwards = backwards
        configuration.caseSensitive = false
        configuration.wraps = true

        Task { @MainActor [weak self] in
            guard let self else {
                completion(false)
                return
            }

            let result = try? await self.webView.find(trimmedQuery, configuration: configuration)
            completion(result?.matchFound == true)
        }
    }

    func clearFindSelection() {
        webView.evaluateJavaScript("window.getSelection && window.getSelection().removeAllRanges()", completionHandler: nil)
    }

    func toggleMuted() {
        setMuted(!isMuted)
    }

    func receiveMediaState(_ body: Any, frameInfo: WKFrameInfo) {
        guard let payload = body as? [String: Any],
              payload["type"] as? String == "state",
              let frameID = payload["frameID"] as? String,
              !frameID.isEmpty,
              let frameIsPlayingAudio = payload["isPlayingAudio"] as? Bool else {
            return
        }

        if frameInfo.isMainFrame, mainMediaFrameID != frameID {
            mainMediaFrameID = frameID
            mediaFramesByID.removeAll()
            audibleMediaFrameIDs.removeAll()
        }

        mediaFramesByID[frameID] = frameInfo
        if isMuted {
            applyMutedState(to: frameInfo)
        }

        if frameIsPlayingAudio, !isMuted {
            audibleMediaFrameIDs.insert(frameID)
        } else {
            audibleMediaFrameIDs.remove(frameID)
        }
        refreshAudioPlayingState()
    }

    func prepareForClose() {
        faviconLoadTask?.cancel()
        faviconLoadTask = nil
        faviconRequestID = nil
        webView.stopLoading()
        mediaFramesByID.removeAll()
        mainMediaFrameID = nil
        audibleMediaFrameIDs.removeAll()
        nativeMediaIsPlaying = false
        refreshAudioPlayingState()
        stopMediaPlaybackMonitoring()
        webView.setAllMediaPlaybackSuspended(true, completionHandler: nil)
    }

    private func handleObservedURLChange(_ observedURL: URL?) async {
        guard let observedURL,
              BrowserNavigation.isAllowedNavigationURL(observedURL) else {
            return
        }

        let urlString = observedURL.absoluteString
        guard lastReportedURLString != urlString else {
            return
        }

        clearFaviconIfNeeded(for: observedURL)
        lastReportedURLString = urlString
        refreshFromWebView()
        onURLDidChange?(self, observedURL)
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        audibleMediaFrameIDs.removeAll()
        refreshAudioPlayingState()
        clearFaviconIfNeeded(for: pendingNavigationURL ?? webView.url)
        originSecurityState = BrowserNavigation.originSecurityState(for: pendingNavigationURL ?? webView.url ?? url)
        pageFailure = nil
        refreshFromWebView()
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        pageFailure = nil
        refreshFromWebView()
        pendingNavigationURL = nil
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if pageFailure != nil {
            refreshFromWebView()
            pendingNavigationURL = nil
            return
        }

        refreshFromWebView()
        pendingNavigationURL = nil
        refreshFavicon()
        onNavigationDidFinish?(self)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        handleNavigationFailure(error)
        refreshFromWebView()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        handleNavigationFailure(error)
        refreshFromWebView()
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        pageFailure = .webContentProcessTerminated(url: webView.url ?? url)
        refreshFromWebView()
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }

        if navigationAction.targetFrame?.isMainFrame == true,
           let invalidPort = BrowserNavigation.invalidPort(in: url) {
            pendingNavigationURL = nil
            self.url = url
            isLoading = false
            pageFailure = .navigationRejected(url: url, detail: "Invalid port \(invalidPort)")
            refreshFromWebView()
            decisionHandler(.cancel)
            return
        }

        if shouldReloadWithDesktopUserAgent(navigationAction) {
            pendingNavigationURL = url
            webView.load(Self.desktopUserAgentRequest(from: navigationAction.request))
            decisionHandler(.cancel)
            return
        }

        if navigationAction.shouldPerformDownload {
            decisionHandler(BrowserNavigation.isAllowedDownloadURL(url) ? .download : .cancel)
            return
        }

        if BrowserNavigation.isExternalApplicationURL(url),
           NSWorkspace.shared.urlForApplication(toOpen: url) != nil {
            onExternalApplicationNavigationRequest?(self, url, navigationAction.sourceFrame.request.url)
            decisionHandler(.cancel)
            return
        }

        guard BrowserNavigation.isAllowedNavigationURL(url) else {
            decisionHandler(.cancel)
            return
        }

        if navigationAction.targetFrame?.isMainFrame == true {
            pendingNavigationURL = url
        }

        decisionHandler(.allow)
    }

    private func shouldReloadWithDesktopUserAgent(_ navigationAction: WKNavigationAction) -> Bool {
        guard navigationAction.targetFrame?.isMainFrame == true,
              let url = navigationAction.request.url,
              BrowserNavigation.isAllowedNavigationURL(url) else {
            return false
        }

        let method = navigationAction.request.httpMethod?.uppercased() ?? "GET"
        guard method == "GET" || method == "HEAD" else {
            return false
        }

        let userAgent = navigationAction.request.value(forHTTPHeaderField: "User-Agent") ?? ""
        return !userAgent.contains(BrowserWebView.safariUserAgentSuffix)
    }

    private static func desktopUserAgentRequest(from request: URLRequest) -> URLRequest {
        var request = request
        request.setValue(BrowserWebView.desktopSafariUserAgent, forHTTPHeaderField: "User-Agent")
        return request
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationResponsePolicy) -> Void
    ) {
        // HTTP error responses can contain the site's own error or verification page.
        if navigationResponse.canShowMIMEType {
            decisionHandler(.allow)
            return
        }

        guard let url = navigationResponse.response.url,
              BrowserNavigation.isAllowedDownloadURL(url) else {
            decisionHandler(.cancel)
            return
        }

        decisionHandler(.download)
    }

    func webView(
        _ webView: WKWebView,
        navigationAction: WKNavigationAction,
        didBecome download: WKDownload
    ) {
        onDownloadDidBegin?(self, download, navigationAction.request.url)
    }

    func webView(
        _ webView: WKWebView,
        navigationResponse: WKNavigationResponse,
        didBecome download: WKDownload
    ) {
        onDownloadDidBegin?(self, download, navigationResponse.response.url)
    }

    func webView(
        _ webView: WKWebView,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping @MainActor @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        guard let serverTrust = challenge.protectionSpace.serverTrust else {
            originSecurityState = .certificateError
            pageFailure = .certificateFailure(url: webView.url ?? url)
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        var trustError: CFError?
        guard SecTrustEvaluateWithError(serverTrust, &trustError) else {
            originSecurityState = .certificateError
            pageFailure = .certificateFailure(url: webView.url ?? url)
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        originSecurityState = BrowserNavigation.originSecurityState(for: webView.url ?? url)
        completionHandler(.useCredential, URLCredential(trust: serverTrust))
    }

    private func setMuted(_ muted: Bool) {
        guard isMuted != muted else {
            return
        }

        isMuted = muted
        if muted {
            audibleMediaFrameIDs.removeAll()
            refreshAudioPlayingState()
        }

        for frameInfo in mediaFramesByID.values {
            applyMutedState(to: frameInfo)
        }
    }

    private func applyMutedState(to frameInfo: WKFrameInfo) {
        webView.callAsyncJavaScript(
            "window.__browserMediaController?.setMuted(muted);",
            arguments: ["muted": isMuted],
            in: frameInfo,
            in: .page,
            completionHandler: nil
        )
    }

    private func refreshAudioPlayingState() {
        isPlayingAudio = nativeMediaIsPlaying || !audibleMediaFrameIDs.isEmpty
    }

    func startMediaPlaybackMonitoring() {
        guard mediaPlaybackPollTimer == nil else {
            return
        }

        pollNativeMediaPlaybackState()
        mediaPlaybackPollTimer = Timer.scheduledTimer(withTimeInterval: 0.75, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.pollNativeMediaPlaybackState()
            }
        }
    }

    private func stopMediaPlaybackMonitoring() {
        mediaPlaybackPollTimer?.invalidate()
        mediaPlaybackPollTimer = nil
    }

    private func pollNativeMediaPlaybackState() {
        webView.requestMediaPlaybackState { [weak self] state in
            guard let self else {
                return
            }

            self.nativeMediaIsPlaying = state == .playing
            self.refreshAudioPlayingState()
        }
    }

    private func refreshFromWebView(notify: Bool = true) {
        if pageFailure == nil {
            url = pendingNavigationURL ?? webView.url ?? url
        }

        if let webTitle = webView.title?.trimmingCharacters(in: .whitespacesAndNewlines), !webTitle.isEmpty {
            title = webTitle
        } else if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || title == "New Tab" {
            title = BrowserNavigation.defaultTitle(for: url)
        }

        isLoading = webView.isLoading
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
        if originSecurityState != .certificateError {
            originSecurityState = BrowserNavigation.originSecurityState(for: webView.url ?? url)
        }

        if notify {
            onStateDidChange?(self)
        }
    }

    private func clearFavicon() {
        faviconLoadTask?.cancel()
        faviconLoadTask = nil
        faviconRequestID = nil
        favicon = nil
    }

    private func clearFaviconIfNeeded(for nextURL: URL?) {
        let currentOrigin = url.flatMap(BrowserNavigation.originKey(for:))
        let nextOrigin = nextURL.flatMap(BrowserNavigation.originKey(for:))
        guard let currentOrigin,
              let nextOrigin,
              currentOrigin == nextOrigin else {
            clearFavicon()
            return
        }
    }

    private func refreshFavicon() {
        guard let pageURL = webView.url ?? url,
              BrowserNavigation.isAllowedNavigationURL(pageURL) else {
            clearFavicon()
            return
        }

        faviconLoadTask?.cancel()

        let requestID = UUID()
        faviconRequestID = requestID
        faviconLoadTask = Task { [weak self] in
            await self?.loadFavicon(for: pageURL, requestID: requestID)
        }
    }

    private func loadFavicon(for pageURL: URL, requestID: UUID) async {
        guard let image = await Self.fetchFavicon(for: pageURL, webView: webView),
              faviconRequestID == requestID else {
            return
        }

        favicon = image
        onFaviconDidLoad?(self, image)
    }

    static func fetchFavicon(for pageURL: URL, webView: WKWebView?) async -> NSImage? {
        let candidates = await faviconCandidateURLs(for: pageURL, webView: webView)

        for candidate in candidates {
            guard !Task.isCancelled else {
                return nil
            }

            do {
                var request = URLRequest(url: candidate)
                request.cachePolicy = .returnCacheDataElseLoad
                request.timeoutInterval = 8

                let (data, response) = try await URLSession.shared.data(for: request)
                guard !Task.isCancelled else {
                    return nil
                }

                if let httpResponse = response as? HTTPURLResponse,
                   !(200..<300).contains(httpResponse.statusCode) {
                    continue
                }

                guard let image = NSImage(data: data), image.isValid else {
                    continue
                }

                return image
            } catch {
                continue
            }
        }

        return nil
    }

    private static func faviconCandidateURLs(for pageURL: URL, webView: WKWebView?) async -> [URL] {
        var urls: [URL] = []
        let script = """
        (() => Array.from(document.querySelectorAll('link[rel]'))
            .filter((link) => link.rel && link.rel.toLowerCase().includes('icon'))
            .map((link) => link.href)
            .filter(Boolean))()
        """

        if let webView,
           let rawIconURLs = try? await webView.evaluateJavaScript(script) as? [String] {
            urls.append(contentsOf: rawIconURLs.compactMap(URL.init(string:)))
        }

        if let fallbackURL = Self.defaultFaviconURL(for: pageURL) {
            urls.append(fallbackURL)
        }

        var seen = Set<String>()
        return urls.filter { url in
            guard BrowserNavigation.isAllowedNavigationURL(url) else {
                return false
            }

            return seen.insert(url.absoluteString).inserted
        }
    }

    private static func defaultFaviconURL(for pageURL: URL) -> URL? {
        guard var components = URLComponents(url: pageURL, resolvingAgainstBaseURL: false),
              components.host != nil else {
            return nil
        }

        components.path = "/favicon.ico"
        components.query = nil
        components.fragment = nil
        return components.url
    }

    private static func zoomLevelIndex(for zoom: CGFloat) -> Int {
        let nearest = nearestZoomLevel(to: zoom)
        return zoomLevels.firstIndex(of: nearest) ?? zoomLevels.firstIndex(of: 1.0) ?? 0
    }

    private static func nearestZoomLevel(to zoom: CGFloat) -> CGFloat {
        zoomLevels.min { lhs, rhs in
            abs(lhs - zoom) < abs(rhs - zoom)
        } ?? 1.0
    }

    private func handleNavigationFailure(_ error: Error) {
        guard !Self.shouldIgnoreNavigationFailure(error) else {
            return
        }

        let failedURL = pendingNavigationURL ?? webView.url ?? url
        pendingNavigationURL = nil
        url = failedURL
        let isCertificateError = updateOriginSecurityState(after: error)
        pageFailure = .navigationFailure(
            url: failedURL,
            error: error,
            isCertificateError: isCertificateError
        )
    }

    private static func shouldIgnoreNavigationFailure(_ error: Error) -> Bool {
        let nsError = error as NSError

        if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled {
            return true
        }

        if nsError.domain == "WebKitErrorDomain", nsError.code == 102 {
            return true
        }

        return false
    }

    @discardableResult
    private func updateOriginSecurityState(after error: Error) -> Bool {
        let nsError = error as NSError
        let certificateErrorCodes: Set<Int> = [
            NSURLErrorServerCertificateHasBadDate,
            NSURLErrorServerCertificateUntrusted,
            NSURLErrorServerCertificateHasUnknownRoot,
            NSURLErrorServerCertificateNotYetValid,
            NSURLErrorClientCertificateRejected,
            NSURLErrorClientCertificateRequired,
            NSURLErrorSecureConnectionFailed
        ]

        if nsError.domain == NSURLErrorDomain, certificateErrorCodes.contains(nsError.code) {
            originSecurityState = .certificateError
            return true
        }

        return false
    }
}
