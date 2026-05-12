import SwiftUI

private func kindColor(_ kind: CorrectionLog.Kind) -> Color {
    switch kind {
    case .autoApply, .applyFromBackspace: return .green
    case .prediction, .contextRerank: return .blue
    case .punctuation, .spaceBeforePunct, .missingSpaceAfterPunct, .doubleSpace: return .orange
    case .activeApostrophe, .capitalI, .sentenceCap: return .purple
    case .deleteWholeWord, .rapidWordDelete, .clearField: return .red
    case .pending: return .gray
    }
}

private let kindLabel: [CorrectionLog.Kind: String] = [
    .autoApply: "auto", .applyFromBackspace: "bs-fix", .pending: "pending",
    .deleteWholeWord: "del-word", .rapidWordDelete: "rapid-del",
    .punctuation: "punct", .spaceBeforePunct: "sp-punct",
    .missingSpaceAfterPunct: "miss-sp", .activeApostrophe: "apostrophe",
    .doubleSpace: "dbl-sp", .capitalI: "cap-I", .prediction: "predict",
    .sentenceCap: "sent-cap", .contextRerank: "ai-rank", .clearField: "clear",
]

struct DashboardView: View {
    @ObservedObject var tailer: LogTailer

    var body: some View {
        VStack(spacing: 0) {
            statusBar
            Divider()
            feedList
            Divider()
            statsGrid
        }
        .frame(minWidth: 500, minHeight: 540)
    }

    // MARK: Status bar
    private var statusBar: some View {
        HStack(spacing: 16) {
            indicator(
                label: tailer.engineEnabled ? "Active" : "Paused",
                color: tailer.engineEnabled ? .green : .orange
            )
            indicator(
                label: PermissionsHelper.accessibilityGranted() ? "Accessibility ✓" : "No Accessibility",
                color: PermissionsHelper.accessibilityGranted() ? .green : .red
            )
            indicator(label: "Lang: \(TyproSettings.shared.language)", color: .secondary)
            Spacer()
            Text("All-time: \(tailer.allTimeCount)")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(.bar)
    }

    private func indicator(label: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label).font(.caption).foregroundStyle(.primary)
        }
    }

    // MARK: Live feed
    private var feedList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(tailer.entries) { entry in
                    feedRow(entry)
                    Divider().padding(.leading, 16)
                }
            }
        }
    }

    private func feedRow(_ e: CorrectionEntry) -> some View {
        HStack(spacing: 10) {
            Text(timeString(e.timestamp))
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .leading)

            Text(kindLabel[e.kind] ?? e.kind.rawValue)
                .font(.system(size: 10, weight: .medium))
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(kindColor(e.kind).opacity(0.15))
                .foregroundStyle(kindColor(e.kind))
                .clipShape(Capsule())
                .frame(width: 72, alignment: .leading)

            if e.typed.isEmpty && e.correction.isEmpty {
                Text("—").foregroundStyle(.secondary).font(.callout)
            } else {
                Text(e.typed.isEmpty ? "—" : e.typed)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(.secondary)
                Image(systemName: "arrow.right")
                    .font(.caption2).foregroundStyle(.tertiary)
                Text(e.correction.isEmpty ? "—" : e.correction)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(.primary)
            }

            Spacer()

            if let app = e.app?.components(separatedBy: ".").last {
                Text(app).font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 7)
    }

    // MARK: Stats grid
    private var statsGrid: some View {
        let today = tailer.todayCountByKind
        let active = CorrectionLog.Kind.allCases.filter { (today[$0] ?? 0) > 0 }
        return VStack(alignment: .leading, spacing: 8) {
            Text("Today").font(.caption).foregroundStyle(.secondary).padding(.horizontal, 16)
            if active.isEmpty {
                Text("No corrections yet today.")
                    .font(.caption).foregroundStyle(.tertiary)
                    .padding(.horizontal, 16)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140))], spacing: 6) {
                    ForEach(active, id: \.self) { kind in
                        HStack {
                            Circle().fill(kindColor(kind)).frame(width: 6, height: 6)
                            Text(kindLabel[kind] ?? kind.rawValue).font(.caption)
                            Spacer()
                            Text("\(today[kind]!)").font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(.quaternary).clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        .padding(.vertical, 12)
        .background(.bar)
    }

    private func timeString(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: date)
    }
}
