import AppKit
import SwiftUI

struct BrowserFullSettingsPage: View {
    @ObservedObject var browser: BrowserState
    let onClose: () -> Void

    private let contentMaxWidth: CGFloat = 1120
    private let twoColumnThreshold: CGFloat = 860

    var body: some View {
        ZStack {
            BrowserChromeBackground(
                bezelStyle: browser.bezelStyle,
                cornerRadius: 0,
                effect: .liquidGlass(
                    style: .regular,
                    tintColor: NSColor.black.withAlphaComponent(0.16)
                ),
                accentColor: browser.accentNSColor
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                header

                Divider()
                    .opacity(0.45)

                GeometryReader { proxy in
                    let usesTwoColumns = proxy.size.width - 56 >= twoColumnThreshold

                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            if usesTwoColumns {
                                HStack(alignment: .top, spacing: 20) {
                                    VStack(spacing: 20) {
                                        generalCard
                                        passwordsCard
                                    }
                                    .frame(maxWidth: .infinity, alignment: .top)

                                    VStack(spacing: 20) {
                                        appearanceCard
                                    }
                                    .frame(maxWidth: .infinity, alignment: .top)
                                }
                            } else {
                                generalCard
                                passwordsCard
                                appearanceCard
                            }

                            userScriptsCard
                        }
                        .frame(maxWidth: contentMaxWidth, alignment: .leading)
                        .padding(28)
                        .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .scrollIndicators(.visible)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onExitCommand(perform: onClose)
    }

    // MARK: - Cards

    private var generalCard: some View {
        SettingsCard(title: "General", systemName: "magnifyingglass") {
            SettingsField(label: "Search Engine") {
                SettingsSegmentedControl {
                    ForEach(BrowserSearchEngine.allCases, id: \.rawValue) { engine in
                        SettingsSegmentButton(
                            title: engine.label,
                            isSelected: browser.searchEngine == engine
                        ) {
                            browser.setSearchEngine(engine)
                        }
                    }
                }
            }

            SettingsRowDivider()

            SettingsField(label: "Downloads") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "folder")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 16)

                        Text(browser.downloadsDirectoryDisplayPath)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 32)
                    .background {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.primary.opacity(0.05))
                    }

                    HStack(spacing: 8) {
                        SettingsActionButton(title: "Open Folder", systemName: "arrow.up.forward.app") {
                            browser.openDownloadsFolder()
                        }

                        SettingsActionButton(title: "Copy Path", systemName: "doc.on.doc") {
                            browser.copyDownloadsDirectoryPath()
                        }

                        Spacer(minLength: 0)
                    }

                    FullSettingsPreferenceRow(
                        title: "Remove Download Quarantine",
                        systemName: "shield.slash",
                        isOn: browser.isDownloadQuarantineRemovalEnabled
                    ) {
                        browser.setDownloadQuarantineRemovalEnabled(!browser.isDownloadQuarantineRemovalEnabled)
                    }
                }
            }
        }
    }

    private var appearanceCard: some View {
        SettingsCard(title: "Appearance", systemName: "paintpalette") {
            SettingsField(label: "Bezel Style") {
                SettingsSegmentedControl {
                    ForEach(BrowserBezelStyle.availableCases, id: \.rawValue) { style in
                        SettingsSegmentButton(
                            title: style.label,
                            isSelected: browser.bezelStyle == style
                        ) {
                            browser.setBezelStyle(style)
                        }
                    }
                }
            }
        }
    }

    private var passwordsCard: some View {
        SettingsCard(title: "Passwords", systemName: "key.fill") {
            VStack(alignment: .leading, spacing: 12) {
                FullSettingsPreferenceRow(
                    title: "Autofill Passwords",
                    systemName: "rectangle.and.pencil.and.ellipsis",
                    isOn: browser.isPasswordAutofillEnabled
                ) {
                    browser.setPasswordAutofillEnabled(!browser.isPasswordAutofillEnabled)
                }

                SettingsRowDivider()

                FullSettingsPreferenceRow(
                    title: "Offer to Save Passwords",
                    systemName: "plus.circle",
                    isOn: browser.isPasswordSavePromptEnabled
                ) {
                    browser.setPasswordSavePromptEnabled(!browser.isPasswordSavePromptEnabled)
                }

                SettingsRowDivider()

                SettingsField(label: "Saved Passwords") {
                    VStack(alignment: .leading, spacing: 8) {
                        if browser.sortedLoginCredentials.isEmpty {
                            SettingsEmptyRow(
                                systemName: "key.slash",
                                message: "No saved passwords."
                            )
                        } else {
                            ForEach(browser.sortedLoginCredentials) { credential in
                                FullSettingsCredentialRow(credential: credential) {
                                    browser.deleteLoginCredential(id: credential.id)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var userScriptsCard: some View {
        SettingsCard(title: "User Scripts", systemName: "curlybraces") {
            VStack(alignment: .leading, spacing: 10) {
                Text("JavaScript files in this folder are loaded automatically. Use userscript metadata for match rules, run timing, and optional sidebar buttons.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    Image(systemName: "folder")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 16)

                    Text(browser.userScriptsDirectoryDisplayPath)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 10)
                .frame(height: 32)
                .background {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.05))
                }

                HStack(spacing: 8) {
                    SettingsActionButton(title: "Open Folder", systemName: "arrow.up.forward.app") {
                        browser.openUserScriptsFolder()
                    }

                    SettingsActionButton(title: "Reload", systemName: "arrow.clockwise") {
                        browser.refreshUserScripts()
                    }

                    SettingsActionButton(title: "Copy Path", systemName: "doc.on.doc") {
                        browser.copyUserScriptsDirectoryPath()
                    }

                    Spacer(minLength: 0)
                }

                SettingsRowDivider()

                if browser.userScripts.isEmpty {
                    SettingsEmptyRow(
                        systemName: "curlybraces",
                        message: "No .js files found in the Userscripts folder."
                    )
                }

                ForEach(browser.userScripts) { script in
                    FullSettingsUserScriptRow(
                        script: script,
                        onEnabledChange: { isEnabled in
                            browser.setUserScriptEnabled(id: script.id, isEnabled: isEnabled)
                        },
                        onReveal: {
                            browser.revealUserScript(id: script.id)
                        }
                    )
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 15, weight: .semibold))

            Text("Settings")
                .font(.system(size: 16, weight: .semibold))

            Spacer()

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.primary.opacity(0.08))
            }
            .accessibilityLabel("Close Settings")
            .help("Close")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

}

// MARK: - Layout primitives

private struct SettingsCard<Content: View>: View {
    let title: String
    let systemName: String
    let content: Content

    init(title: String, systemName: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemName = systemName
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 9) {
                Image(systemName: systemName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 18)

                Text(title)
                    .font(.system(size: 14, weight: .semibold))
            }

            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
        }
    }
}

private struct SettingsField<Content: View>: View {
    let label: String
    let content: Content

    init(label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .kerning(0.4)

            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SettingsRowDivider: View {
    var body: some View {
        Divider()
            .opacity(0.32)
    }
}

private struct SettingsEmptyRow: View {
    let systemName: String
    let message: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.tertiary)

            Text(message)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.primary.opacity(0.03))
        }
    }
}

private struct SettingsSegmentedControl<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 3) {
            content
        }
        .padding(3)
        .background {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.05), lineWidth: 1)
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}

