import AppKit
import SwiftUI

struct BrowserFullSettingsPage: View {
    @ObservedObject var browser: BrowserState
    let onClose: () -> Void

    @State private var isAddingUserScript = false
    @State private var editingUserScriptID: BrowserUserScript.ID?
    @State private var userScriptDraft = FullSettingsUserScriptDraft()

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
                if browser.userScripts.isEmpty && !isAddingUserScript {
                    SettingsEmptyRow(
                        systemName: "curlybraces",
                        message: "No user scripts yet. Add one to run custom JavaScript on pages you visit."
                    )
                }

                ForEach(browser.userScripts) { script in
                    FullSettingsUserScriptRow(
                        script: script,
                        isEditing: editingUserScriptID == script.id,
                        onEnabledChange: { isEnabled in
                            browser.setUserScriptEnabled(id: script.id, isEnabled: isEnabled)
                        },
                        onEdit: {
                            startEditingUserScript(script)
                        },
                        onDelete: {
                            deleteUserScript(script)
                        }
                    )
                }

                if isAddingUserScript || editingUserScript != nil {
                    FullSettingsUserScriptEditor(
                        title: isAddingUserScript ? "New Script" : "Edit Script",
                        draft: $userScriptDraft,
                        onSave: saveUserScriptDraft,
                        onCancel: cancelUserScriptEditor
                    )
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                HStack {
                    SettingsActionButton(
                        title: isAddingUserScript ? "Cancel" : "Add Script",
                        systemName: isAddingUserScript ? "xmark" : "plus"
                    ) {
                        if isAddingUserScript {
                            cancelUserScriptEditor()
                        } else {
                            startAddingUserScript()
                        }
                    }

                    Spacer(minLength: 0)
                }
                .padding(.top, 2)
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

    private var editingUserScript: BrowserUserScript? {
        guard let editingUserScriptID else {
            return nil
        }

        return browser.userScripts.first { $0.id == editingUserScriptID }
    }

    private func startAddingUserScript() {
        withAnimation(.easeInOut(duration: 0.14)) {
            editingUserScriptID = nil
            isAddingUserScript = true
            userScriptDraft = FullSettingsUserScriptDraft()
        }
    }

    private func startEditingUserScript(_ script: BrowserUserScript) {
        withAnimation(.easeInOut(duration: 0.14)) {
            isAddingUserScript = false
            editingUserScriptID = script.id
            userScriptDraft = FullSettingsUserScriptDraft(script: script)
        }
    }

    private func cancelUserScriptEditor() {
        withAnimation(.easeInOut(duration: 0.14)) {
            isAddingUserScript = false
            editingUserScriptID = nil
            userScriptDraft = FullSettingsUserScriptDraft()
        }
    }

    private func saveUserScriptDraft() {
        guard userScriptDraft.canSave else {
            return
        }

        if isAddingUserScript {
            browser.createUserScript(
                name: userScriptDraft.name,
                matchPatterns: userScriptDraft.matchPatterns,
                source: userScriptDraft.source,
                isEnabled: userScriptDraft.isEnabled,
                injectionTime: userScriptDraft.injectionTime,
                forMainFrameOnly: userScriptDraft.forMainFrameOnly
            )
        } else if let editingUserScriptID {
            browser.updateUserScript(
                id: editingUserScriptID,
                name: userScriptDraft.name,
                matchPatterns: userScriptDraft.matchPatterns,
                source: userScriptDraft.source,
                isEnabled: userScriptDraft.isEnabled,
                injectionTime: userScriptDraft.injectionTime,
                forMainFrameOnly: userScriptDraft.forMainFrameOnly
            )
        }

        cancelUserScriptEditor()
    }

    private func deleteUserScript(_ script: BrowserUserScript) {
        withAnimation(.easeInOut(duration: 0.14)) {
            if editingUserScriptID == script.id {
                editingUserScriptID = nil
                userScriptDraft = FullSettingsUserScriptDraft()
            }
            isAddingUserScript = false
            browser.deleteUserScript(id: script.id)
        }
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

private struct FullSettingsLabel: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .kerning(0.4)
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

private struct FullSettingsUserScriptDraft: Equatable {
    var name = "New Script"
    var matchPatterns = BrowserUserScript.defaultMatchPatterns
    var source = BrowserUserScript.defaultSource
    var isEnabled = true
    var injectionTime: BrowserUserScriptInjectionTime = .documentEnd
    var forMainFrameOnly = true

    init() {}

    init(script: BrowserUserScript) {
        name = script.name
        matchPatterns = script.matchPatterns
        source = script.source
        isEnabled = script.isEnabled
        injectionTime = script.injectionTime
        forMainFrameOnly = script.forMainFrameOnly
    }

    var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !matchPatterns.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

private struct FullSettingsUserScriptRow: View {
    let script: BrowserUserScript
    let isEditing: Bool
    let onEnabledChange: (Bool) -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

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

            Button(action: onEdit) {
                Image(systemName: "pencil")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .cursor(.pointingHand)
            .accessibilityLabel("Edit \(script.displayName)")
            .help("Edit")

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .cursor(.pointingHand)
            .accessibilityLabel("Delete \(script.displayName)")
            .help("Delete")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isEditing ? Color.primary.opacity(0.1) : Color.primary.opacity(0.04))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(isEditing ? 0.1 : 0.05), lineWidth: 1)
        }
    }

    private var detailText: String {
        let patterns = script.normalizedMatchPatternLines.joined(separator: ", ")
        let frameScope = script.forMainFrameOnly ? "main frame" : "all frames"
        return "\(patterns) - \(frameScope)"
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

private struct FullSettingsUserScriptEditor: View {
    let title: String
    @Binding var draft: FullSettingsUserScriptDraft
    let onSave: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))

                Spacer()

                Toggle("Enabled", isOn: $draft.isEnabled)
                    .font(.system(size: 12, weight: .medium))
                    .toggleStyle(.switch)
            }

