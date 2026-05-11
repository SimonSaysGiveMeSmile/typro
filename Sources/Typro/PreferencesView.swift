import SwiftUI
import AppKit

struct PreferencesView: View {
    @State private var enabled: Bool = TyproSettings.shared.enabled
    @State private var minLen: Double = Double(TyproSettings.shared.minWordLength)
    @State private var mode: TyproSettings.AllowlistMode = TyproSettings.shared.allowlistMode
    @State private var bundleIDs: [String] = TyproSettings.shared.bundleIDs
    @State private var language: String = TyproSettings.shared.language
    @State private var newBundleID: String = ""

    private let languages: [(label: String, code: String)] = [
        ("English", "en"), ("Spanish", "es"), ("French", "fr"),
        ("German", "de"), ("Italian", "it"), ("Portuguese", "pt"),
        ("Dutch", "nl"), ("Swedish", "sv")
    ]

    var body: some View {
        Form {
            Section {
                Toggle("Enable Typro", isOn: $enabled)
                    .onChange(of: enabled) { TyproSettings.shared.enabled = enabled }
            }
            Section("Detection") {
                VStack(alignment: .leading) {
                    Text("Minimum word length: \(Int(minLen))")
                    Slider(value: $minLen, in: 2...10, step: 1)
                        .onChange(of: minLen) { TyproSettings.shared.minWordLength = Int(minLen) }
                }
                Picker("Language", selection: $language) {
                    ForEach(languages, id: \.code) { lang in
                        Text(lang.label).tag(lang.code)
                    }
                }
                .onChange(of: language) { TyproSettings.shared.language = language }
            }
            Section("App Filter") {
                Picker("Mode", selection: $mode) {
                    Text("Everywhere").tag(TyproSettings.AllowlistMode.everywhere)
                    Text("Only in listed apps").tag(TyproSettings.AllowlistMode.onlyListed)
                    Text("Everywhere except listed").tag(TyproSettings.AllowlistMode.exceptListed)
                }
                .onChange(of: mode) { TyproSettings.shared.allowlistMode = mode }

                if mode != .everywhere {
                    HStack {
                        TextField("com.apple.Safari", text: $newBundleID)
                        Button("Add") { addBundleID() }
                            .disabled(newBundleID.trimmingCharacters(in: .whitespaces).isEmpty)
                        Button("Add Frontmost") { addFrontmost() }
                    }
                    if bundleIDs.isEmpty {
                        Text("No apps added yet.").foregroundStyle(.secondary)
                    } else {
                        List {
                            ForEach(bundleIDs, id: \.self) { id in
                                HStack {
                                    Text(id).font(.system(.body, design: .monospaced))
                                    Spacer()
                                    Button(role: .destructive) { remove(id) } label: {
                                        Image(systemName: "minus.circle")
                                    }.buttonStyle(.plain)
                                }
                            }
                        }
                        .frame(minHeight: 100, maxHeight: 150)
                    }
                }
            }
            Section {
                Text("Typro needs Accessibility permission (System Settings → Privacy & Security → Accessibility).")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(minWidth: 440)
    }

    private func addBundleID() {
        let id = newBundleID.trimmingCharacters(in: .whitespaces)
        guard !id.isEmpty, !bundleIDs.contains(id) else { return }
        bundleIDs.append(id)
        TyproSettings.shared.bundleIDs = bundleIDs
        newBundleID = ""
    }

    private func addFrontmost() {
        if let id = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
           !bundleIDs.contains(id) {
            bundleIDs.append(id)
            TyproSettings.shared.bundleIDs = bundleIDs
        }
    }

    private func remove(_ id: String) {
        bundleIDs.removeAll { $0 == id }
        TyproSettings.shared.bundleIDs = bundleIDs
    }
}
