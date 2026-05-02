import SwiftUI
import AppKit

struct SettingsView: View {
    @Bindable var store: DataStore

    @State private var budgetText: String = ""
    @State private var dailyBudgetText: String = ""
    @State private var launchAtLogin: Bool = LaunchAtLogin.isEnabled
    @State private var launchStatus: String = LaunchAtLogin.statusDescription
    @State private var iconStyle: IconStyle = Appearance.iconStyle
    @State private var menuBarStyle: MenuBarStyle = Appearance.menuBarStyle
    @State private var bubbleMetric: BubbleMetric = Appearance.bubbleMetric

    var body: some View {
        Form {
            // --- Appearance ----------------------------------------------
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("App icon")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 12) {
                        ForEach(IconStyle.allCases) { style in
                            IconChoice(style: style, isSelected: iconStyle == style) {
                                iconStyle = style
                                Appearance.iconStyle = style
                            }
                        }
                    }
                }
                .padding(.vertical, 4)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Menu bar icon")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 12) {
                        ForEach(MenuBarStyle.allCases) { style in
                            MenuBarChoice(style: style, isSelected: menuBarStyle == style) {
                                menuBarStyle = style
                                Appearance.menuBarStyle = style
                            }
                        }
                    }
                }
                .padding(.vertical, 4)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Floating bubble shows")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    Picker("", selection: Binding(
                        get: { bubbleMetric },
                        set: { newValue in
                            bubbleMetric = newValue
                            Appearance.bubbleMetric = newValue
                        }
                    )) {
                        ForEach(BubbleMetric.allCases) { m in
                            Text(m.displayName).tag(m)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                .padding(.vertical, 4)

                Text("App icon affects Cmd-Tab, About, and notifications. Finder shows the bundled default — to change that, run `swift tools/MakeIcon.swift all <style> && ./build.sh --install`.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("Appearance")
            }

            // --- Usage limit -----------------------------------------------
            Section {
                HStack {
                    TextField("Tokens", text: $budgetText, prompt: Text("e.g. 5_000_000"))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 160)
                        .onSubmit(commitBudget)
                    Button("Apply", action: commitBudget)
                        .keyboardShortcut(.return, modifiers: [])
                    Spacer()
                    if store.usageLimitBudget > 0 {
                        Button("Disable", role: .destructive) {
                            store.usageLimitBudget = 0
                            budgetText = ""
                        }
                    }
                }
                if store.usageLimitBudget > 0 {
                    LabeledContent("Current 5h usage",
                                   value: "\(NumberFormat.grouped(store.aggregates.tokensLast5h)) / \(NumberFormat.grouped(store.usageLimitBudget))")
                    LabeledContent("Progress",
                                   value: NumberFormat.compactPercent(store.usageLimitProgress))
                    LabeledContent("Crossings logged",
                                   value: "\(store.limitEvents.count)")
                    Button("Test confetti now") {
                        store.triggerConfettiNow()
                    }
                    Button("Clear log", role: .destructive) {
                        store.clearLimitEvents()
                    }
                }
                Text("Set the number of tokens you'd consider your 5-hour cap. The bubble's color shifts orange → amber → red as you approach it; confetti when you cross it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("Usage limit (rolling 5 hours)")
            }

            // --- Daily ring goal (Apple Activity-style) -------------------
            Section {
                HStack {
                    TextField("Tokens / day", text: $dailyBudgetText, prompt: Text("e.g. 50_000_000"))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 160)
                        .onSubmit(commitDailyBudget)
                    Button("Apply", action: commitDailyBudget)
                    Spacer()
                    if store.usageLimitDaily > 0 {
                        Button("Disable", role: .destructive) {
                            store.usageLimitDaily = 0
                            dailyBudgetText = ""
                        }
                    }
                }
                if store.usageLimitDaily > 0 {
                    LabeledContent("Today",
                        value: "\(NumberFormat.grouped(store.aggregates.todayTokens)) / \(NumberFormat.grouped(store.usageLimitDaily))")
                    LabeledContent("Progress",
                        value: NumberFormat.compactPercent(Double(store.aggregates.todayTokens) / max(1, Double(store.usageLimitDaily))))
                }
                Text("The bubble's activity ring fills toward this number, like an Apple Health Activity ring. When you exceed it, a second arc stacks on top to show the overflow. Disabled? The ring falls back to today vs your 30-day daily average.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("Daily ring goal")
            }

            // --- Startup --------------------------------------------------
            Section {
                Toggle("Open ClaudeHealth at login", isOn: Binding(
                    get: { launchAtLogin },
                    set: { newValue in
                        LaunchAtLogin.setEnabled(newValue)
                        launchAtLogin = LaunchAtLogin.isEnabled
                        launchStatus = LaunchAtLogin.statusDescription
                    }
                ))
                LabeledContent("Status", value: launchStatus)
                Text("Uses macOS Login Items via SMAppService. If the toggle says \"Needs approval,\" open System Settings → General → Login Items and enable ClaudeHealth.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("Startup")
            }

            // --- Data -----------------------------------------------------
            Section {
                LabeledContent("Records parsed", value: "\(store.aggregates.totalRecords)")
                LabeledContent("Transcript files", value: "\(store.aggregates.totalFiles)")
                LabeledContent("Last parse time", value: "\(store.aggregates.parseDurationMs) ms")
                Button {
                    Task { await store.refresh() }
                } label: {
                    Label("Refresh now", systemImage: "arrow.clockwise")
                }
                .disabled(store.isRefreshing)

                LabeledContent("Cache file") {
                    HStack(spacing: 6) {
                        Text(Cache.url.path)
                            .font(.system(.caption, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Button {
                            NSWorkspace.shared.activateFileViewerSelecting([Cache.url])
                        } label: {
                            Image(systemName: "magnifyingglass")
                        }
                        .buttonStyle(.borderless)
                    }
                }
            } header: {
                Text("Data")
            }

            // --- Help & links ---------------------------------------------
            Section {
                Button {
                    if let url = URL(string: "https://claude.ai/settings/usage") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Label("Open Anthropic plan usage on claude.ai", systemImage: "safari")
                }
                Text("ClaudeHealth only sees Claude Code activity (and Desktop App agent-session metadata). For the unified usage gauge across web chat, Desktop App, Claude Code, and API, Anthropic's own page is the source of truth.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("Help")
            }

            // --- Privacy --------------------------------------------------
            Section {
                privacyRow(label: "Reads",
                           value: "~/.claude/projects/*/*.jsonl",
                           reveal: FileManager.default.homeDirectoryForCurrentUser
                                .appendingPathComponent(".claude/projects"))
                privacyRow(label: "Aggregated cache (0600)",
                           value: Cache.url.path,
                           reveal: Cache.url)
                if let bundleId = Bundle.main.bundleIdentifier {
                    let prefsURL = FileManager.default.homeDirectoryForCurrentUser
                        .appendingPathComponent("Library/Preferences/\(bundleId).plist")
                    privacyRow(label: "Preferences",
                               value: prefsURL.lastPathComponent,
                               reveal: prefsURL)
                }
                Text("ClaudeHealth never opens a network socket and ships no embedded HTTP server. All processing stays on this Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("Privacy")
            }

            // --- Advanced -------------------------------------------------
            Section {
                Button(role: .destructive) {
                    Uninstall.showFlow()
                } label: {
                    Label("Uninstall ClaudeHealth…", systemImage: "trash")
                }
                Text("Removes the cache, preferences, and Login Item registration. You will still need to drag ClaudeHealth.app from /Applications to the Trash afterward.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("Advanced")
            }

            // --- About ----------------------------------------------------
            Section {
                Text("ClaudeHealth reads transcripts from ~/.claude/projects. No data leaves this Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                LabeledContent("Version",
                    value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
            } header: {
                Text("About")
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 520, minHeight: 480)
        .onAppear {
            if store.usageLimitBudget > 0 {
                budgetText = "\(store.usageLimitBudget)"
            }
            if store.usageLimitDaily > 0 {
                dailyBudgetText = "\(store.usageLimitDaily)"
            }
        }
    }

    @ViewBuilder
    private func privacyRow(label: String, value: String, reveal: URL) -> some View {
        LabeledContent(label) {
            HStack(spacing: 6) {
                Text(value)
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([reveal])
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .buttonStyle(.borderless)
                .help("Reveal in Finder")
            }
        }
    }

    private func commitBudget() {
        let cleaned = budgetText
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: " ", with: "")
        if let n = Int(cleaned), n > 0 {
            store.usageLimitBudget = n
        } else if cleaned.isEmpty {
            store.usageLimitBudget = 0
        }
    }

    private func commitDailyBudget() {
        let cleaned = dailyBudgetText
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: " ", with: "")
        if let n = Int(cleaned), n > 0 {
            store.usageLimitDaily = n
        } else if cleaned.isEmpty {
            store.usageLimitDaily = 0
        }
    }
}

private struct IconChoice: View {
    let style: IconStyle
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 6) {
                ZStack {
                    if let image = style.image {
                        Image(nsImage: image)
                            .resizable()
                            .interpolation(.high)
                            .frame(width: 56, height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    } else {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.secondary.opacity(0.2))
                            .frame(width: 56, height: 56)
                    }
                }
                .padding(3)
                .overlay(
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2.5)
                )
                Text(style.displayName)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct MenuBarChoice: View {
    let style: MenuBarStyle
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(nsColor: .windowBackgroundColor))
                        .frame(width: 44, height: 30)
                    Image(systemName: style.symbolName)
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(.primary)
                }
                .padding(3)
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2.5)
                )
                Text(style.displayName)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)
            }
        }
        .buttonStyle(.plain)
    }
}
