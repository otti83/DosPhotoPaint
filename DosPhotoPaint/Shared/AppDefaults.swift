import Foundation

/// Process-wide runtime facts and the preferences store.
nonisolated enum AppRuntime {
    /// True when this process is the host of an XCTest bundle.
    static let isUnitTestHost: Bool = {
        let env = ProcessInfo.processInfo.environment
        return env["XCTestConfigurationFilePath"] != nil || env["XCTestSessionIdentifier"] != nil
    }()

    /// Suite used instead of the user's preferences while unit tests run, so tests never change
    /// the real app settings (they share the app's sandbox container). Cleared at each test launch.
    static let unitTestSuiteName = "com.dosphotopaint.DosPhotoPaint.unittests"

    /// The preferences store for all app settings (UserDefaults is thread-safe).
    // UserDefaults is documented as thread-safe but not marked Sendable.
    nonisolated(unsafe) static let defaults: UserDefaults = {
        guard isUnitTestHost, let suite = UserDefaults(suiteName: unitTestSuiteName) else { return .standard }
        suite.removePersistentDomain(forName: unitTestSuiteName)
        return suite
    }()
}
