import Foundation

/// Percorsi del servizio di opencode-lens (`opencode-lens service install`, src/service.js),
/// gli stessi dalla 0.1.0.
public enum Paths {
    public static let label = "local.opencode-lens"

    /// La home dell'utente: nella sandbox del widget homeDirectoryForCurrentUser è il suo container,
    /// e il plist del LaunchAgent va cercato nella home vera.
    public static var home: URL {
        guard let entry = getpwuid(getuid()), let dir = entry.pointee.pw_dir else {
            return FileManager.default.homeDirectoryForCurrentUser
        }
        return URL(fileURLWithPath: String(cString: dir), isDirectory: true)
    }
    public static var plist: URL { home.appending(path: "Library/LaunchAgents/\(label).plist") }
    public static var log: URL { home.appending(path: "Library/Logs/opencode-lens/lens.log") }
    public static var logsFolder: URL { home.appending(path: "Library/Logs") }

    /// Il log della lens se esiste, altrimenti ~/Library/Logs.
    public static func logToOpen(fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) -> URL {
        fileExists(log.path) ? log : logsFolder
    }
}
