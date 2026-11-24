import AppKit
import WebKit

/// Reads and writes the layout file and the component files.
@MainActor
final class LayoutStore: ObservableObject {
    static let shared = LayoutStore()
    @Published private(set) var document = LayoutDocument(root: [])
    @Published private(set) var userComponents: [ComponentDefinition] = []
    /// Each loaded component's source, by component name.
    @Published private(set) var sources: [String: String] = [:]
    @Published private(set) var componentErrors: [String: String] = [:]
    @Published private(set) var fileError: String?

    let bundledFiles: [String]
    private let defaults: URL?
    let directory: URL
    var configURL: URL { directory.appendingPathComponent("ui-config.json") }
    var componentsURL: URL { directory.appendingPathComponent("Components", isDirectory: true) }
    private var fileSources: [String: String] = [:]
    private var componentTask: Task<Void, Never>?

    init(directory: URL? = nil, defaults: URL? = Bundle.main.url(forResource: "PanelDefaults", withExtension: nil)) {
        self.defaults = defaults
        bundledFiles = defaults.map {
            (try? FileManager.default.contentsOfDirectory(atPath: $0.appendingPathComponent("Components").path))?
                .filter { $0.hasSuffix(".js") }.sorted() ?? []
        } ?? []
        self.directory = directory ?? URL.applicationSupportDirectory
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "com.ryankuah.browser", isDirectory: true)
        do {
            let fm = FileManager.default
            guard let defaults else { throw CocoaError(.fileNoSuchFile) }
            document = try LayoutDocument.read(from: defaults.appendingPathComponent("ui-config.json"))
            try fm.createDirectory(at: self.directory, withIntermediateDirectories: true)
            let stored = fm.fileExists(atPath: configURL.path) ? Self.storedVersion(at: configURL) ?? 0 : nil
            if let stored, stored < LayoutDocument.currentVersion {
                // Preserve each migration, including a previous backup of the same version.
                func availableBackup(_ name: String) -> URL {
                    let original = self.directory.appendingPathComponent(name)
                    return fm.fileExists(atPath: original.path) ? original.appendingPathExtension(UUID().uuidString) : original
                }
                try fm.copyItem(at: configURL, to: availableBackup("ui-config.v\(stored).json"))
                if fm.fileExists(atPath: componentsURL.path) {
                    try fm.moveItem(at: componentsURL, to: availableBackup("Components.v\(stored)"))
                }
                try installComponents()
                try save(standardLayout())
            } else if stored == nil {
                try installComponents(named: ["Omnibox.js", "Shortcuts.js"])
                try save(document)
            } else {
                document = try LayoutDocument.read(from: configURL)
                try fm.createDirectory(at: componentsURL, withIntermediateDirectories: true)
            }
            let types = try Data(contentsOf: defaults.appendingPathComponent("aria.d.ts"))
            try types.write(to: self.directory.appendingPathComponent("aria.d.ts"), options: .atomic)
            reloadComponents()
        } catch {
            fileError = error.localizedDescription
        }
    }

    func standardLayout() throws -> LayoutDocument {
        guard let defaults else { throw CocoaError(.fileNoSuchFile) }
        return try LayoutDocument.read(from: defaults.appendingPathComponent("standard-layout.json"))
    }

    /// Explicit installation keeps edits and lets removal survive a relaunch.
    func installComponents(named names: [String]? = nil) throws {
        guard let bundled = defaults?.appendingPathComponent("Components") else { throw CocoaError(.fileNoSuchFile) }
        let fm = FileManager.default
        try fm.createDirectory(at: componentsURL, withIntermediateDirectories: true)
        let files = try names ?? fm.contentsOfDirectory(atPath: bundled.path).filter { $0.hasSuffix(".js") }
        for file in files {
            let target = componentsURL.appendingPathComponent(file)
            if !fm.fileExists(atPath: target.path) {
                try fm.copyItem(at: bundled.appendingPathComponent(file), to: target)
            }
        }
    }

    private static func storedVersion(at url: URL) -> Int? {
        struct Probe: Decodable { var version: Int }
        return (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(Probe.self, from: $0).version }
    }

    func save(_ edited: LayoutDocument) throws {
        try edited.validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(edited).write(to: configURL, options: .atomic)
        document = edited
        fileError = nil
    }

    /// Writes a rearranged layout into its component's file, between the layout markers.
    func writeLayout(_ layout: PartLayout, for type: String) throws {
        guard let url = definition(for: type)?.source else { throw CocoaError(.fileNoSuchFile) }
        let source = try String(contentsOf: url, encoding: .utf8)
        try ComponentFile.replacingLayout(in: source, with: layout).write(to: url, atomically: true, encoding: .utf8)
        reloadComponents()
    }

    func definition(for type: String) -> ComponentDefinition? {
        type == LayoutDocument.webViewType ? ComponentCatalog.webView : userComponents.first { $0.type == type }
    }

    var definitions: [ComponentDefinition] { [ComponentCatalog.webView] + userComponents }

    /// Rereads the component files from disk.
    func reloadComponents() {
        let loaded: (files: [String: String], unreadable: [String])
        do {
            loaded = try Self.readFiles(in: componentsURL)
        } catch {
            componentErrors = ["Components": error.localizedDescription]
            return
        }
        guard loaded.files != fileSources || componentTask == nil else { return }
        fileSources = loaded.files
        componentTask?.cancel()
        componentTask = Task { [weak self, files = loaded.files, unreadable = loaded.unreadable, directory = componentsURL] in
            let results = await ScriptSandbox.shared.describeComponents(files)
            guard !Task.isCancelled, let self else { return }
            var definitions: [ComponentDefinition] = []
            var sources: [String: String] = [:]
            var errors = Dictionary(uniqueKeysWithValues: unreadable.map { ($0, "Can’t be read as UTF-8 text.") })
            for (file, result) in results.sorted(by: { $0.key < $1.key }) {
                do {
                    let spec = try JSONDecoder().decode(ComponentCatalog.UserSpec.self, from: Data(try result.get().utf8))
                    var definition = try ComponentCatalog.definition(from: spec, source: directory.appendingPathComponent(file))
                    definition.layoutEditable = definition.layout != nil && ComponentFile.hasLayoutMarkers(files[file] ?? "")
                    if definitions.contains(where: { $0.type == definition.type }) {
                        throw NSError(domain: "Aria.Components", code: 2,
                                      userInfo: [NSLocalizedDescriptionKey: "Another file already defines \(definition.type)."])
                    }
                    definitions.append(definition)
                    sources[definition.type] = files[file]
                } catch let error as DecodingError {
                    errors[file] = "The file describes something Aria doesn’t understand (\(Self.describe(error)))."
                } catch {
                    errors[file] = error.localizedDescription
                }
            }
            self.userComponents = definitions
            self.sources = sources
            self.componentErrors = errors
        }
    }

    private static func describe(_ error: DecodingError) -> String {
        switch error {
        case .keyNotFound(let key, let context): "missing \((context.codingPath + [key]).map(\.stringValue).joined(separator: "."))"
        case .typeMismatch(_, let context), .valueNotFound(_, let context), .dataCorrupted(let context):
            "wrong value at \(context.codingPath.map(\.stringValue).joined(separator: "."))"
        @unknown default: "invalid"
        }
    }

    private static func readFiles(in folder: URL) throws -> (files: [String: String], unreadable: [String]) {
        let urls = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isRegularFileKey],
                                                               options: [.skipsHiddenFiles])
        var files: [String: String] = [:]
        var unreadable: [String] = []
        for url in urls where url.pathExtension == "js" {
            do {
                guard try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { continue }
                files[url.lastPathComponent] = try String(contentsOf: url, encoding: .utf8)
            } catch {
                unreadable.append(url.lastPathComponent)
            }
        }
        return (files, unreadable)
    }
}

