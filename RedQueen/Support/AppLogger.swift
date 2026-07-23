import Foundation
import CocoaLumberjackSwift

/// Debug logging to a file in Documents so a repro can be pulled off-device
/// after the fact — on macOS (unsandboxed) that's the real `~/Documents`; on
/// iOS it's the app's own Documents, exposed via Files (`UIFileSharingEnabled`)
/// and pullable with `devicectl device copy from --domain-type appDataContainer`.
enum AppLogger {
    private static let fileLogger: DDFileLogger = {
        let manager = DDLogFileManagerDefault(logsDirectory: logsDirectory.path(percentEncoded: false))
        let logger = DDFileLogger(logFileManager: manager)
        logger.rollingFrequency = 60 * 60 * 24
        logger.logFileManager.maximumNumberOfLogFiles = 7
        logger.maximumFileSize = 5 * 1024 * 1024
        return logger
    }()

    private static var logsDirectory: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let logs = documents.appendingPathComponent("Logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        return logs
    }

    private static var isEnabled = false

    /// Reflects the "Debug Logging" setting. Called once at launch (reading
    /// the persisted value) and again whenever the user flips the toggle.
    static func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        if enabled {
            dynamicLogLevel = .debug
            DDLog.add(DDOSLogger.sharedInstance)
            DDLog.add(fileLogger)
            logLaunch()
        } else {
            DDLogInfo("🚀 [AppLogger] logging disabled")
            DDLog.remove(DDOSLogger.sharedInstance)
            DDLog.remove(fileLogger)
        }
    }

    static func start() {
        let enabled = (UserDefaults.standard.object(forKey: "debugLoggingEnabled") as? Bool) ?? true
        setEnabled(enabled)
    }

    private static func logLaunch() {
        let defaults = UserDefaults.standard
        let agentUserIDOverride = defaults.string(forKey: "agentUserID") ?? ""
        let elementCallURL = defaults.string(forKey: "elementCallURL") ?? AppConfig.defaultElementCallURL
        let pushGatewayURL = defaults.string(forKey: "pushGatewayURL") ?? AppConfig.defaultPushGatewayURL
        let showIDs = defaults.bool(forKey: "showIDs")

        let bundle = Bundle.main
        let version = bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = bundle.infoDictionary?["CFBundleVersion"] as? String ?? "?"

        #if os(iOS)
        let platform = "iOS"
        #elseif os(macOS)
        let platform = "macOS"
        #endif

        DDLogInfo("""
        🚀 [AppLogger] launch
          app: \(version) (\(build)) bundleID=\(bundle.bundleIdentifier ?? "?")
          platform: \(platform) \(ProcessInfo.processInfo.operatingSystemVersionString)
          sdk: \(AppConfig.sdkVersion.prefix(9))
          homeserver: \(AppConfig.homeserverURL)
          agentUserID override: \(agentUserIDOverride.isEmpty ? "(default)" : agentUserIDOverride)
          elementCallURL: \(elementCallURL)
          pushGatewayURL: \(pushGatewayURL)
          showIDs: \(showIDs)
          encryptNewConversations: \(AppConfig.encryptNewConversations)
          logs dir: \(logsDirectory.path(percentEncoded: false))
        """)
    }
}
