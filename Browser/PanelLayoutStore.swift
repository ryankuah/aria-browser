import AppKit
import WebKit

@MainActor
final class PanelLayoutStore: ObservableObject {
    static let shared = PanelLayoutStore()
    @Published private(set) var layout = PanelLayout(panels: [])
    @Published private(set) var scripts: [String: String] = [:]
    @Published private(set) var fileError: String?

    @Published private(set) var scriptReadError: String?
    let directory: URL
    var configURL: URL { directory.appendingPathComponent("ui-config.json") }
    var scriptsURL: URL { directory.appendingPathComponent("PanelScripts", isDirectory: true) }

    init(directory: URL? = nil, defaults: URL? = Bundle.main.url(forResource: "PanelDefaults", withExtension: nil)) {
        self.directory = directory ?? URL.applicationSupportDirectory
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "com.ryankuah.browser", isDirectory: true)
        do {
            let fm = FileManager.default
            guard let defaults else { throw CocoaError(.fileNoSuchFile) }
            layout = try PanelLayout.read(from: defaults.appendingPathComponent("ui-config.json"))
            try fm.createDirectory(at: self.directory, withIntermediateDirectories: true)
            if !fm.fileExists(atPath: scriptsURL.path) {
                try fm.copyItem(at: defaults.appendingPathComponent("PanelScripts"), to: scriptsURL)
            }
            reloadScripts()
            if fm.fileExists(atPath: configURL.path) {
                layout = try PanelLayout.read(from: configURL)
            } else {
                try save(layout)
            }
        } catch {
            fileError = error.localizedDescription
        }
    }

    func save(_ edited: PanelLayout) throws {
        try edited.validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(edited).write(to: configURL, options: .atomic)
        layout = edited
        fileError = nil
    }

    func reloadScripts() {
        do { try readScripts() }
        catch { scriptReadError = error.localizedDescription }
    }

    private func readScripts() throws {
        let files = try FileManager.default.contentsOfDirectory(at: scriptsURL,
            includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
        var loaded: [String: String] = [:]
        var unreadable: [String] = []
        for url in files where url.pathExtension == "js" {
            do {
                guard try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { continue }
                loaded[url.lastPathComponent] = try String(contentsOf: url, encoding: .utf8)
            } catch {
                unreadable.append(url.lastPathComponent)
            }
        }
        scriptReadError = unreadable.isEmpty ? nil : "Cannot read " + unreadable.sorted().joined(separator: ", ")
        if loaded != scripts { scripts = loaded }
    }
}

struct PanelVisibilityInput: Equatable {
    var layout: PanelLayout
    var scripts: [String: String]
    var hoveredEdges: Set<PanelEdge>
    var hoveredPanels: Set<String>
    var tabCount: Int
    var activeDownloadCount: Int
    var host: String
}

// Run editable predicates away from both Swift's UI thread and the browsing
// session. Each worker is disposable, including when a rule never returns.
@MainActor
final class PanelVisibility: ObservableObject {
    @Published private(set) var visible = Set<String>()
    @Published private(set) var errors: [String: String] = [:]
    private let engine: WKWebView
    private let ready: Task<Void, Error>

    init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: .zero, configuration: config)
        engine = view
        ready = Task {
            let html = """
            <meta http-equiv="Content-Security-Policy" content="default-src 'none'; worker-src blob:; script-src 'unsafe-eval'">
            """
            guard view.loadHTMLString(html, baseURL: nil) != nil else { throw URLError(.cannotLoadFromNetwork) }
            while view.isLoading { try await Task.sleep(for: .milliseconds(10)) }
        }
    }

    func update(_ input: PanelVisibilityInput) async {
        do {
            try await ready.value
            try Task.checkCancellation()
            var failures: [String: String] = [:]
            var jobs: [[String: Any]] = []
            for panel in input.layout.panels {
                guard let source = input.scripts[panel.visibility] else {
                    failures[panel.id] = "Missing \(panel.visibility)"
                    continue
                }
                jobs.append(["id": panel.id, "source": source, "state": [
                    "edge": panel.edge.rawValue, "mode": panel.mode.rawValue,
                    "pointerAtEdge": input.hoveredEdges.contains(panel.edge),
                    "pointerInsidePanel": input.hoveredPanels.contains(panel.id),
                    "tabCount": input.tabCount, "activeDownloadCount": input.activeDownloadCount,
                    "host": input.host
                ] as [String: Any]])
            }
            let result = try await engine.callAsyncJavaScript(Self.evaluate, arguments: ["jobs": jobs],
                                                              in: nil, contentWorld: .defaultClient)
            try Task.checkCancellation()
            guard let rows = result as? [[String: String]] else { throw CocoaError(.coderInvalidValue) }
            var shown = Set<String>()
            for row in rows {
                guard let id = row["id"] else { continue }
                if let error = row["error"] { failures[id] = error }
                if row["visible"] == "true" { shown.insert(id) }
            }
            if visible != shown { visible = shown }
            if errors != failures { errors = failures }
        } catch {
            guard !Task.isCancelled else { return }
            visible = []
            errors = ["engine": error.localizedDescription]
        }
    }

    private static let evaluate = #"""
    const code = `onmessage = ({data}) => {
      try {
        const result = Function("state", '"use strict";\\n' + data.source)(Object.freeze(data.state));
        if (typeof result !== "boolean") throw Error("Return true or false.");
        postMessage({visible: String(result)});
      } catch (error) { postMessage({error: String(error)}); }
    }`;
    const url = URL.createObjectURL(new Blob([code], {type: "text/javascript"}));
    try {
      return await Promise.all(jobs.map(job => new Promise(resolve => {
        const worker = new Worker(url);
        function finish(result) {
          clearTimeout(timer);
          worker.terminate();
          resolve({id: job.id, ...result});
        }
        const timer = setTimeout(() => finish({error: "Script timed out."}), 1000);
        worker.onmessage = event => finish(event.data);
        worker.onerror = event => finish({error: event.message || "Script failed."});
        worker.postMessage(job);
      })));
    } finally { URL.revokeObjectURL(url); }
    """#
}