/// Runs component files away from both the UI thread and the browsing session.
/// Each job gets its own disposable worker, including when it never returns.
@MainActor
final class ScriptSandbox {
    static let shared = ScriptSandbox()
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

    /// Runs each job and returns its rows: `{id, value}` or `{id, error}`.
    func run(_ jobs: [[String: Any]]) async throws -> [[String: String]] {
        try await ready.value
        guard !jobs.isEmpty else { return [] }
        let result = try await engine.callAsyncJavaScript(Self.evaluate, arguments: ["jobs": jobs],
                                                          in: nil, contentWorld: .defaultClient)
        guard let rows = result as? [[String: String]] else { throw CocoaError(.coderInvalidValue) }
        return rows
    }

    /// Evaluates component files and returns each one's description as JSON.
    func describeComponents(_ sources: [String: String]) async -> [String: Result<String, Error>] {
        let jobs: [[String: Any]] = sources.map { ["id": $0.key, "source": $0.value, "mode": "describe"] }
        do {
            var results: [String: Result<String, Error>] = [:]
            for row in try await run(jobs) {
                guard let id = row["id"] else { continue }
                if let value = row["value"] { results[id] = .success(value) }
                else { results[id] = .failure(NSError(domain: "Aria.Components", code: 3,
                                                       userInfo: [NSLocalizedDescriptionKey: row["error"] ?? "Failed."])) }
            }
            return results
        } catch {
            return sources.mapValues { _ in .failure(error) }
        }
    }

