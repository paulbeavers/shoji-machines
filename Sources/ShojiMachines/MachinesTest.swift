import AppKit

/// Scripted end-to-end test of Shoji Machines, without a window:
/// `SHOJI_MACHINES_TEST=<log> SHOJI_VMS_DIR=<scratch> SHOJI_MACHINES_IMAGE=debian-13 "Shoji Machines"`.
/// Creates a VM, boots it, talks to it through a real console client (this program run as
/// `--console`, like a kitty window does), checks its IP and SSH, shuts it down and quits.
@MainActor
enum MachinesTest {
    static func run() -> Bool {
        let env = ProcessInfo.processInfo.environment
        guard let logPath = env["SHOJI_MACHINES_TEST"] else { return false }
        NSApp.setActivationPolicy(.prohibited) // no Dock icon, never on screen
        FileManager.default.createFile(atPath: logPath, contents: nil)
        func log(_ t: String) {
            if let h = FileHandle(forWritingAtPath: logPath) { h.seekToEndOfFile(); h.write(Data("\(t)\n".utf8)) }
        }
        let imageID = env["SHOJI_MACHINES_IMAGE"] ?? "debian-13"
        Task { @MainActor in
            do {
                let cfg = try await VMLibrary.create(name: "t-shoji", cpus: 2, memoryMB: 2048, diskGB: 10, imageID: imageID) { _, _ in }
                log("created \(cfg.id)")
                let vm = VMManager.shared.instance(cfg.id)!
                guard let server = ConsoleServer.server(for: vm) else { log("FAIL no console server"); NSApp.terminate(nil); return }
                log("socket \(server.path)")
                vm.start()
                for _ in 0..<240 where !String(decoding: vm.consoleHistory, as: UTF8.self).contains("$ ") {
                    try await Task.sleep(nanoseconds: 500_000_000)
                }
                log("prompt seen: \(String(decoding: vm.consoleHistory, as: UTF8.self).contains("$ "))")

                // A console client, exactly as kitty runs it, fed by a pipe.
                let client = Process()
                client.executableURL = URL(fileURLWithPath: Bundle.main.executablePath!)
                client.arguments = ["--console", server.path, cfg.name]
                let input = Pipe(), output = Pipe()
                client.standardInput = input
                client.standardOutput = output
                try client.run()
                try await Task.sleep(nanoseconds: 1_000_000_000)
                input.fileHandleForWriting.write(Data("echo SHOJI-CONSOLE-OK $(uname -s)\n".utf8))
                try await Task.sleep(nanoseconds: 3_000_000_000)
                input.fileHandleForWriting.closeFile()
                client.terminate()
                let seen = String(decoding: output.fileHandleForReading.availableData, as: UTF8.self)
                log("client got \(seen.count) bytes; round trip: \(seen.contains("SHOJI-CONSOLE-OK Linux"))")
                log("client tail: \(String(seen.suffix(400)).debugDescription)")

                var ip: String?
                for _ in 0..<40 { ip = vm.ipAddress; if ip != nil { break }; try await Task.sleep(nanoseconds: 500_000_000) }
                log("ip \(ip ?? "NONE")")
                if let ip {
                    let ssh = try? VMLibrary.run("/usr/bin/ssh", ["-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=no",
                                                                 "-o", "UserKnownHostsFile=/dev/null", "-o", "ConnectTimeout=5",
                                                                 "-o", "LogLevel=ERROR", "\(cfg.user)@\(ip)", "hostname; sudo -n whoami"])
                    log("ssh: \(ssh?.replacingOccurrences(of: "\n", with: " ") ?? "FAILED")")
                }
            } catch {
                log("ERROR \(error.localizedDescription)")
            }
            NSApp.terminate(nil) // applicationShouldTerminate shuts the VM down cleanly first
        }
        return true
    }
}
