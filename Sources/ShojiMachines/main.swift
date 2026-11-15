import AppKit

// macOS's "reopen windows?" prompt after a crash isn't wanted.
UserDefaults.standard.set(true, forKey: "ApplePersistenceIgnoreState")

if let i = CommandLine.arguments.firstIndex(of: "--render-icon"), i + 1 < CommandLine.arguments.count {
    MainActor.assumeIsolated { AppIcon.render(to: CommandLine.arguments[i + 1]) }
    exit(0)
}

// A kitty console window for a VM: `--console <socket> [name]` (no app, just a byte pipe).
if let i = CommandLine.arguments.firstIndex(of: "--console"), i + 1 < CommandLine.arguments.count {
    let name = i + 2 < CommandLine.arguments.count ? CommandLine.arguments[i + 2] : "VM"
    ConsoleClient.run(socketPath: CommandLine.arguments[i + 1], name: name)
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = MachinesAppDelegate()
    app.delegate = delegate
    // A scripted test never appears in the Dock or on screen.
    app.setActivationPolicy(ProcessInfo.processInfo.environment["SHOJI_MACHINES_TEST"] == nil ? .regular : .prohibited)
    app.run()
}