    // Kept free of backticks and dollar-brace, since it sits inside a template literal.
    private static let evaluate = #"""
    const code = `
    "use strict";
    const SECTIONS = ["tabs", "bookmarks", "downloads", "page", "settings", "scripts", "console", "notices"];
    const prop = {
      number: (value = 0, options = {}) => ({ kind: "number", default: value, ...options }),
      choice: (options, value, extra = {}) => ({ kind: "choice", options, default: value ?? options[0], ...extra }),
      toggle: (value = false, options = {}) => ({ kind: "toggle", default: value, ...options }),
      text: (value = "", options = {}) => ({ kind: "text", default: value, ...options }),
    };
    const hover = (options = {}) => ({ kind: "hover", edge: "left", size: 6, ...options });
    const button = (options = {}) => ({ kind: "button", ...options });
    const slot = (name, options = {}) => ({ kind: "slot", name: String(name), direction: "row", ...options });
    const part = (name, options = {}) => ({ kind: "part", name: String(name), ...options });
    const shortcut = keys => ({ kind: "shortcut", keys: String(keys) });
    const when = test => ({ kind: "when", test });
    const stack = kind => (children = [], options = {}) => ({ kind, children, ...options });
    const piece = kind => (options = {}) => ({ kind, ...options });
    const target = kind => name => ({ kind, target: name == null ? "" : String(name) });
    const api = {
      prop, hover, button, slot, part, shortcut, when,
      row: stack("row"), column: stack("column"), layers: stack("layers"),
      scroll: (children = [], options = {}) => ({ kind: "scroll", children, direction: "column", ...options }),
      spacer: piece("spacer"), divider: piece("divider"),
      text: (value, options = {}) => ({ kind: "text", text: String(value), ...options }),
      icon: (name, options = {}) => ({ kind: "icon", icon: String(name), ...options }),
      favicon: (src, options = {}) => ({ kind: "favicon", src: src == null ? "" : String(src), ...options }),
      progress: (value, options = {}) => ({ kind: "progress", ...(value == null ? {} : { value: Number(value) }), ...options }),
      textField: (options = {}) => ({ kind: "textField", ...options }),
      switchControl: (options = {}) => ({ kind: "switch", ...options }),
      dragRegion: piece("dragRegion"),
      windowControls: piece("windowControls"),
      open: target("open"), close: target("close"), toggle: target("toggle"),
      run: (command, arg) => ({ kind: "command", target: String(command), arg }),
      set: (key, value) => ({ kind: "set", target: String(key), arg: value }),
      openTab: address => ({ kind: "openTab", target: String(address) }),
      navigate: address => ({ kind: "navigate", target: String(address) }),
      defineComponent: spec => spec,
    };
    function load(source) {
      const body = source.replace(/^\\s*export\\s+default\\s+/m, "return ");
      const spec = Function(...Object.keys(api), '"use strict";\\n' + body)(...Object.values(api));
      if (!spec || typeof spec !== "object" || typeof spec.name !== "string") throw Error("Export defineComponent({ name: ... }).");
      const activate = spec.activate ?? [];
      if (!Array.isArray(activate) || activate.some(item => !item || typeof item.kind !== "string")) {
        throw Error("activate is a list made with hover(), shortcut() and when().");
      }
      const parts = {};
      for (const [name, value] of Object.entries(spec.parts ?? {})) {
        const entry = typeof value === "function" ? { render: value } : value;
        if (!entry || typeof entry.render !== "function") throw Error("The part " + name + " needs a render function.");
        parts[name] = { title: String(entry.title ?? name), icon: entry.icon == null ? undefined : String(entry.icon),
                        render: entry.render };
      }
      if (spec.layout != null && typeof spec.render === "function") throw Error("Give render, or parts and a layout, not both.");
      const layout = spec.layout == null ? null : layoutData(spec.layout, parts);
      return { ...spec, activate, parts, layout };
    }
    function json(value) {
      if (value === undefined) return null;
      return JSON.parse(JSON.stringify(value));
    }
    function specAction(value, path) {
      if (value == null) return undefined;
      if (typeof value === "function") return { kind: "fn", target: path };
      return action(value, []);
    }
    function specActions(map, prefix) {
      if (map == null) return undefined;
      if (typeof map !== "object") throw Error(prefix + " maps names to actions.");
      const out = {};
      for (const [key, value] of Object.entries(map)) out[key] = specAction(value, prefix + "/" + key);
      return out;
    }
    function describe(spec) {
      const props = Object.entries(spec.props ?? {}).map(([name, p]) => ({ name, ...p }));
      const activate = spec.activate.map(({ test, ...rest }) => rest);
      const parts = Object.entries(spec.parts).map(([name, p]) => ({ name, title: p.title, icon: p.icon }));
      if (spec.uses != null && !Array.isArray(spec.uses)) throw Error("uses is a list, like [\\"tabs\\", \\"page\\"].");
      if (spec.local != null && typeof spec.local !== "object") throw Error("local is an object of starting values.");
      return { ...spec, props, activate, parts, layout: spec.layout ?? undefined,
               keys: specActions(spec.keys, "keys"), handles: specActions(spec.handles, "handles"),
               onOpen: specAction(spec.onOpen, "onOpen"), onClose: specAction(spec.onClose, "onClose"),
               uses: spec.uses == null ? undefined : spec.uses.map(String),
               local: spec.local == null ? undefined : json(spec.local),
               hasRender: typeof spec.render === "function" };
    }
    const layoutKinds = ["row", "column", "spacer", "divider", "part", "slot"];
    function layoutData(node, parts) {
      if (!node || typeof node !== "object" || !layoutKinds.includes(node.kind)) {
        throw Error("layout is made of row, column, spacer, divider, part and slot.");
      }
      const out = { kind: node.kind };
      if (node.kind === "part" || node.kind === "slot") out.name = String(node.name);
      if (node.kind === "part" && !parts[out.name]) throw Error('layout uses part("' + out.name + '"), which parts doesn’t define.');
      for (const key of ["align", "direction"]) if (node[key] != null) out[key] = String(node[key]);
      if (out.direction === "row") delete out.direction;
      for (const key of ["spacing", "width", "height"]) {
        const value = Number(node[key]);
        if (node[key] != null && Number.isFinite(value)) out[key] = value;
      }
      if (node.grow) out.grow = true;
      if (node.padding != null) out.padding = padding(node.padding);
      if (node.kind === "row" || node.kind === "column") {
        out.children = [node.children ?? []].flat(Infinity).filter(child => child != null && child !== false)
          .map(child => layoutData(child, parts));
      }
      return out;
    }
    function renderLayout(node, at, spec, data, fns, problems) {
      const { children, ...rest } = node;
      const out = { ...rest, at };
      if (node.kind === "row" || node.kind === "column") {
        out.children = (children ?? []).map((child, index) =>
          renderLayout(child, at === "" ? String(index) : at + "." + index, spec, data, fns, problems));
      } else if (node.kind === "part") {
        // A part that fails shows a marker, so the rest of the component still works.
        try {
          const found = spec.parts[node.name];
          if (!found) throw Error("parts doesn’t define it.");
          const content = tree(found.render(Object.freeze({ ...data.props }), data.state, data.local), fns);
          if (content && node.grow) content.grow = true;
          out.children = content ? [content] : [];
        } catch (error) {
          problems.push(node.name + ": " + String(error));
          out.children = [{ kind: "icon", icon: "exclamationmark.triangle" }];
        }
      }
      return out;
    }
    function padding(value) {
      if (typeof value === "number") return [value, value];
      if (Array.isArray(value) && value.length === 2) return value.map(Number);
      throw Error("padding is a number or [horizontal, vertical].");
    }
    function action(value, fns) {
      if (typeof value === "function") { fns.push(value); return { kind: "fn", target: "", index: fns.length - 1 }; }
      if (typeof value === "string") return { kind: "command", target: value };
      if (value && typeof value.kind === "string") {
        const out = { kind: value.kind, target: String(value.target ?? "") };
        if (value.arg !== undefined) out.arg = json(value.arg);
        return out;
      }
      throw Error("An action is a command name, run(), set(), open(), close(), toggle() or a function.");
    }
    const stringKeys = ["text", "icon", "label", "help", "style", "align", "name", "direction", "color", "background",
      "hoverBackground", "border", "drag", "weight", "truncate", "bind", "placeholder", "suggest", "src", "followEnd"];
    const numberKeys = ["spacing", "size", "width", "height", "badge", "minWidth", "maxWidth", "minHeight", "maxHeight",
      "cornerRadius", "opacity", "lineLimit", "value"];
    const boolKeys = ["grow", "enabled", "active", "hoverGroup", "showOnHover", "monospaced", "autofocus", "selectAll",
      "on", "indicators"];
    const actionKeys = ["action", "onDrop", "onSubmit", "onChange"];
    function menuItem(item, fns) {
      if (item === "divider") return { divider: true };
      if (!item || typeof item !== "object") throw Error("A menu item is { label, action } or \\"divider\\".");
      const out = { label: String(item.label ?? "") };
      if (item.icon != null) out.icon = String(item.icon);
      if (item.action != null) out.action = action(item.action, fns);
      if (item.destructive != null) out.destructive = Boolean(item.destructive);
      if (item.enabled != null) out.enabled = Boolean(item.enabled);
      return out;
    }
    function tree(node, fns) {
      if (node == null || node === false || node === true) return null;
      if (typeof node === "string" || typeof node === "number") return { kind: "text", text: String(node) };
      if (Array.isArray(node)) return { kind: "column", children: node.flat(Infinity).map(child => tree(child, fns)).filter(Boolean) };
      if (typeof node !== "object" || typeof node.kind !== "string") throw Error("render returned something that isn't a piece.");
      const out = { kind: node.kind };
      for (const key of stringKeys) if (node[key] != null) out[key] = String(node[key]);
      for (const key of numberKeys) {
        const value = Number(node[key]);
        if (node[key] != null && Number.isFinite(value)) out[key] = value;
      }
      for (const key of boolKeys) if (node[key] != null) out[key] = Boolean(node[key]);
      for (const key of actionKeys) if (node[key] != null) out[key] = action(node[key], fns);
      if (node.onKey != null) {
        out.onKey = {};
        for (const [key, value] of Object.entries(node.onKey)) if (value != null) out.onKey[key] = action(value, fns);
      }
      if (node.menu != null) out.menu = [node.menu].flat(Infinity).filter(item => item != null && item !== false).map(item => menuItem(item, fns));
      if (node.padding != null) out.padding = padding(node.padding);
      if (node.popover != null) out.popover = [tree(node.popover, fns)].filter(Boolean);
      if (node.children != null) out.children = [node.children].flat(Infinity).map(child => tree(child, fns)).filter(Boolean);
      return out;
    }
    function render(spec, data, fns, problems = []) {
      const layout = data.layout != null ? JSON.parse(data.layout) : spec.layout;
      if (layout) return renderLayout(layout, "", spec, data, fns, problems);
      if (typeof spec.render !== "function") throw Error("render must be a function.");
      return tree(spec.render(Object.freeze({ ...data.props }), data.state, data.local), fns);
    }
    function freeze(value) {
      if (value && typeof value === "object" && !Object.isFrozen(value)) {
        for (const key of Object.keys(value)) freeze(value[key]);
        Object.freeze(value);
      }
      return value;
    }
    // Parts of the state a component didn't ask for explain how to get them.
    function makeState(raw) {
      const state = { ...(raw ?? {}) };
      for (const name of SECTIONS) {
        if (name in state) continue;
        Object.defineProperty(state, name, { enumerable: false, get() {
          throw Error("state." + name + " needs uses: [\\"" + name + "\\"] in the component's file.");
        } });
      }
      return freeze(state);
    }
    function specFunction(spec, path) {
      const [group, key] = path.split(/\\/(.*)/s);
      const found = key === undefined ? spec[group] : (spec[group] ?? {})[key];
      if (typeof found !== "function") throw Error(path + " is no longer a function.");
      return found;
    }
    onmessage = ({ data }) => {
      try {
        const spec = load(data.source);
        const state = makeState(data.state);
        const local = freeze({ ...(data.local ?? {}) });
        if (data.mode === "describe") {
          postMessage({ value: JSON.stringify(describe(spec)) });
        } else if (data.mode === "render") {
          const conditions = spec.activate.filter(item => item.kind === "when").map(item => {
            if (typeof item.test !== "function") throw Error("when() takes a function.");
            const result = item.test(state, local);
            if (typeof result !== "boolean") throw Error("A when() function must return true or false.");
            return result;
          });
          const problems = [];
          const rendered = render(spec, { ...data, state, local }, [], problems);
          postMessage({ value: JSON.stringify({ tree: rendered, conditions, problems }) });
        } else {
          let fn;
          if (data.path != null) {
            fn = specFunction(spec, data.path);
          } else {
            const fns = [];
            // Recreate the closures behind the displayed rows, even if browser
            // state has already moved on. The callback itself sees current state.
            const snapshot = data.snapshot;
            render(spec, { ...snapshot, state: makeState(snapshot.state), local: freeze(snapshot.local) }, fns);
            fn = fns[data.index];
            if (typeof fn !== "function") throw Error("That button's function no longer exists.");
          }
          const commands = [];
          const now = { ...local };
          const push = (kind, target, arg) => {
            const out = { kind, target: target == null ? "" : String(target) };
            if (arg !== undefined) out.arg = json(arg);
            commands.push(out);
          };
          const setOne = (key, value) => { now[key] = value; push("set", key, value); };
          const aria = {
            open: name => push("open", name), close: name => push("close", name), toggle: name => push("toggle", name),
            run: (command, arg) => push("command", command, arg),
            openTab: address => push("openTab", address), navigate: address => push("navigate", address),
            set: (key, value) => {
              if (key && typeof key === "object") { for (const [k, v] of Object.entries(key)) setOne(k, v); }
              else setOne(String(key), value);
            },
            find: (query, options = {}) => push("command", "find", { query: String(query ?? ""), backwards: Boolean(options.backwards) }),
            copy: text => push("command", "copy", String(text ?? "")),
          };
          fn(aria, state, now, data.event === undefined ? null : data.event);
          postMessage({ value: JSON.stringify(commands) });
        }
      } catch (error) { postMessage({ error: String(error) }); }
    };`;
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

/// The browser state component files can read.
struct RuntimeState: Equatable, Sendable {
    /// Given to every component: the window and the active page, in brief.
    var base: [String: AnyJSON] = [:]
    /// Given to components that name them in `uses`: lists of tabs, downloads and so on.
    var sections: [String: AnyJSON] = [:]

