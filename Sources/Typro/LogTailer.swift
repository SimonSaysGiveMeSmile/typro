import Foundation
import AppKit

struct CorrectionEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let kind: CorrectionLog.Kind
    let typed: String
    let correction: String
    let app: String?
}

final class LogTailer: ObservableObject {
    @Published var entries: [CorrectionEntry] = []
    @Published var allTimeCount: Int = 0
    @Published var engineEnabled: Bool = TyproSettings.shared.enabled

    private let logURL = CorrectionLog.shared.fileURLForDisplay
    private var fileHandle: FileHandle?
    private var source: DispatchSourceFileSystemObject?
    private let iso = ISO8601DateFormatter()

    init() {
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        TyproSettings.shared.onChange = { [weak self] in
            DispatchQueue.main.async { self?.engineEnabled = TyproSettings.shared.enabled }
        }
    }

    func start() {
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        guard let fh = try? FileHandle(forReadingFrom: logURL) else { return }

        // Seed with last 16 KB of history.
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: logURL.path)[.size] as? Int) ?? 0
        let tailSize = min(fileSize, 16_384)
        if tailSize > 0 {
            try? fh.seek(toOffset: UInt64(fileSize - tailSize))
            parse(fh.availableData, prepend: false)
        }
        try? fh.seekToEnd()
        fileHandle = fh

        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fh.fileDescriptor,
            eventMask: .write,
            queue: .main
        )
        src.setEventHandler { [weak self] in
            guard let self, let fh = self.fileHandle else { return }
            self.parse(fh.availableData, prepend: true)
        }
        src.setCancelHandler { try? fh.close() }
        src.resume()
        source = src
    }

    func stop() {
        source?.cancel()
        source = nil
        fileHandle = nil
    }

    var todayCountByKind: [CorrectionLog.Kind: Int] {
        let cal = Calendar.current
        return entries
            .filter { cal.isDateInToday($0.timestamp) }
            .reduce(into: [:]) { $0[$1.kind, default: 0] += 1 }
    }

    private func parse(_ data: Data, prepend: Bool) {
        guard !data.isEmpty,
              let text = String(data: data, encoding: .utf8) else { return }
        let lines = text.components(separatedBy: "\n").filter { !$0.isEmpty }
        var parsed: [CorrectionEntry] = []
        for line in lines {
            guard let d = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                  let tStr = obj["t"] as? String,
                  let ts = iso.date(from: tStr),
                  let kindRaw = obj["kind"] as? String,
                  let kind = CorrectionLog.Kind(rawValue: kindRaw) else { continue }
            parsed.append(CorrectionEntry(
                timestamp: ts,
                kind: kind,
                typed: obj["typed"] as? String ?? "",
                correction: obj["correction"] as? String ?? "",
                app: obj["app"] as? String
            ))
        }
        guard !parsed.isEmpty else { return }
        allTimeCount += parsed.count
        if prepend {
            entries = Array((parsed.reversed() + entries).prefix(50))
        } else {
            entries = Array(parsed.suffix(50))
        }
    }

    deinit { stop() }
}
