import SwiftUI

// MARK: - SettingsView
//
// A clean, tabbed settings window. Every control binds directly to the
// `SettingsStore` via the type-safe `binding(_:)` helper, so edits are
// auto-persisted to the JSON config (debounced) and propagated to live tabs.
//
// Tabs: General · Performance · Appearance · Privacy · Advanced

struct SettingsView: View {
    @ObservedObject var store: SettingsStore

    var body: some View {
        TabView {
            GeneralTab(store: store)
                .tabItem { Label("General", systemImage: "gear") }
            PerformanceTab(store: store)
                .tabItem { Label("Performance", systemImage: "gauge.medium") }
            AppearanceTab(store: store)
                .tabItem { Label("Appearance", systemImage: "paintbrush") }
            PrivacyTab(store: store)
                .tabItem { Label("Privacy", systemImage: "hand.raised") }
            AdvancedTab(store: store)
                .tabItem { Label("Advanced", systemImage: "wrench.and.screwdriver") }
        }
        .frame(width: 520, height: 460)
        .padding(.top, 6)
    }
}

// MARK: - General

private struct GeneralTab: View {
    @ObservedObject var store: SettingsStore

    var body: some View {
        Form {
            Section("Startup") {
                LabeledRow("Homepage") {
                    TextField("https://example.com", text: store.binding(\.homepageURL))
                        .textFieldStyle(.roundedBorder)
                }
                LabeledRow("New tab page") {
                    TextField("blank = local page", text: store.binding(\.newTabPageURL))
                        .textFieldStyle(.roundedBorder)
                }
                LabeledRow("Search engine") {
                    TextField("https://duckduckgo.com/?q=%@", text: store.binding(\.searchEngineURL))
                        .textFieldStyle(.roundedBorder)
                }
                Toggle("Restore last session on launch", isOn: store.binding(\.restoreLastSession))
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Performance

private struct PerformanceTab: View {
    @ObservedObject var store: SettingsStore

    var body: some View {
        Form {
            Section("Tab unloading") {
                LabeledRow("Unload inactive tabs after") {
                    HStack {
                        Stepper(value: store.binding(\.tabUnloadMinutes), in: 0...120, step: 5) {
                            Text("\(store.settings.tabUnloadMinutes) min")
                                .monospacedDigit()
                        }
                        Text("0 = never")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                LabeledRow("Max loaded tabs") {
                    HStack {
                        Stepper(value: store.binding(\.maxLoadedTabs), in: 0...50) {
                            Text("\(store.settings.maxLoadedTabs)")
                                .monospacedDigit()
                        }
                        Text("0 = unlimited")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                LabeledRow("Unload check every") {
                    Stepper(value: store.binding(\.unloadCheckIntervalSeconds), in: 15...600, step: 15) {
                        Text("\(store.settings.unloadCheckIntervalSeconds) s")
                            .monospacedDigit()
                    }
                }
            }

            Section("Idle tab scheduling") {
                Picker("Inactive policy", selection: store.binding(\.inactivePolicy)) {
                    ForEach(InactivePolicy.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.menu)
                Text("Suspend = lowest CPU/RAM. Throttle = balanced. None = instant wake.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Appearance

private struct AppearanceTab: View {
    @ObservedObject var store: SettingsStore

    var body: some View {
        Form {
            Section("Sidebar tabs") {
                Picker("Position", selection: store.binding(\.tabPosition)) {
                    ForEach(TabPosition.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                Toggle("Show sidebar", isOn: store.binding(\.sidebarVisible))
                Toggle("Collapsed (icon-only rail)", isOn: store.binding(\.sidebarCollapsed))
                LabeledRow("Expanded width") {
                    HStack {
                        Slider(value: Binding(
                            get: { Double(store.settings.sidebarWidth) },
                            set: { newValue in store.update { $0.sidebarWidth = Int(newValue) } }
                        ), in: 160...420, step: 5)
                        Text("\(store.settings.sidebarWidth)pt").monospacedDigit()
                    }
                }
            }

            Section("Window") {
                Toggle("Compact mode (floating sidebar on hover)", isOn: store.binding(\.compactMode))
                Toggle("Show Home button", isOn: store.binding(\.showHomeButton))
                Toggle("Show Reload button", isOn: store.binding(\.showReloadButton))
                Toggle("Show status bar", isOn: store.binding(\.showStatusBar))
            }

            Section("Theme & content") {
                Picker("Appearance", selection: store.binding(\.theme)) {
                    ForEach(AppTheme.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                LabeledRow("Page zoom") {
                    HStack {
                        Slider(value: store.binding(\.pageZoom), in: 0.5...2.0, step: 0.05)
                        Text("\(Int(store.settings.pageZoom * 100))%").monospacedDigit()
                    }
                }
                LabeledRow("Min font size") {
                    Stepper(value: store.binding(\.minimumFontSize), in: 0...48) {
                        Text("\(store.settings.minimumFontSize) pt")
                            .monospacedDigit()
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Privacy

private struct PrivacyTab: View {
    @ObservedObject var store: SettingsStore

    var body: some View {
        Form {
            Section("Tracking") {
                Toggle("Block trackers & ads", isOn: store.binding(\.blockTrackers))
                Toggle("Upgrade known hosts to HTTPS", isOn: store.binding(\.upgradeKnownHostsToHTTPS))
                Toggle("Fraudulent site warnings", isOn: store.binding(\.fraudulentSiteWarnings))
            }
            Section("Browsing") {
                Toggle("Private browsing (no history/cookies)", isOn: store.binding(\.privateBrowsing))
                Toggle("Allow pop-up windows", isOn: store.binding(\.allowsPopups))
            }
            Section("Media") {
                Toggle("Require user action for autoplay", isOn: store.binding(\.mediaAutoplayRequiresUserAction))
                Toggle("Block AirPlay (skip media routing)", isOn: store.binding(\.blockAirPlay))
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Advanced

private struct AdvancedTab: View {
    @ObservedObject var store: SettingsStore

    var body: some View {
        Form {
            Section("Content") {
                Toggle("Enable JavaScript", isOn: store.binding(\.enableJavaScript))
                Toggle("JS can open windows", isOn: store.binding(\.javaScriptCanOpenWindows))
                Toggle("Element fullscreen", isOn: store.binding(\.elementFullscreenEnabled))
                Picker("Default content mode", selection: store.binding(\.defaultContentMode)) {
                    ForEach(ContentModeSetting.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            Section("User agent") {
                TextField("Custom UA (blank = default)", text: store.binding(\.customUserAgent),
                          axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...3)
            }

            Section("Custom CSS injection") {
                Toggle("Inject custom CSS", isOn: store.binding(\.injectCustomCSS))
                if store.settings.injectCustomCSS {
                    TextEditor(text: store.binding(\.customCSS))
                        .font(.system(size: 11, design: .monospaced))
                        .frame(height: 80)
                        .border(.tertiary)
                }
            }

            Section("Custom JS injection") {
                Toggle("Inject custom JavaScript", isOn: store.binding(\.injectCustomJS))
                if store.settings.injectCustomJS {
                    TextEditor(text: store.binding(\.customJS))
                        .font(.system(size: 11, design: .monospaced))
                        .frame(height: 80)
                        .border(.tertiary)
                }
            }

            Section("Config file") {
                HStack {
                    Button("Reveal config.json") { store.revealConfig() }
                    Button("Reset to defaults", role: .destructive) { store.resetToDefaults() }
                    Spacer()
                }
                Text("~/.config/minimal-webkit-browser/config.json")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - LabeledRow helper

private struct LabeledRow<Content: View>: View {
    let label: String
    let content: Content
    init(_ label: String, @ViewBuilder content: () -> Content) {
        self.label = label; self.content = content()
    }
    var body: some View {
        HStack {
            Text(label).foregroundStyle(.primary)
            Spacer(minLength: 12)
            content
        }
    }
}
