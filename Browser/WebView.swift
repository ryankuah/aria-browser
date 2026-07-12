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
    private let webViewHost = NSView(frame: .zero)
    private var hostedWebView: BrowserWebView?
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
        webViewHost.translatesAutoresizingMaskIntoConstraints = true
        webViewHost.autoresizingMask = [.width, .height]
        webViewHost.frame = bounds
        addSubview(webViewHost)
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
        hostedWebView?.removeFromSuperview()
        hostedWebView = webView
        isMountNotificationPending = false

        guard let webView else {
            return
        }

        webView.occlusionRects = occlusionRects
        webView.removeFromSuperview()
        webView.translatesAutoresizingMaskIntoConstraints = true
        webView.autoresizingMask = [.width, .height]
        webView.frame = webViewHost.bounds
        webViewHost.addSubview(webView)
        fullscreenObservation = webView.observe(\.fullscreenState, options: [.new]) { [weak self] webView, _ in
            DispatchQueue.main.async {
                guard !webView.isElementFullscreenTransitionActive else {
                    return
                }

                self?.applyPendingWebViewIfReady()
            }
        }

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
        webViewHost.frame = bounds
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
              hostedWebView.superview === webViewHost,
              window != nil else {
            return
        }

        layoutSubtreeIfNeeded()

        guard hostedWebView.bounds.width > 1,
              hostedWebView.bounds.height > 1 else {
            return
        }

        hostedWebView.frame = webViewHost.bounds
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
    // Safari deliberately freezes the macOS token at 10_15_7 and reports a fixed
    // WebKit build rather than leaking the host OS version; we mirror that exactly
    // so sites treat us like Safari. Keep the version tokens in one place so the
    // full UA and the `applicationNameForUserAgent` suffix can never drift apart.
    private static let webKitBuildToken = "AppleWebKit/605.1.15 (KHTML, like Gecko)"
    static let safariUserAgentSuffix = "Version/18.0 Safari/605.1.15"
    static let desktopSafariUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) \(webKitBuildToken) \(safariUserAgentSuffix)"
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
        autofillMessageHandler: WKScriptMessageHandler? = nil,
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
        if let autofillMessageHandler {
            userContentController.add(autofillMessageHandler, contentWorld: .defaultClient, name: "browserAutofill")
        }
        installConfiguredUserScripts(
            on: userContentController,
            includeConsoleBridge: consoleMessageHandler != nil,
            includeAutofillBridge: autofillMessageHandler != nil,
            userScripts: userScripts
        )
    }

    static func replaceConfiguredUserScripts(
        on userContentController: WKUserContentController,
        includeConsoleBridge: Bool,
        includeAutofillBridge: Bool,
        userScripts: [BrowserUserScript]
    ) {
        userContentController.removeAllUserScripts()
        installConfiguredUserScripts(
            on: userContentController,
            includeConsoleBridge: includeConsoleBridge,
            includeAutofillBridge: includeAutofillBridge,
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
        let rectsJSON = rectsJSONLiteral(for: rects)

        return #"""
        (() => {
          const rootId = "__browserPointerShields";
          const rects = \#(rectsJSON);
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
    }

    /// Serializes the shield rects as a JSON array literal that can be embedded
    /// directly into the injected script. Using `JSONSerialization` keeps the
    /// payload well-formed regardless of the values instead of hand-splicing
    /// numbers into a string template.
    private static func rectsJSONLiteral(for rects: [CGRect]) -> String {
        let payload = rects.map { rect in
            [
                "left": Double(rect.minX),
                "top": Double(rect.minY),
                "width": Double(rect.width),
                "height": Double(rect.height)
            ]
        }

        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else {
            return "[]"
        }

        return json
    }

    private static func installConfiguredUserScripts(
        on userContentController: WKUserContentController,
        includeConsoleBridge: Bool,
        includeAutofillBridge: Bool,
        userScripts: [BrowserUserScript]
    ) {
        if includeConsoleBridge {
            userContentController.addUserScript(WKUserScript(
                source: consoleBridgeScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false
            ))
        }

        if includeAutofillBridge {
            userContentController.addUserScript(WKUserScript(
                source: autofillBridgeScript,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: false,
                in: .defaultClient
            ))
        }

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

    private static let autofillBridgeScript = #"""
    (() => {
      if (window.__browserAutofillBridgeInstalled) return;
      window.__browserAutofillBridgeInstalled = true;

      const autofillAttribute = "data-browser-autofill-id";
      const reportedForms = new Map();
      let scanTimer = null;

      const post = payload => {
        try {
          window.webkit.messageHandlers.browserAutofill.postMessage({
            ...payload,
            origin: String(location.origin),
            href: String(location.href)
          });
        } catch (_) {}
      };

      const normalized = value => String(value || "").toLowerCase();
      const fieldSignature = field => normalized([
        field.name,
        field.id,
        field.autocomplete,
        field.placeholder,
        field.getAttribute("aria-label")
      ].filter(Boolean).join(" "));

      const isVisible = element => {
        if (!(element instanceof HTMLElement)) return false;
        if (element.disabled || element.readOnly || element.type === "hidden") return false;
        const style = window.getComputedStyle(element);
        if (style.visibility === "hidden" || style.display === "none") return false;
        const rect = element.getBoundingClientRect();
        return rect.width > 0 && rect.height > 0;
      };

      const isIgnoredPassword = field => {
        const signature = fieldSignature(field);
        return /\b(one-time-code|otp|2fa|mfa|verification|verify|code|pin)\b/.test(signature) ||
          /\b(new-password|new password|confirm|confirmation|repeat|reset)\b/.test(signature);
      };

      const isPasswordField = field => {
        return field instanceof HTMLInputElement &&
          normalized(field.type) === "password" &&
          isVisible(field) &&
          !isIgnoredPassword(field);
      };

      const isUsernameCandidate = field => {
        if (!(field instanceof HTMLInputElement)) return false;
        const type = normalized(field.type || "text");
        if (!["text", "email", "search", "tel", "url", ""].includes(type)) return false;
        if (!isVisible(field)) return false;
        const signature = fieldSignature(field);
        return !/\b(one-time-code|otp|2fa|mfa|verification|verify|code|pin|captcha|search)\b/.test(signature);
      };

      const usernameScore = field => {
        const signature = fieldSignature(field);
        let score = 0;
        if (normalized(field.type) === "email") score += 20;
        if (/\b(email|e-mail|username|user name|login|account|identifier)\b/.test(signature)) score += 16;
        if (/\b(user|mail)\b/.test(signature)) score += 8;
        if (field.autocomplete && /username|email/.test(normalized(field.autocomplete))) score += 12;
        return score;
      };

      const ownerFor = passwordField => {
        return passwordField.form ||
          passwordField.closest("form,[role='form'],[data-testid*='login' i],[class*='login' i],[class*='signin' i],[class*='sign-in' i]") ||
          passwordField.closest("section,main,article,div") ||
          document.body;
      };

      const controlsIn = owner => {
        return Array.from(owner.querySelectorAll("input")).filter(field => field instanceof HTMLInputElement);
      };

      const fieldName = field => {
        return field.name || field.id || field.autocomplete || field.getAttribute("aria-label") || "";
      };

      const ensureFormID = owner => {
        let id = owner.getAttribute(autofillAttribute);
        if (!id) {
          id = (crypto && crypto.randomUUID) ? crypto.randomUUID() : `${Date.now()}-${Math.random().toString(16).slice(2)}`;
          owner.setAttribute(autofillAttribute, id);
        }
        return id;
      };

      const detectOwner = owner => {
        if (!(owner instanceof Element)) return null;
        const controls = controlsIn(owner);
        const passwordFields = controls.filter(isPasswordField);
        if (passwordFields.length !== 1) return null;

        const passwordField = passwordFields[0];
        const usernameCandidates = controls
          .filter(isUsernameCandidate)
          .filter(field => field.compareDocumentPosition(passwordField) & Node.DOCUMENT_POSITION_FOLLOWING);

        if (usernameCandidates.length === 0) return null;

        usernameCandidates.sort((left, right) => usernameScore(right) - usernameScore(left));
        const usernameField = usernameCandidates[0];
        return {
          owner,
          formID: ensureFormID(owner),
          usernameField,
          passwordField,
          usernameFieldName: fieldName(usernameField),
          passwordFieldName: fieldName(passwordField)
        };
      };

      const detectFromPasswordField = passwordField => detectOwner(ownerFor(passwordField));

      const reportDetected = detected => {
        const signature = `${detected.usernameFieldName}|${detected.passwordFieldName}`;
        if (reportedForms.get(detected.formID) === signature) return;
        reportedForms.set(detected.formID, signature);
        post({
          type: "formDetected",
          formID: detected.formID,
          usernameFieldName: detected.usernameFieldName,
          passwordFieldName: detected.passwordFieldName
        });
      };

      const scan = () => {
        scanTimer = null;
        const seen = new Set();
        for (const passwordField of Array.from(document.querySelectorAll("input[type='password']"))) {
          const detected = detectFromPasswordField(passwordField);
          if (!detected || seen.has(detected.formID)) continue;
          seen.add(detected.formID);
          reportDetected(detected);
        }
      };

      const scheduleScan = () => {
        if (scanTimer !== null) return;
        scanTimer = window.setTimeout(scan, 150);
      };

      const setValue = (field, value) => {
        const prototype = Object.getPrototypeOf(field);
        const descriptor = Object.getOwnPropertyDescriptor(prototype, "value");
        if (descriptor && descriptor.set) {
          descriptor.set.call(field, value);
        } else {
          field.value = value;
        }
        try {
          field.dispatchEvent(new InputEvent("input", { bubbles: true, inputType: "insertReplacementText" }));
        } catch (_) {
          field.dispatchEvent(new Event("input", { bubbles: true }));
        }
        field.dispatchEvent(new Event("change", { bubbles: true }));
      };

      window.__browserAutofillFill = payload => {
        if (!payload || typeof payload.formID !== "string") return false;
        const owner = Array.from(document.querySelectorAll(`[${autofillAttribute}]`))
          .find(element => element.getAttribute(autofillAttribute) === payload.formID);
        const detected = owner ? detectOwner(owner) : null;
        if (!detected) return false;

        setValue(detected.usernameField, String(payload.username || ""));
        setValue(detected.passwordField, String(payload.password || ""));
        return true;
      };

      document.addEventListener("submit", event => {
        const form = event.target instanceof HTMLFormElement ? event.target : null;
        if (!form) return;
        const detected = detectOwner(form);
        if (!detected) return;

        const username = String(detected.usernameField.value || "").trim();
        const password = String(detected.passwordField.value || "");
        if (!username || !password) return;

        post({
          type: "credentialsSubmitted",
          formID: detected.formID,
          username,
          password,
          usernameFieldName: detected.usernameFieldName,
          passwordFieldName: detected.passwordFieldName
        });
      }, true);

      document.addEventListener("focusin", scheduleScan, true);
      window.addEventListener("load", scheduleScan, { once: true });
      if (document.readyState === "loading") {
        document.addEventListener("DOMContentLoaded", scheduleScan, { once: true });
      } else {
        scheduleScan();
      }

      const observer = new MutationObserver(scheduleScan);
      observer.observe(document.documentElement, { childList: true, subtree: true });
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

final class BrowserAutofillScriptMessageHandler: NSObject, WKScriptMessageHandler {
    weak var browser: BrowserState?

    init(browser: BrowserState) {
        self.browser = browser
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        Task { @MainActor [weak browser] in
            browser?.receiveAutofillMessage(
                message.body,
                webView: message.webView as? BrowserWebView,
                frameInfo: message.frameInfo
            )
        }
    }
}
