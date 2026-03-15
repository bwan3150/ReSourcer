//
//  PreviewLogger.swift
//  ReSourcer
//
//  预览调试日志收集器，用于排查视频/音频/图片/PDF 加载问题
//

import Foundation

@MainActor
final class PreviewLogger: ObservableObject {

    enum Level: String {
        case info    = "INFO"
        case warning = "WARN"
        case error   = "ERR "
    }

    struct Entry: Identifiable {
        let id = UUID()
        let time: Date
        let level: Level
        let message: String

        var timeString: String {
            let f = DateFormatter()
            f.dateFormat = "HH:mm:ss.SSS"
            return f.string(from: time)
        }
    }

    @Published private(set) var entries: [Entry] = []

    func info(_ msg: String)    { append(.info,    msg) }
    func warning(_ msg: String) { append(.warning, msg) }
    func error(_ msg: String)   { append(.error,   msg) }

    func clear() { entries = [] }

    var fullText: String {
        entries.map { "[\($0.timeString)] [\($0.level.rawValue)] \($0.message)" }
               .joined(separator: "\n")
    }

    private func append(_ level: Level, _ message: String) {
        entries.append(Entry(time: Date(), level: level, message: message))
    }
}
