import FlexBankCore
import Foundation

@main
struct FlexBankSeedDemoCLI {
    static func main() throws {
        let outputURL = try resolveOutputURL(arguments: Array(CommandLine.arguments.dropFirst()))
        let fileManager = FileManager.default

        try fileManager.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        if fileManager.fileExists(atPath: outputURL.path) {
            let backupURL = makeBackupURL(for: outputURL)
            try fileManager.copyItem(at: outputURL, to: backupURL)
            print("Backed up existing state to: \(backupURL.path)")
        }

        let state = FlexDemoSeed.makeState()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let data = try encoder.encode(state)
        try data.write(to: outputURL, options: [.atomic])

        print("Wrote demo FlexBank state to: \(outputURL.path)")
        print("Events: \(state.events.count)")
        print("Quick add default: \(state.settings.quickAddMinutes)m")
    }

    private static func resolveOutputURL(arguments: [String]) throws -> URL {
        if arguments.isEmpty {
            return defaultStateFileURL()
        }

        if arguments.count == 2, arguments[0] == "--output" {
            return URL(fileURLWithPath: NSString(string: arguments[1]).expandingTildeInPath)
        }

        if arguments.count == 1 {
            return URL(fileURLWithPath: NSString(string: arguments[0]).expandingTildeInPath)
        }

        throw CLIError.invalidArguments
    }

    private static func defaultStateFileURL() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FlexBank", isDirectory: true)
            .appendingPathComponent("state.json")
    }

    private static func makeBackupURL(for outputURL: URL) -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyyMMdd-HHmmss"

        let timestamp = formatter.string(from: Date())
        let fileName = outputURL.deletingPathExtension().lastPathComponent
        let backupName = "\(fileName).backup-\(timestamp).json"
        return outputURL.deletingLastPathComponent().appendingPathComponent(backupName)
    }
}

private enum CLIError: LocalizedError {
    case invalidArguments

    var errorDescription: String? {
        switch self {
        case .invalidArguments:
            return "Usage: swift run FlexBankSeedDemo [--output /path/to/state.json]"
        }
    }
}
