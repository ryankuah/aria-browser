import SwiftUI
import WebKit

struct WebView: NSViewRepresentable {
    let webView: BrowserWebView?
    let cornerRadius: CGFloat
    let occlusionRects: [CGRect]
    let onMount: (() -> Void)?

    init(
        webView: BrowserWebView?,
        cornerRadius: CGFloat = 0,
        occlusionRects: [CGRect] = [],
        onMount: (() -> Void)? = nil
    ) {
        self.webView = webView
        self.cornerRadius = cornerRadius
        self.occlusionRects = occlusionRects
        self.onMount = onMount
    }

    func makeNSView(context: Context) -> BrowserWebContainerView {
        let containerView = BrowserWebContainerView()
        containerView.cornerRadius = cornerRadius
        containerView.occlusionRects = occlusionRects
        containerView.onWebViewMounted = onMount
        containerView.setWebView(webView)
        return containerView
    }

    func updateNSView(_ nsView: BrowserWebContainerView, context: Context) {
        nsView.cornerRadius = cornerRadius
        nsView.occlusionRects = occlusionRects
        nsView.onWebViewMounted = onMount
        nsView.setWebView(webView)
    }
}

final class BrowserWebContainerView: NSView {
    private var hostedWebView: BrowserWebView?
    private var hostedWebViewConstraints: [NSLayoutConstraint] = []
    private var isMountNotificationPending = false
    private var pendingWebView: BrowserWebView?
    private var hasPendingWebView = false
    private var fullscreenObservation: NSKeyValueObservation?

    var onWebViewMounted: (() -> Void)?
    var occlusionRects: [CGRect] = [] {
        didSet {
            hostedWebView?.occlusionRects = occlusionRects
            window?.invalidateCursorRects(for: self)
            hostedWebView.map { window?.invalidateCursorRects(for: $0) }
        }
    }

    var cornerRadius: CGFloat = 0 {
        didSet {
            updateCornerMask()
        }
    }

    init() {
        super.init(frame: .zero)

        wantsLayer = true
        layer?.cornerCurve = .continuous
        layer?.backgroundColor = NSColor.clear.cgColor
        updateCornerMask()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func setWebView(_ webView: BrowserWebView?) {
        guard hostedWebView !== webView else {
            return
        }

        if hostedWebView?.isElementFullscreenTransitionActive == true {
            pendingWebView = webView
            hasPendingWebView = true
            return
        }

        pendingWebView = nil
        hasPendingWebView = false
        fullscreenObservation = nil
        NSLayoutConstraint.deactivate(hostedWebViewConstraints)
        hostedWebViewConstraints = []
        hostedWebView?.removeFromSuperview()
        hostedWebView = webView
        isMountNotificationPending = false

        guard let webView else {
            return
        }

        webView.removeFromSuperview()
        webView.occlusionRects = occlusionRects
        if bounds.width > 1, bounds.height > 1 {
            webView.frame = bounds
        }
        webView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(webView)
        fullscreenObservation = webView.observe(\.fullscreenState, options: [.new]) { [weak self] webView, _ in
            DispatchQueue.main.async {
                guard !webView.isElementFullscreenTransitionActive else {
                    return
                }

                self?.applyPendingWebViewIfReady()
            }
        }

        hostedWebViewConstraints = [
            webView.leadingAnchor.constraint(equalTo: leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: trailingAnchor),
            webView.topAnchor.constraint(equalTo: topAnchor),
            webView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ]
        NSLayoutConstraint.activate(hostedWebViewConstraints)

        DispatchQueue.main.async { [weak self] in
            self?.isMountNotificationPending = true
            self?.notifyMountedIfReady()
        }
    }

    private func applyPendingWebViewIfReady() {
        guard hasPendingWebView else {
            return
        }

        if hostedWebView?.isElementFullscreenTransitionActive == true {
            return
        }

        let webView = pendingWebView
        pendingWebView = nil
        hasPendingWebView = false
        setWebView(webView)
    }

    override func layout() {
        super.layout()
        notifyMountedIfReady()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        notifyMountedIfReady()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        if isPointOccluded(point) {
            return nil
        }

        return super.hitTest(point)
    }

    override func mouseDown(with event: NSEvent) {
        focusHostedWebView()
        super.mouseDown(with: event)
    }

    private func notifyMountedIfReady() {
        guard isMountNotificationPending,
              let hostedWebView,
              window != nil else {
            return
        }

        layoutSubtreeIfNeeded()

        guard hostedWebView.bounds.width > 1,
              hostedWebView.bounds.height > 1 else {
            return
        }

        hostedWebView.frame = bounds
        hostedWebView.layoutSubtreeIfNeeded()
        focusHostedWebView()

        isMountNotificationPending = false
        onWebViewMounted?()
    }

    private func focusHostedWebView() {
        guard let hostedWebView,
              window?.firstResponder !== hostedWebView else {
            return
        }

        window?.makeFirstResponder(hostedWebView)
    }

    private func updateCornerMask() {
        let resolvedCornerRadius = max(cornerRadius, 0)
        layer?.cornerRadius = resolvedCornerRadius
        layer?.masksToBounds = resolvedCornerRadius > 0
    }

    private func isPointOccluded(_ point: NSPoint) -> Bool {
        occlusionRects.contains { $0.contains(point) }
    }
}

final class BrowserWebView: WKWebView {
    private static let defaultInitialFrame = CGRect(x: 0, y: 0, width: 1280, height: 800)
    static let desktopSafariUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"
    static let safariUserAgentSuffix = "Version/18.0 Safari/605.1.15"
    private var isPointerShieldUpdatePending = false