private struct SettingsSegmentButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                .lineLimit(1)
                .padding(.horizontal, 16)
                .frame(height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? .primary : .secondary)
        .background {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isSelected ? Color.primary.opacity(0.14) : isHovered ? Color.primary.opacity(0.06) : Color.clear)
        }
        .onHover { isHovered = $0 }
        .cursor(.pointingHand)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .help(title)
    }
}

private struct SettingsActionButton: View {
    let title: String
    let systemName: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemName)
                    .font(.system(size: 11, weight: .semibold))

                Text(title)
                    .font(.system(size: 12, weight: .semibold))
            }
            .frame(height: 30)
            .padding(.horizontal, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isHovered ? Color.primary.opacity(0.13) : Color.primary.opacity(0.08))
        }
        .onHover { isHovered = $0 }
        .cursor(.pointingHand)
        .accessibilityLabel(title)
        .help(title)
    }
}

private struct FullSettingsPreferenceRow: View {
    let title: String
    let systemName: String
    let isOn: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 18)

            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            FullSettingsSwitch(isOn: isOn, action: onToggle)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.05), lineWidth: 1)
        }
    }
}

private struct FullSettingsCredentialRow: View {
    let credential: StoredLoginCredential
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "key.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 3) {
                Text(credential.displayHost)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)

                Text(credential.displayUsername)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .cursor(.pointingHand)
            .accessibilityLabel("Delete password for \(credential.displayHost)")
            .help("Delete")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.05), lineWidth: 1)
        }
    }
}

private struct FullSettingsUserScriptRow: View {
    let script: BrowserUserScript
    let onEnabledChange: (Bool) -> Void
    let onReveal: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            FullSettingsSwitch(isOn: script.isEnabled) {
                onEnabledChange(!script.isEnabled)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(script.displayName)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)

                Text(detailText)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(script.injectionTime.label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.horizontal, 8)
                .frame(height: 22)
                .background {
                    Capsule(style: .continuous)
                        .fill(Color.primary.opacity(0.07))
                }

            if let sidebarItem = script.sidebarItem {
                Image(systemName: sidebarItem.systemName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .background {
                        Circle()
                            .fill(Color.primary.opacity(0.07))
                    }
                    .help("Sidebar: \(sidebarItem.label)")
            }

            Button(action: onReveal) {
                Image(systemName: "folder")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .cursor(.pointingHand)
            .accessibilityLabel("Reveal \(script.displayName) in Finder")
            .help("Reveal in Finder")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.05), lineWidth: 1)
        }
    }

    private var detailText: String {
        let patterns = script.normalizedMatchPatternLines.joined(separator: ", ")
        let frameScope = script.forMainFrameOnly ? "main frame" : "all frames"
        return "\(script.fileURL.lastPathComponent) - \(patterns) - \(frameScope)"
    }
}

private struct FullSettingsSwitch: View {
    let isOn: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Capsule()
                .fill(isOn ? Color.accentColor.opacity(isHovered ? 0.95 : 0.82) : Color.primary.opacity(isHovered ? 0.18 : 0.12))
                .frame(width: 34, height: 20)
                .overlay(alignment: isOn ? .trailing : .leading) {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 16, height: 16)
                        .shadow(color: .black.opacity(0.16), radius: 2, y: 1)
                        .padding(2)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .cursor(.pointingHand)
        .accessibilityLabel(isOn ? "Disable Script" : "Enable Script")
        .help(isOn ? "Disable" : "Enable")
    }
}