            VStack(alignment: .leading, spacing: 6) {
                FullSettingsLabel("Name")
                FullSettingsTextField(text: $draft.name)
            }

            VStack(alignment: .leading, spacing: 6) {
                FullSettingsLabel("Match Patterns")
                FullSettingsTextEditor(text: $draft.matchPatterns, minHeight: 58, isMonospaced: false)
            }

            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    FullSettingsLabel("Run At")
                    SettingsSegmentedControl {
                        ForEach(BrowserUserScriptInjectionTime.allCases, id: \.rawValue) { injectionTime in
                            SettingsSegmentButton(
                                title: injectionTime.label,
                                isSelected: draft.injectionTime == injectionTime
                            ) {
                                draft.injectionTime = injectionTime
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    FullSettingsLabel("Scope")
                    Toggle("Main Frame Only", isOn: $draft.forMainFrameOnly)
                        .font(.system(size: 12, weight: .medium))
                        .toggleStyle(.switch)
                        .frame(height: 34)
                }

                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 6) {
                FullSettingsLabel("Source")
                FullSettingsTextEditor(text: $draft.source, minHeight: 220, isMonospaced: true)
            }

            HStack(spacing: 8) {
                SettingsActionButton(title: "Save", systemName: "checkmark") {
                    onSave()
                }
                .disabled(!draft.canSave)

                SettingsActionButton(title: "Cancel", systemName: "xmark") {
                    onCancel()
                }

                Spacer(minLength: 0)
            }
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.09), lineWidth: 1)
        }
    }
}

private struct FullSettingsTextField: View {
    @Binding var text: String

    var body: some View {
        TextField("", text: $text)
            .textFieldStyle(.plain)
            .font(.system(size: 12))
            .padding(.horizontal, 9)
            .frame(height: 32)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            }
    }
}

private struct FullSettingsTextEditor: View {
    @Binding var text: String
    let minHeight: CGFloat
    let isMonospaced: Bool

    var body: some View {
        TextEditor(text: $text)
            .font(isMonospaced ? .system(size: 12, design: .monospaced) : .system(size: 12))
            .scrollContentBackground(.hidden)
            .padding(6)
            .frame(minHeight: minHeight)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }
}
