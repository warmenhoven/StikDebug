//
//  LogManager.swift
//  StikJIT
//
//  Created by neoarz on 3/29/25.
//

import Foundation

final class LogManager: ObservableObject {
    static let shared = LogManager()

    @Published var logs: [LogEntry] = []
    @Published var errorCount: Int = 0

    struct LogEntry: Identifiable {
        let id = UUID()
        let timestamp: Date
        let type: LogType
        let message: String

        enum LogType: String {
            case info    = "INFO"
            case error   = "ERROR"
            case debug   = "DEBUG"
            case warning = "WARNING"
        }
    }

    private static let redundantPrefixes: [String] = [
        "Info: ", "INFO: ", "Information: ",
        "Error: ", "ERROR: ", "ERR: ",
        "Debug: ", "DEBUG: ", "DBG: ",
        "Warning: ", "WARN: ", "WARNING: "
    ]

    private init() {
        addInfoLog("StikJIT starting up")
        addInfoLog("Initializing environment")
    }

    func addLog(message: String, type: LogEntry.LogType) {
        let clean = Self.redundantPrefixes
            .first(where: { message.hasPrefix($0) })
            .map { String(message.dropFirst($0.count)) } ?? message

        DispatchQueue.main.async {
            self.logs.append(LogEntry(timestamp: Date(), type: type, message: clean))
            if type == .error { self.errorCount += 1 }
            if self.logs.count > 1000 { self.logs.removeFirst(100) }
        }
    }

    func addInfoLog(_ message: String)    { addLog(message: message, type: .info) }
    func addErrorLog(_ message: String)   { addLog(message: message, type: .error) }
    func addDebugLog(_ message: String)   { addLog(message: message, type: .debug) }
    func addWarningLog(_ message: String) { addLog(message: message, type: .warning) }

    func clearLogs() {
        DispatchQueue.main.async {
            self.logs.removeAll()
            self.errorCount = 0
        }
    }

    func removeOldestLogs(count: Int) {
        DispatchQueue.main.async {
            let removed = self.logs.prefix(count)
            self.logs.removeFirst(count)
            let removedErrors = removed.filter { $0.type == .error }.count
            self.errorCount = max(0, self.errorCount - removedErrors)
        }
    }
}
