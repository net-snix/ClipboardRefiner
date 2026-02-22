import Foundation
import os.log

final class AppLogger {
    static let shared = AppLogger()

    private let logger: Logger
    private let fileHandle: FileHandle?
    private let logFileURL: URL?
    private let fileQueue: DispatchQueue
    private let formatterQueue: DispatchQueue
    private let dateFormatter: DateFormatter

    private init() {
        logger = Logger(subsystem: "com.clipboardrefiner", category: "general")
        fileQueue = DispatchQueue(label: "com.clipboardrefiner.logger.file", qos: .utility)
        formatterQueue = DispatchQueue(label: "com.clipboardrefiner.logger.formatter")

        dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"

        let fileManager = FileManager.default
        if let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let logsDir = appSupport.appendingPathComponent("ClipboardRefiner/Logs", isDirectory: true)

            do {
                try fileManager.createDirectory(at: logsDir, withIntermediateDirectories: true)

                let logFileName = "clipboard_refiner_\(DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .none).replacingOccurrences(of: "/", with: "-")).log"
                let logURL = logsDir.appendingPathComponent(logFileName)

                if !fileManager.fileExists(atPath: logURL.path) {
                    fileManager.createFile(atPath: logURL.path, contents: nil)
                }

                fileHandle = try FileHandle(forWritingTo: logURL)
                fileHandle?.seekToEndOfFile()
                logFileURL = logURL

                fileQueue.async { [weak self] in
                    self?.cleanOldLogs(in: logsDir)
                }
            } catch {
                fileHandle = nil
                logFileURL = nil
                logger.error("Failed to create log file: \(error.localizedDescription)")
            }
        } else {
            fileHandle = nil
            logFileURL = nil
        }
    }

    deinit {
        fileQueue.sync {
            try? fileHandle?.close()
        }
    }

    private func cleanOldLogs(in directory: URL) {
        let fileManager = FileManager.default
        let maxAge: TimeInterval = 7 * 24 * 60 * 60

        do {
            let files = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.creationDateKey])

            for file in files {
                if let creationDate = try file.resourceValues(forKeys: [.creationDateKey]).creationDate,
                   Date().timeIntervalSince(creationDate) > maxAge {
                    try fileManager.removeItem(at: file)
                }
            }
        } catch {
            logger.warning("Failed to clean old logs: \(error.localizedDescription)")
        }
    }

    private func writeToFile(_ message: String) {
        guard let fileHandle = fileHandle,
              let data = (message + "\n").data(using: .utf8) else { return }

        fileQueue.async { [logger] in
            do {
                try fileHandle.write(contentsOf: data)
            } catch {
                logger.warning("Failed to write to log file: \(error.localizedDescription)")
            }
        }
    }

    private func formattedMessage(_ level: String, _ message: String, file: String, function: String, line: Int) -> String {
        let timestamp = formatterQueue.sync {
            dateFormatter.string(from: Date())
        }
        let fileName = (file as NSString).lastPathComponent
        return "[\(timestamp)] [\(level)] [\(fileName):\(line)] \(function) - \(message)"
    }

    func debug(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        let formatted = formattedMessage("DEBUG", message, file: file, function: function, line: line)
        logger.debug("\(formatted)")
        #if DEBUG
        writeToFile(formatted)
        #endif
    }

    func info(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        let formatted = formattedMessage("INFO", message, file: file, function: function, line: line)
        logger.info("\(formatted)")
        writeToFile(formatted)
    }

    func warning(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        let formatted = formattedMessage("WARNING", message, file: file, function: function, line: line)
        logger.warning("\(formatted)")
        writeToFile(formatted)
    }

    func error(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        let formatted = formattedMessage("ERROR", message, file: file, function: function, line: line)
        logger.error("\(formatted)")
        writeToFile(formatted)
    }

    func error(_ error: Error, file: String = #file, function: String = #function, line: Int = #line) {
        self.error(error.localizedDescription, file: file, function: function, line: line)
    }
}