    /// What a component that uses `sections` sees.
    func slice(_ uses: Set<String>) -> [String: AnyJSON] {
        base.merging(sections.filter { uses.contains($0.key) }) { first, _ in first }
    }
}

struct RenderInput: Equatable {
    /// Sources by component name.
    var sources: [String: String]
    /// Prop values with defaults filled in, by component name.
    var props: [String: [String: JSONValue]]
    var state: RuntimeState
    /// Layouts the editor is changing, by component name. They replace the files' own until saved.
    var layouts: [String: PartLayout] = [:]
}

/// Renders component files, keeps each one's own state, and tracks which are open.
@MainActor
final class ComponentRuntime: ObservableObject {
    @Published private(set) var trees: [String: Piece] = [:]
    /// Whether any of a component's when() activators currently returns true.
    @Published private(set) var conditions: [String: Bool] = [:]
    @Published private(set) var errors: [String: String] = [:]
    /// Components opened by a button, shortcut or action, until closed again.
    @Published private(set) var toggled: Set<String> = []
    /// The component holding the button that opened another. It stays open meanwhile.
    @Published private(set) var parents: [String: String] = [:]
    /// Components kept open by a popover showing from one of their buttons, by button.
    @Published private(set) var holds: [String: String] = [:]
    /// Values components set with `set`, by component name. Defaults come from their files.
    @Published private(set) var local: [String: [String: AnyJSON]] = [:]
    /// False until the first render, so components that open on a condition don't flash.
    @Published private(set) var settled = false

