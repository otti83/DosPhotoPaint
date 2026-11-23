import AppKit

LaunchTiming.markMain()

// The language preference must be applied before any localized string is loaded.
AppLanguage.applyAtLaunch()

let delegate = AppDelegate()
NSApplication.shared.delegate = delegate
if AppDelegate.isRunningUnitTests {
    // Unit-test host: no Dock icon, no menu bar, no windows. Keeps test runs from stealing focus
    // and from presenting "quit unexpectedly" dialogs when a test crashes the host.
    NSApplication.shared.setActivationPolicy(.prohibited)
}
_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