    var isElementFullscreenTransitionActive: Bool {
        Self.isElementFullscreenTransitionActive(fullscreenState)
    }

    var isElementFullscreenActiveForChrome: Bool {
        Self.isElementFullscreenActiveForChrome(fullscreenState)
    }

    static func isElementFullscreenTransitionActive(_ fullscreenState: WKWebView.FullscreenState) -> Bool {
        fullscreenState == .enteringFullscreen
            || fullscreenState == .inFullscreen
            || fullscreenState == .exitingFullscreen
    }

    static func isElementFullscreenActiveForChrome(_ fullscreenState: WKWebView.FullscreenState) -> Bool {
        fullscreenState == .enteringFullscreen || fullscreenState == .inFullscreen
    }

    var occlusionRects: [CGRect] = [] {
        didSet {
            window?.invalidateCursorRects(for: self)
            updatePointerShield()
        }
    }

    func updateElementFullscreenPresentation(for fullscreenState: WKWebView.FullscreenState) {
        if Self.isElementFullscreenActiveForChrome(fullscreenState) {
            occlusionRects = []
        }
    }

    override init(frame: CGRect, configuration: WKWebViewConfiguration) {
        super.init(frame: frame == .zero ? Self.defaultInitialFrame : frame, configuration: configuration)
        allowsBackForwardNavigationGestures = true
        setValue(false, forKey: "drawsBackground")
        customUserAgent = Self.desktopSafariUserAgent
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        if isPointOccluded(point) {
            return nil
        }

        return super.hitTest(point)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard shouldHandleAsWebContentKey(event) else {
            return super.performKeyEquivalent(with: event)
        }

        // WebKit calls back through AppKit when web content does not handle a key.
        // Consume plain keys here to prevent AppKit's system beep without
        // re-dispatching the event into WKWebView and recursively re-entering
        // this path.
        return true
    }

    override func mouseMoved(with event: NSEvent) {
        if isEventInOccludedRegion(event) {
            updatePointerShield()
            return
        }

        super.mouseMoved(with: event)
    }

    override func mouseEntered(with event: NSEvent) {
        if isEventInOccludedRegion(event) {
            return
        }

        super.mouseEntered(with: event)
    }

    override func cursorUpdate(with event: NSEvent) {
        if isEventInOccludedRegion(event) {
            updatePointerShield()
            return
        }

        super.cursorUpdate(with: event)
    }