    /// Looks up a component's definition, for what it uses and its starting state.
    var definition: (String) -> ComponentDefinition? = { LayoutStore.shared.definition(for: $0) }

    private var latest: RenderInput?
    /// What each component last rendered from. It renders again only when this changes.
    private var rendered: [String: Inputs] = [:]
    private var loop: Task<Void, Never>?
    private var dirty = false

    private struct Inputs: Equatable {
        var source: String
        var props: [String: JSONValue]
        var local: [String: AnyJSON]
        var layout: PartLayout?
        var state: [String: AnyJSON]
    }

    private struct Rendered: Decodable {
        var tree: Piece?
        var conditions: [Bool]
        /// Parts that failed to render.
        var problems: [String]?
    }

    /// Renders whatever the new input changes. Updates arriving meanwhile are coalesced.
    func update(_ input: RenderInput) async {
        latest = input
        schedule()
    }

    private func schedule() {
        dirty = true
        guard loop == nil else { return }
        // Unstructured, so a caller's cancelled task doesn't cut a render short.
        loop = Task { [weak self] in
            while let self, self.dirty {
                self.dirty = false
                guard let input = self.latest else { break }
                await self.renderChanged(input)
            }
            self?.loop = nil
        }
    }

    /// A component's own state: its file's starting values, with what it has set since.
    func localState(_ name: String) -> [String: AnyJSON] {
        (definition(name)?.local ?? [:]).merging(local[name] ?? [:]) { _, set in set }
    }

