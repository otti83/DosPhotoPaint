import Foundation

/// Debug-only launch instrumentation: uptime stamps taken at the first statement of `main.swift`
/// and at the end of `applicationDidFinishLaunching`. Read by PerformanceTests. Compiled out of
/// Release builds, so shipping code carries no cost.
enum LaunchTiming {
    #if DEBUG
    nonisolated(unsafe) static var mainStartNanos: UInt64 = 0
    nonisolated(unsafe) static var didFinishLaunchingNanos: UInt64 = 0

    /// Seconds from the start of `main` to the end of `applicationDidFinishLaunching`.
    static var mainToDidFinishLaunching: Double? {
        guard mainStartNanos > 0, didFinishLaunchingNanos >= mainStartNanos else { return nil }
        return Double(didFinishLaunchingNanos - mainStartNanos) / 1e9
    }
    #endif

    @inline(__always) static func markMain() {
        #if DEBUG
        mainStartNanos = DispatchTime.now().uptimeNanoseconds
        #endif
    }

    @inline(__always) static func markDidFinishLaunching() {
        #if DEBUG
        didFinishLaunchingNanos = DispatchTime.now().uptimeNanoseconds
        #endif
    }
}
