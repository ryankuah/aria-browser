import Foundation

struct BrowserUserScriptLoadResult {
    let scripts: [BrowserUserScript]
}

enum BrowserUserScriptStore {
    static let directoryName = "Userscripts"
    static let bundledVideoControlsFilename = "video-controls.user.js"

    static func directoryURL() throws -> URL {
        let fileManager = FileManager.default
        guard let applicationSupportURL = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw BrowserDatabaseError.invalidApplicationSupportDirectory
        }

        let bundleID = Bundle.main.bundleIdentifier ?? "com.ryankuah.browser"
        return applicationSupportURL
            .appendingPathComponent(bundleID, isDirectory: true)
            .appendingPathComponent(directoryName, isDirectory: true)
    }

    static func prepareAndLoad(
        legacyScripts: [StoredBrowserUserScript],
        shouldExportLegacyScripts: Bool
    ) throws -> BrowserUserScriptLoadResult {
        let directoryURL = try ensureDirectory()

        if shouldExportLegacyScripts {
            for legacyScript in legacyScripts {
                if legacyScript.source.contains("__browserVideoControlsInstalled") {
                    continue
                }

                try exportLegacyScript(legacyScript, to: directoryURL)
            }
        }

        try installBundledVideoControlsIfNeeded(in: directoryURL)
        try installReadmeIfNeeded(in: directoryURL)

        return BrowserUserScriptLoadResult(scripts: try loadScripts(from: directoryURL))
    }

    static func loadScripts() throws -> [BrowserUserScript] {
        try loadScripts(from: ensureDirectory())
    }

    static func directorySignature() throws -> String {
        let directoryURL = try ensureDirectory()
        let fileURLs = try FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        )
        .filter { $0.pathExtension.lowercased() == "js" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }

        return try fileURLs.map { fileURL in
            let values = try fileURL.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            return [
                fileURL.lastPathComponent,
                String(values.fileSize ?? 0),
                String(values.contentModificationDate?.timeIntervalSince1970 ?? 0)
            ].joined(separator: "|")
        }
        .joined(separator: "\n")
    }

    static func setEnabled(_ isEnabled: Bool, for script: BrowserUserScript) throws {
        var lines = script.source.components(separatedBy: .newlines)
        let enabledLine = "// @enabled      \(isEnabled ? "true" : "false")"
        var headerStartIndex: Int?
        var headerEndIndex: Int?
        var enabledIndex: Int?

        for index in lines.indices {
            let trimmedLine = lines[index].trimmingCharacters(in: .whitespaces)
            if trimmedLine == "// ==UserScript==" {
                headerStartIndex = index
            } else if trimmedLine == "// ==/UserScript==" {
                headerEndIndex = index
                break
            } else if headerStartIndex != nil,
                      metadataEntry(from: lines[index])?.key == "enabled" {
                enabledIndex = index
            }
        }

        if let enabledIndex {
            lines[enabledIndex] = enabledLine
        } else if let headerEndIndex {
            lines.insert(enabledLine, at: headerEndIndex)
        } else {
            lines.insert(contentsOf: [
                "// ==UserScript==",
                enabledLine,
                "// ==/UserScript==",
                ""
            ], at: 0)
        }

        try lines.joined(separator: "\n").write(
            to: script.fileURL,
            atomically: true,
            encoding: .utf8
        )
    }

    private static func ensureDirectory() throws -> URL {
        let directoryURL = try directoryURL()
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        return directoryURL
    }

    private static func installBundledVideoControlsIfNeeded(in directoryURL: URL) throws {
        let destinationURL = directoryURL.appendingPathComponent(bundledVideoControlsFilename)
        guard !FileManager.default.fileExists(atPath: destinationURL.path),
              let bundledURL = Bundle.main.url(forResource: "video-controls", withExtension: "js") else {
            return
        }

        try FileManager.default.copyItem(at: bundledURL, to: destinationURL)
    }

    private static func installReadmeIfNeeded(in directoryURL: URL) throws {
        let readmeURL = directoryURL.appendingPathComponent("README.txt")
        guard !FileManager.default.fileExists(atPath: readmeURL.path) else {
            return
        }

        let readme = """
        Browser Userscripts
        ===================

        Put .js files in this folder. Browser reloads them automatically when they change.

        Supported metadata:
          // ==UserScript==
          // @name         My Script
          // @enabled      true
          // @match        <all_urls>
          // @run-at       document-end
          // @frames       all
          // @sidebar-icon star
          // @sidebar-label My Action
          // ==/UserScript==

        Use @noframes or "@frames main" to run only in the main frame. Sidebar icons use
        SF Symbol names. Handle a sidebar button inside the script with:

          browserUserScript.onSidebarAction(() => {
            // Respond to the native sidebar button.
          });

        Start one or more downloads without page CORS restrictions with:

          browserUserScript.download(["https://example.com/image.jpg"]);

        To create a new folder for a batch, pass a folder name:

          browserUserScript.download(urls, { folderName: "Page Images" });
        """
        try readme.write(to: readmeURL, atomically: true, encoding: .utf8)
    }

    private static func exportLegacyScript(
        _ script: StoredBrowserUserScript,
        to directoryURL: URL
    ) throws {
        let baseName = sanitizedFilenameBase(script.name, fallback: "script")
        let legacyID = script.id.uuidString.lowercased().prefix(8)
        let destinationURL = directoryURL.appendingPathComponent("\(baseName)-\(legacyID).user.js")
        guard !FileManager.default.fileExists(atPath: destinationURL.path) else {
            return
        }

        let matches = script.matchPatterns
            .components(separatedBy: CharacterSet(charactersIn: "\n,"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        var metadataLines = [
            "// ==UserScript==",
            "// @name         \(script.name)",
            "// @enabled      \(script.isEnabled ? "true" : "false")"
        ]
        metadataLines.append(contentsOf: matches.map { "// @match        \($0)" })
        metadataLines.append("// @run-at       \(normalizedRunAt(script.injectionTime))")
        if script.forMainFrameOnly {
            metadataLines.append("// @noframes")
        }
        metadataLines.append("// ==/UserScript==")
        metadataLines.append("")
        metadataLines.append(script.source)

        try metadataLines.joined(separator: "\n").write(
            to: destinationURL,
            atomically: true,
            encoding: .utf8
        )
    }

    private static func loadScripts(from directoryURL: URL) throws -> [BrowserUserScript] {
        let fileURLs = try FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        .filter { fileURL in
            fileURL.pathExtension.lowercased() == "js" &&
            (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) != false
        }
        .sorted { left, right in
            left.lastPathComponent.localizedStandardCompare(right.lastPathComponent) == .orderedAscending
        }

        return fileURLs.compactMap { fileURL in
            do {
                let source = try String(contentsOf: fileURL, encoding: .utf8)
                return parseScript(source: source, fileURL: fileURL)
            } catch {
                NSLog("Browser skipped userscript \(fileURL.lastPathComponent): \(error.localizedDescription)")
                return nil
            }
        }
    }

    private static func parseScript(source: String, fileURL: URL) -> BrowserUserScript {
        let metadata = parsedMetadata(from: source)
        let matchPatterns = metadata["match"]?.filter { !$0.isEmpty }
            ?? [BrowserUserScript.defaultMatchPatterns]
        let runAt = metadata["run-at"]?.last?.lowercased()
        let injectionTime: BrowserUserScriptInjectionTime = runAt == "document-start"
            ? .documentStart
            : .documentEnd
        let enabledValue = metadata["enabled"]?.last?.lowercased()
        let isEnabled = !["false", "0", "no", "off"].contains(enabledValue ?? "true")
        let frameValue = metadata["frames"]?.last?.lowercased()
        let forMainFrameOnly = metadata["noframes"] != nil || frameValue == "main"
        let fallbackName = fileURL.deletingPathExtension().lastPathComponent

        return BrowserUserScript(
            id: fileURL.lastPathComponent,
            fileURL: fileURL,
            name: metadata["name"]?.last?.nonEmpty ?? fallbackName,
            matchPatterns: matchPatterns.joined(separator: "\n"),
            source: source,
            isEnabled: isEnabled,
            injectionTime: injectionTime,
            forMainFrameOnly: forMainFrameOnly,
            sidebarIconSystemName: metadata["sidebar-icon"]?.last,
            sidebarLabel: metadata["sidebar-label"]?.last
        )
    }

    private static func parsedMetadata(from source: String) -> [String: [String]] {
        var metadata: [String: [String]] = [:]
        var isInsideHeader = false

        for line in source.components(separatedBy: .newlines) {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            if trimmedLine == "// ==UserScript==" {
                isInsideHeader = true
                continue
            }
            if trimmedLine == "// ==/UserScript==" {
                break
            }
            guard isInsideHeader, let entry = metadataEntry(from: line) else {
                continue
            }

            metadata[entry.key, default: []].append(entry.value)
        }

        return metadata
    }

    private static func metadataEntry(from line: String) -> (key: String, value: String)? {
        let trimmedLine = line.trimmingCharacters(in: .whitespaces)
        guard trimmedLine.hasPrefix("//") else {
            return nil
        }

        let comment = String(trimmedLine.dropFirst(2)).trimmingCharacters(in: .whitespaces)
        guard comment.hasPrefix("@") else {
            return nil
        }

        let content = comment.dropFirst()
        let parts = content.split(maxSplits: 1, whereSeparator: { $0.isWhitespace })
        guard let rawKey = parts.first else {
            return nil
        }

        return (
            key: rawKey.lowercased(),
            value: parts.count > 1 ? String(parts[1]).trimmingCharacters(in: .whitespaces) : ""
        )
    }

    private static func normalizedRunAt(_ rawValue: String) -> String {
        rawValue == BrowserUserScriptInjectionTime.documentStart.rawValue
            ? "document-start"
            : "document-end"
    }

    private static func sanitizedFilenameBase(_ name: String, fallback: String) -> String {
        let words = name.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted)
        return words.filter { !$0.isEmpty }.joined(separator: "-").nonEmpty ?? fallback.lowercased()
    }
}