    /// Sets one key of a component's own state, or removes it when `value` is nil.
    func setLocal(_ name: String, _ key: String, _ value: AnyJSON?) {
        var state = localState(name)
        state[key] = value
        guard local[name] != state else { return }
        local[name] = state
        schedule()
    }

    /// Back to the starting values, as when the component closes.
    func resetLocal(_ name: String) {
        guard local[name] != nil else { return }
        local[name] = nil
        schedule()
    }

    private func inputs(_ name: String, _ input: RenderInput) -> Inputs? {
        guard let source = input.sources[name] else { return nil }
        return Inputs(source: source, props: input.props[name] ?? [:], local: localState(name),
                      layout: input.layouts[name], state: input.state.slice(definition(name)?.uses ?? []))
    }

    private func job(_ name: String, _ inputs: Inputs, mode: String) -> [String: Any] {
        var job: [String: Any] = ["id": name, "source": inputs.source, "mode": mode,
                                  "state": inputs.state.mapValues(\.foundation),
                                  "props": inputs.props.mapValues(\.foundation),
                                  "local": inputs.local.mapValues(\.foundation)]
        if let layout = inputs.layout, let data = try? JSONEncoder().encode(layout) {
            job["layout"] = String(decoding: data, as: UTF8.self)
        }
        return job
    }

