import Foundation
import os

/// Unified logger using os.Logger — visible in Console.app under com.livekeet.core.
public enum Log {
    private static let consoleState = OSAllocatedUnfairLock(initialState: false)
    public static var consoleEnabled: Bool {
        get { consoleState.withLock { $0 } }
        set { consoleState.withLock { $0 = newValue } }
    }

    private static func console(_ message: String) {
        if consoleEnabled { FileHandle.standardError.write(Data((message + "\n").utf8)) }
    }

    private static let logger = Logger(subsystem: "com.livekeet.core", category: "pipeline")

    public static func debug(_ message: String) {
        logger.debug("\(message, privacy: .public)")
    }

    public static func info(_ message: String) {
        logger.info("\(message, privacy: .public)")
        console("\(message)")
    }

    public static func warning(_ message: String) {
        logger.warning("\(message, privacy: .public)")
        console("Warning: \(message)")
    }

    public static func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
        console("Error: \(message)")
    }
}