    static func makeConfiguration(userScripts: [BrowserUserScript] = []) -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configure(configuration, userScripts: userScripts)
        return configuration
    }

    static func configure(
        _ configuration: WKWebViewConfiguration,
        consoleMessageHandler: WKScriptMessageHandler? = nil,
        userScripts: [BrowserUserScript] = []
    ) {
        configuration.applicationNameForUserAgent = Self.safariUserAgentSuffix
        configuration.preferences.isElementFullscreenEnabled = true

        let preferences = WKWebpagePreferences()
        preferences.allowsContentJavaScript = true
        configuration.defaultWebpagePreferences = preferences

        let userContentController = configuration.userContentController
        if let consoleMessageHandler {
            userContentController.add(consoleMessageHandler, name: "browserConsole")
        }
        installConfiguredUserScripts(
            on: userContentController,
            includeConsoleBridge: consoleMessageHandler != nil,
            userScripts: userScripts
        )
    }

    static func replaceConfiguredUserScripts(
        on userContentController: WKUserContentController,
        includeConsoleBridge: Bool,
        userScripts: [BrowserUserScript]
    ) {
        userContentController.removeAllUserScripts()
        installConfiguredUserScripts(
            on: userContentController,
            includeConsoleBridge: includeConsoleBridge,
            userScripts: userScripts
        )
    }

    private func isEventInOccludedRegion(_ event: NSEvent) -> Bool {
        isPointOccluded(convert(event.locationInWindow, from: nil))
    }

    private func isPointOccluded(_ point: NSPoint) -> Bool {
        bounds.contains(point) && occlusionRects.contains { $0.contains(point) }
    }

    private func shouldHandleAsWebContentKey(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown,
              window?.firstResponder === self,
              let characters = event.charactersIgnoringModifiers,
              !characters.isEmpty else {
            return false
        }

        let modifiers = event.modifierFlags.intersection([.command, .option, .control])
        guard modifiers.isEmpty else {
            return false
        }

        return !Self.containsAppKitFunctionKey(characters)
    }

    private static func containsAppKitFunctionKey(_ characters: String) -> Bool {
        characters.unicodeScalars.contains { scalar in
            scalar.value >= 0xF700 && scalar.value <= 0xF8FF
        }
    }

    private func updatePointerShield() {
        guard !isPointerShieldUpdatePending else {
            return
        }

        isPointerShieldUpdatePending = true

        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }

            self.isPointerShieldUpdatePending = false
            let rects = self.normalizedOcclusionRects()
            self.evaluateJavaScript(Self.pointerShieldScript(rects: rects), completionHandler: nil)
        }
    }

    private func normalizedOcclusionRects() -> [CGRect] {
        occlusionRects.compactMap { rect in
            let intersection = rect.intersection(bounds)
            guard !intersection.isNull,
                  intersection.width > 0,
                  intersection.height > 0 else {
                return nil
            }

            return intersection
        }
    }

    private static func pointerShieldScript(rects: [CGRect]) -> String {
        let rectJSON = rects.map { rect in
            """
            {"left":\(String(format: "%.2f", rect.minX)),"top":\(String(format: "%.2f", rect.minY)),"width":\(String(format: "%.2f", rect.width)),"height":\(String(format: "%.2f", rect.height))}
            """
        }
            .joined(separator: ",")

        return #"""
        (() => {
          const rootId = "__browserPointerShields";
          const rects = [RECTS];
          let root = document.getElementById(rootId);

          if (!root) {
            root = document.createElement("div");
            root.id = rootId;
            root.setAttribute("aria-hidden", "true");
            Object.assign(root.style, {
              position: "fixed",
              left: "0",
              top: "0",
              width: "0",
              height: "0",
              zIndex: "2147483647",
              pointerEvents: "none"
            });
            (document.documentElement || document.body).appendChild(root);
          }

          if (rects.length === 0) {
            root.remove();
            return;
          }

          while (root.children.length > rects.length) {
            root.lastChild.remove();
          }

          const block = event => {
            event.preventDefault();
            event.stopPropagation();
          };
          const stop = event => event.stopPropagation();
          const eventNames = ["click", "dblclick", "mousedown", "mouseup", "mousemove", "mouseover", "mouseout", "pointerdown", "pointerup", "pointermove", "pointerover", "pointerout"];

          rects.forEach((rect, index) => {
            let shield = root.children[index];
            if (!shield) {
              shield = document.createElement("div");
              shield.addEventListener("contextmenu", block, true);
              for (const name of eventNames) {
                shield.addEventListener(name, stop, true);
              }
              root.appendChild(shield);
            }

            Object.assign(shield.style, {
              position: "fixed",
              left: `${rect.left}px`,
              top: `${rect.top}px`,
              width: `${rect.width}px`,
              height: `${rect.height}px`,
              zIndex: "2147483647",
              background: "transparent",
              cursor: "auto",
              pointerEvents: "auto"
            });
          });
        })();
        """#
            .replacingOccurrences(of: "RECTS", with: rectJSON)
    }

    private static func installConfiguredUserScripts(
        on userContentController: WKUserContentController,
        includeConsoleBridge: Bool,
        userScripts: [BrowserUserScript]
    ) {
        if includeConsoleBridge {
            userContentController.addUserScript(WKUserScript(
                source: consoleBridgeScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false
            ))
        }

        userContentController.addUserScript(WKUserScript(
            source: videoSkipPromptScript,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: false
        ))

        for userScript in userScripts where userScript.isRunnable {
            userContentController.addUserScript(WKUserScript(
                source: wrappedUserScriptSource(for: userScript),
                injectionTime: webKitInjectionTime(for: userScript.injectionTime),
                forMainFrameOnly: userScript.forMainFrameOnly
            ))
        }
    }

    private static func webKitInjectionTime(for injectionTime: BrowserUserScriptInjectionTime) -> WKUserScriptInjectionTime {
        switch injectionTime {
        case .documentStart:
            return .atDocumentStart
        case .documentEnd:
            return .atDocumentEnd
        }
    }

    private static func wrappedUserScriptSource(for userScript: BrowserUserScript) -> String {
        #"""
        (() => {
          const scriptName = __BROWSER_USER_SCRIPT_NAME__;
          const patterns = __BROWSER_USER_SCRIPT_PATTERNS__;
          const escapeRegExp = value => value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
          const wildcardToRegExp = value => new RegExp(`^${String(value).split("*").map(escapeRegExp).join(".*")}$`);
          const matchesHost = (pattern, host) => {
            const normalizedPattern = String(pattern || "*").toLowerCase();
            const normalizedHost = String(host || "").toLowerCase();
            if (normalizedPattern === "*" || normalizedPattern === "") return true;
            if (normalizedPattern.startsWith("*.")) {
              const base = normalizedPattern.slice(2);
              return normalizedHost === base || normalizedHost.endsWith(`.${base}`);
            }
            return wildcardToRegExp(normalizedPattern).test(normalizedHost);
          };
          const matchesPattern = pattern => {
            const normalizedPattern = String(pattern || "").trim();
            if (!normalizedPattern || normalizedPattern === "*" || normalizedPattern === "<all_urls>") return true;

            const url = new URL(location.href);
            const match = normalizedPattern.match(/^(\*|https?|file):\/\/([^/]*)(\/.*)?$/i);
            if (!match) {
              if (!normalizedPattern.includes("/") && !normalizedPattern.includes(":")) {
                return matchesHost(normalizedPattern, url.hostname);
              }
              return wildcardToRegExp(normalizedPattern).test(location.href);
            }

            const expectedScheme = match[1].toLowerCase();
            const actualScheme = url.protocol.replace(/:$/, "").toLowerCase();
            if (expectedScheme !== "*" && expectedScheme !== actualScheme) return false;

            const hostPattern = match[2] || "*";
            if (actualScheme !== "file" && !matchesHost(hostPattern, url.hostname)) return false;

            const pathPattern = match[3] || "/*";
            return wildcardToRegExp(pathPattern).test(`${url.pathname}${url.search}${url.hash}`);
          };

          if (!patterns.some(matchesPattern)) return;

          try {
        __BROWSER_USER_SCRIPT_SOURCE__
          } catch (error) {
            console.error(`[Browser user script: ${scriptName}]`, error);
          }
        })();
        """#
        .replacingOccurrences(of: "__BROWSER_USER_SCRIPT_NAME__", with: javascriptStringLiteral(userScript.displayName))
        .replacingOccurrences(of: "__BROWSER_USER_SCRIPT_PATTERNS__", with: javascriptArrayLiteral(userScript.normalizedMatchPatternLines))
        .replacingOccurrences(of: "__BROWSER_USER_SCRIPT_SOURCE__", with: indentedUserScriptSource(userScript.source))
    }

    private static func javascriptStringLiteral(_ value: String) -> String {
        guard let data = try? JSONEncoder().encode(value),
              let literal = String(data: data, encoding: .utf8) else {
            return "\"\""
        }

        return literal
    }

    private static func javascriptArrayLiteral(_ values: [String]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: values),
              let literal = String(data: data, encoding: .utf8) else {
            return "[]"
        }

        return literal
    }

    private static func indentedUserScriptSource(_ source: String) -> String {
        source
            .components(separatedBy: .newlines)
            .map { "            \($0)" }
            .joined(separator: "\n")
    }

    private static let consoleBridgeScript = #"""
    (() => {
      if (window.__browserConsoleBridgeInstalled) return;
      window.__browserConsoleBridgeInstalled = true;

      const post = (level, values, source = "page") => {
        try {
          window.webkit.messageHandlers.browserConsole.postMessage({
            level,
            source,
            url: String(location.href),
            message: values.map(value => {
              try {
                if (typeof value === "string") return value;
                if (value instanceof Error) return `${value.name}: ${value.message}\n${value.stack || ""}`;
                if (value instanceof Element) return value.outerHTML;
                if (typeof value === "undefined") return "undefined";
                return JSON.stringify(value);
              } catch (_) {
                return String(value);
              }
            }).join(" ")
          });
        } catch (_) {}
      };

      for (const level of ["debug", "log", "info", "warn", "error"]) {
        const original = console[level];
        console[level] = function(...values) {
          post(level, values);
          return original.apply(this, values);
        };
      }

      const diagnostics = (phase) => {
        const connection = navigator.connection || navigator.webkitConnection || navigator.mozConnection;
        let localStorageAvailable = false;
        try {
          localStorageAvailable = !!window.localStorage;
        } catch (_) {}

        post("debug", [{
          phase,
          userAgent: navigator.userAgent,
          cookieEnabled: navigator.cookieEnabled,
          webdriver: navigator.webdriver,
          saveData: connection ? connection.saveData : null,
          effectiveType: connection ? connection.effectiveType : null,
          hardwareConcurrency: navigator.hardwareConcurrency,
          language: navigator.language,
          languages: navigator.languages,
          localStorageAvailable,
          url: location.href
        }], "diagnostic");
      };

      diagnostics("document-start");
      window.addEventListener("DOMContentLoaded", () => diagnostics("dom-content-loaded"), { once: true });
      window.addEventListener("load", () => diagnostics("window-load"), { once: true });
    })();
    """#

    private static let videoSkipPromptScript = #"""
    (() => {
      if (window.__browserVideoSkipPromptInstalled) return;
      window.__browserVideoSkipPromptInstalled = true;

      const rootId = "__browserVideoSkipPrompt";
      const scanDelayMs = 250;
      const intervalMs = 1000;
      const labels = [
        "skip video",
        "skip intro",
        "next episode"
      ];
      const clickableSelector = [
        "button",
        "a[href]",
        "[role='button']",
        "[role='link']",
        "[tabindex]",
        "[onclick]",
        "[data-uia]",
        "[aria-label]",
        "[title]"
      ].join(",");
      const ignoredTextEntryTypes = new Set([
        "email",
        "number",
        "password",
        "search",
        "tel",
        "text",
        "url"
      ]);

      let activeTarget = null;
      let scanTimer = 0;

      const normalize = value => String(value || "")
        .replace(/\s+/g, " ")
        .trim()
        .toLowerCase();

      const getRoot = () => {
        let root = document.getElementById(rootId);
        if (root) return root;

        root = document.createElement("div");
        root.id = rootId;
        root.setAttribute("aria-hidden", "true");
        Object.assign(root.style, {
          position: "fixed",
          left: "0",
          top: "0",
          zIndex: "2147483647",
          pointerEvents: "none",
          display: "none",
          padding: "5px 8px",
          borderRadius: "999px",
          border: "1px solid rgba(255, 255, 255, 0.22)",
          background: "rgba(8, 10, 13, 0.88)",
          color: "white",
          boxShadow: "0 8px 24px rgba(0, 0, 0, 0.36)",
          font: "600 12px -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif",
          lineHeight: "1",
          letterSpacing: "0",
          whiteSpace: "nowrap",
          backdropFilter: "blur(14px)",
          WebkitBackdropFilter: "blur(14px)"
        });

        const key = document.createElement("span");
        key.textContent = "S";
        Object.assign(key.style, {
          display: "inline-flex",
          alignItems: "center",
          justifyContent: "center",
          minWidth: "18px",
          height: "18px",
          marginRight: "6px",
          borderRadius: "5px",
          background: "rgba(255, 255, 255, 0.16)",
          boxShadow: "inset 0 -1px 0 rgba(0, 0, 0, 0.32)",
          fontSize: "11px"
        });

        const label = document.createElement("span");
        label.textContent = "Skip";

        root.append(key, label);
        (document.documentElement || document.body).appendChild(root);
        return root;
      };

      const hidePrompt = () => {
        const root = document.getElementById(rootId);
        if (root) root.style.display = "none";
        activeTarget = null;
      };

      const isVisible = element => {
        if (!(element instanceof Element) || element.id === rootId) return false;

        const style = getComputedStyle(element);
        if (style.display === "none" || style.visibility === "hidden" || Number(style.opacity) === 0) return false;

        const rect = element.getBoundingClientRect();
        if (rect.width < 10 || rect.height < 10) return false;
        if (rect.bottom <= 0 || rect.right <= 0 || rect.top >= innerHeight || rect.left >= innerWidth) return false;

        return true;
      };

      const elementText = element => normalize([
        element.innerText,
        element.textContent,
        element.getAttribute("aria-label"),
        element.getAttribute("title"),
        element.getAttribute("data-uia"),
        element.getAttribute("data-testid")
      ].filter(Boolean).join(" "));

      const scoreElement = element => {
        if (!isVisible(element)) return 0;

        const text = elementText(element);
        if (!text) return 0;

        let score = 0;
        for (const label of labels) {
          if (text === label) score = Math.max(score, 100);
          else if (text.includes(label)) score = Math.max(score, 80);
        }

        if (!score) return 0;

        const tagName = element.tagName.toLowerCase();
        const role = normalize(element.getAttribute("role"));
        if (tagName === "button" || role === "button") score += 20;
        if (element.disabled || element.getAttribute("aria-disabled") === "true") score -= 50;
        if (element.closest("nav, header, footer")) score -= 15;

        return score;
      };

      const candidateElements = () => {
        const elements = new Set();
        for (const element of document.querySelectorAll(clickableSelector)) {
          elements.add(element);
          const actionableParent = element.closest("button, a[href], [role='button'], [onclick]");
          if (actionableParent) elements.add(actionableParent);
        }
        return [...elements];
      };

      const findTarget = () => candidateElements()
        .map(element => ({ element, score: scoreElement(element) }))
        .filter(candidate => candidate.score > 0)
        .sort((a, b) => b.score - a.score)[0]?.element || null;

      const positionPrompt = target => {
        if (!isVisible(target)) {
          hidePrompt();
          return;
        }

        const root = getRoot();
        root.style.display = "inline-flex";
        root.style.alignItems = "center";

        const targetRect = target.getBoundingClientRect();
        const promptRect = root.getBoundingClientRect();
        const gap = 8;
        let left = targetRect.right + gap;
        let top = targetRect.top + ((targetRect.height - promptRect.height) / 2);

        if (left + promptRect.width > innerWidth - gap) {
          left = targetRect.left - promptRect.width - gap;
        }

        if (left < gap) {
          left = Math.min(Math.max(targetRect.left, gap), innerWidth - promptRect.width - gap);
          top = targetRect.top - promptRect.height - gap;
        }

        top = Math.min(Math.max(top, gap), innerHeight - promptRect.height - gap);
        root.style.transform = `translate(${Math.round(left)}px, ${Math.round(top)}px)`;
      };

      const scan = () => {
        scanTimer = 0;

        if (!document.documentElement || !document.body) {
          hidePrompt();
          return;
        }

        const target = findTarget();
        activeTarget = target;

        if (!target) {
          hidePrompt();
          return;
        }

        positionPrompt(target);
      };

      const scheduleScan = () => {
        if (scanTimer) return;
        scanTimer = window.setTimeout(scan, scanDelayMs);
      };

      const clickTarget = target => {
        const clickable = target.closest("button, a[href], [role='button'], [onclick]") || target;
        clickable.dispatchEvent(new MouseEvent("mousemove", { bubbles: true, cancelable: true, view: window }));
        clickable.dispatchEvent(new MouseEvent("mousedown", { bubbles: true, cancelable: true, view: window }));
        clickable.dispatchEvent(new MouseEvent("mouseup", { bubbles: true, cancelable: true, view: window }));
        clickable.click();
      };

      const isEditingText = element => {
        if (!(element instanceof Element)) return false;
        if (element.isContentEditable) return true;

        const tagName = element.tagName.toLowerCase();
        if (tagName === "textarea" || tagName === "select") return true;
        if (tagName !== "input") return false;

        const type = normalize(element.getAttribute("type") || "text");
        return ignoredTextEntryTypes.has(type);
      };

      const isTextEntryEvent = event => {
        const path = typeof event.composedPath === "function" ? event.composedPath() : [event.target];
        return path.some(isEditingText) || isEditingText(document.activeElement);
      };

      const onKeyDown = event => {
        if (event.defaultPrevented || event.metaKey || event.altKey || event.ctrlKey) return;
        if (normalize(event.key) !== "s") return;
        if (isTextEntryEvent(event)) return;

        const target = activeTarget && scoreElement(activeTarget) > 0 ? activeTarget : findTarget();
        if (!target) return;

        event.preventDefault();
        event.stopPropagation();
        clickTarget(target);
        window.setTimeout(scan, 200);
      };

      const isPromptMutation = record => {
        const target = record.target;
        return target instanceof Element && (target.id === rootId || !!target.closest(`#${rootId}`));
      };

      const observer = new MutationObserver(records => {
        if (!records.every(isPromptMutation)) scheduleScan();
      });
      const start = () => {
        observer.observe(document.documentElement, {
          childList: true,
          subtree: true,
          attributes: true,
          attributeFilter: ["aria-label", "class", "disabled", "hidden", "role", "style", "title"]
        });

        document.addEventListener("keydown", onKeyDown, true);
        window.addEventListener("resize", scheduleScan);
        window.addEventListener("scroll", scheduleScan, true);
        window.setInterval(scan, intervalMs);
        scan();
      };

      if (document.documentElement && document.body) {
        start();
      } else {
        document.addEventListener("DOMContentLoaded", start, { once: true });
      }
    })();
    """#

}

final class BrowserConsoleScriptMessageHandler: NSObject, WKScriptMessageHandler {
    weak var browser: BrowserState?

    init(browser: BrowserState) {
        self.browser = browser
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        Task { @MainActor [weak browser] in
            browser?.receiveConsoleMessage(message.body)
        }
    }
}