    private func renderChanged(_ input: RenderInput) async {
        var changed: [String: Inputs] = [:]
        for name in input.sources.keys {
            if let next = inputs(name, input), rendered[name] != next { changed[name] = next }
        }
        let gone = Set(rendered.keys).subtracting(input.sources.keys)
        guard !changed.isEmpty || !gone.isEmpty else { settled = true; return }
        var trees = self.trees, conditions = self.conditions, errors = self.errors
        for name in gone {
            close(name)
            resetLocal(name)
            holds = holds.filter { $0.value != name }
            trees[name] = nil; conditions[name] = nil; errors[name] = nil; rendered[name] = nil
        }
        do {
            let rows = try await ScriptSandbox.shared.run(changed.map { job($0.key, $0.value, mode: "render") })
            errors["engine"] = nil
            for row in rows {
                guard let name = row["id"] else { continue }
                rendered[name] = changed[name]
                trees[name] = nil
                conditions[name] = nil
                errors[name] = nil
                if let value = row["value"] {
                    do {
                        let result = try JSONDecoder().decode(Rendered.self, from: Data(value.utf8))
                        trees[name] = result.tree ?? Piece(kind: "column")
                        conditions[name] = result.conditions.contains(true)
                        if let problem = result.problems?.first { errors[name] = "Part \(problem)" }
                    } catch {
                        errors[name] = "render returned pieces Aria doesn’t understand."
                    }
                } else {
                    errors[name] = row["error"] ?? "Failed."
                }
            }
        } catch {
            errors["engine"] = error.localizedDescription
        }
        if self.trees != trees { self.trees = trees }
        if self.conditions != conditions { self.conditions = conditions }
        if self.errors != errors { self.errors = errors }
        settled = true
    }

    /// Runs a function from a component file and returns what it asked for. `action` is the
    /// fn action: a button's (by index) or one the spec keeps (by path). `event` is what
    /// happened, like the text typed or what was dropped.
    func call(_ name: String, _ action: PieceAction, event: AnyJSON? = nil) async -> [PieceAction] {
        guard let input = latest, let inputs = inputs(name, input) else { return [] }
        var job = job(name, inputs, mode: "action")
        if let index = action.index {
            guard let displayed = rendered[name], displayed.source == inputs.source else { return [] }
            job["index"] = index
            var snapshot = self.job(name, displayed, mode: "render")
            snapshot.removeValue(forKey: "source")
            job["snapshot"] = snapshot
        } else {
            job["path"] = action.target
        }
        if let event { job["event"] = event.foundation }
        do {
            guard let row = try await ScriptSandbox.shared.run([job]).first else { return [] }
            if let error = row["error"] { report(name, error); return [] }
            return try JSONDecoder().decode([PieceAction].self, from: Data((row["value"] ?? "[]").utf8))
        } catch {
            report(name, error.localizedDescription)
            return []
        }
    }

    func report(_ name: String, _ message: String) {
        errors[name] = message
    }

    func open(_ name: String, in parent: String? = nil) {
        toggled.insert(name)
        parents[name] = parent
    }

    /// Keeps `host` open while a button inside it shows a popover. Nil lets it go.
    func hold(_ button: String, host: String?) {
        if holds[button] != host { holds[button] = host }
    }

    func close(_ name: String) {
        toggled.remove(name)
        parents[name] = nil
        // Whatever it opened closes with it.
        for (child, owner) in parents where owner == name { close(child) }
    }

    func toggle(_ name: String, in parent: String? = nil) {
        if toggled.contains(name) { close(name) } else { open(name, in: parent) }
    }

    func closeAll() {
        for name in toggled { close(name) }
    }
}
