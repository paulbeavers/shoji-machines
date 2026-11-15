import AppKit

/// A VM's serial console (hvc0), served on a Unix socket so kitty windows can attach to it: each
/// kitty window runs this same program as `--console <socket>` (see `ConsoleClient`). The VM
/// keeps running when a console window closes; several windows may attach at once.
@MainActor
final class ConsoleServer {
    private static var servers: [String: ConsoleServer] = [:]

    /// Sockets live in a short private folder (Unix socket paths are limited to ~104 bytes).
    nonisolated static func socketPath(for id: String) -> String {
        let dir = "/tmp/shoji-\(getuid())"
        mkdir(dir, 0o700)
        return "\(dir)/\(id).sock"
    }

    static func server(for vm: VMInstance) -> ConsoleServer? {
        if let s = servers[vm.id] { return s }
        let s = ConsoleServer(vm: vm)
        guard s.listenFD >= 0 else { return nil }
        servers[vm.id] = s
        return s
    }

    /// Open the console in a new kitty window, starting the VM if it's off.
    static func openConsole(for vm: VMInstance) {
        guard let server = server(for: vm), let exe = Bundle.main.executablePath else { NSSound.beep(); return }
        if !vm.state.isActive { vm.start() }
        Kitty.open(title: "\(vm.config.name) — console", [exe, "--console", server.path, vm.config.name])
    }

    let vm: VMInstance
    let path: String
    private var listenFD: Int32 = -1
    private var acceptSource: DispatchSourceRead?
    private var clients: [Int32: DispatchSourceRead] = [:]
    private var listener: UUID?
    private var lastState: VMInstance.State

    private init(vm: VMInstance) {
        self.vm = vm
        path = Self.socketPath(for: vm.id)
        lastState = vm.state
        unlink(path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8CString)
        guard bytes.count <= MemoryLayout.size(ofValue: addr.sun_path) else { close(fd); return }
        withUnsafeMutableBytes(of: &addr.sun_path) { dst in bytes.withUnsafeBytes { dst.copyMemory(from: $0) } }
        let ok = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard ok == 0, listen(fd, 8) == 0 else { close(fd); return }
        chmod(path, 0o600)
        listenFD = fd
        let src = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .main)
        src.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.acceptClient() } }
        src.resume()
        acceptSource = src
        listener = vm.addConsoleListener { [weak self] data in self?.broadcast(data) }
        NotificationCenter.default.addObserver(forName: .vmsDidChange, object: vm.id, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.stateChanged() }
        }
    }

    private func acceptClient() {
        let fd = accept(listenFD, nil, nil)
        guard fd >= 0 else { return }
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        let src = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .main)
        src.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.readClient(fd) } }
        src.setCancelHandler { close(fd) }
        clients[fd] = src
        src.resume()
        // Catch up: what the console showed so far, then the VM's state.
        if !vm.consoleHistory.isEmpty { write(vm.consoleHistory, to: fd) }
        switch vm.state {
        case .stopped, .failed: write(status("\(vm.config.name) is off. Press Enter to start it."), to: fd)
        case .starting: write(status("Starting \(vm.config.name)…"), to: fd)
        default: break
        }
    }

    private func readClient(_ fd: Int32) {
        var buf = [UInt8](repeating: 0, count: 4096)
        let n = read(fd, &buf, buf.count)
        guard n > 0 else { clients.removeValue(forKey: fd)?.cancel(); return }
        let data = Data(buf[0..<n])
        if vm.state.isActive {
            vm.sendToConsole(data)
        } else if data.contains(13) {
            vm.start() // Enter starts a stopped VM
        }
    }

    private func broadcast(_ data: Data) {
        for fd in clients.keys where !write(data, to: fd) { clients.removeValue(forKey: fd)?.cancel() }
    }

    @discardableResult
    private func write(_ data: Data, to fd: Int32) -> Bool {
        data.withUnsafeBytes { p in
            var off = 0
            while off < p.count {
                let n = Darwin.write(fd, p.baseAddress! + off, p.count - off)
                if n <= 0 { return false }
                off += n
            }
            return true
        }
    }

    private func status(_ text: String) -> Data { Data("\r\n\u{1B}[2m[shoji] \(text)\u{1B}[0m\r\n".utf8) }

    private func stateChanged() {
        let s = vm.state
        defer { lastState = s }
        guard s != lastState else { return }
        let message: String?
        switch s {
        case .stopped: message = "\(vm.config.name) is off. Press Enter to start it."
        case .failed(let m): message = "\(vm.config.name) stopped: \(m)"
        case .stopping: message = "Shutting down…"
        case .starting: message = "Starting \(vm.config.name)…"
        case .running: message = nil
        }
        if let message { broadcast(status(message)) }
    }
}

/// `Shoji Machines --console <socket> [name]`: the program kitty runs for a console window. Puts
/// the terminal in raw mode and copies bytes both ways until either side closes.
enum ConsoleClient {
    static func run(socketPath: String, name: String) -> Never {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(socketPath.utf8CString)
        withUnsafeMutableBytes(of: &addr.sun_path) { dst in bytes.prefix(dst.count).withUnsafeBytes { dst.copyMemory(from: $0) } }
        let ok = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard fd >= 0, ok == 0 else {
            FileHandle.standardError.write(Data("Shoji Machines isn't serving this console any more.\n".utf8))
            sleep(3)
            exit(1)
        }
        // Raw terminal: every key goes to the VM (Ctrl-C included); restored on exit.
        var original = termios()
        let isTTY = isatty(STDIN_FILENO) == 1
        if isTTY {
            tcgetattr(STDIN_FILENO, &original)
            var raw = original
            cfmakeraw(&raw)
            tcsetattr(STDIN_FILENO, TCSANOW, &raw)
        }
        let header = "\u{1B}[2m[shoji] \(name) console — close this window to detach (the VM keeps running)\u{1B}[0m\r\n"
        FileHandle.standardOutput.write(Data(header.utf8))
        var fds = [pollfd(fd: STDIN_FILENO, events: Int16(POLLIN), revents: 0), pollfd(fd: fd, events: Int16(POLLIN), revents: 0)]
        var buf = [UInt8](repeating: 0, count: 8192)
        var stdinOpen = true
        loop: while true {
            fds[0].fd = stdinOpen ? STDIN_FILENO : -1
            guard poll(&fds, 2, -1) > 0 else { if errno == EINTR { continue }; break }
            if fds[1].revents & Int16(POLLIN | POLLHUP | POLLERR) != 0 {
                let n = read(fd, &buf, buf.count)
                if n <= 0 { break loop }
                // (Not `&buf[off]`: that points at a one-byte temporary copy, not into the buffer.)
                let ok = buf.withUnsafeBytes { p -> Bool in
                    var off = 0
                    while off < n {
                        let w = write(STDOUT_FILENO, p.baseAddress! + off, n - off)
                        if w <= 0 { return false }
                        off += w
                    }
                    return true
                }
                if !ok { break loop }
            }
            if stdinOpen, fds[0].revents & Int16(POLLIN | POLLHUP) != 0 {
                let n = read(STDIN_FILENO, &buf, buf.count)
                if n <= 0 { stdinOpen = false; continue }
                if write(fd, &buf, n) <= 0 { break loop }
            }
        }
        if isTTY { tcsetattr(STDIN_FILENO, TCSANOW, &original) }
        exit(0)
    }
}

/// Opening kitty windows (Shoji assumes kitty is installed).
@MainActor
enum Kitty {
    /// A new kitty window running `command` (each `open -n` is a new kitty instance, so the window
    /// closes with its command).
    static func open(title: String, _ command: [String]) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        p.arguments = ["-n", "-b", "net.kovidgoyal.kitty", "--args", "--title", title] + command
        try? p.run()
    }
}

enum Duration {
    /// "45s", "12m", "3h 5m", "2d 4h".
    static func short(_ t: TimeInterval) -> String {
        let s = Int(t)
        if s < 60 { return "\(s)s" }
        if s < 3600 { return "\(s / 60)m" }
        if s < 86400 { return "\(s / 3600)h \(s % 3600 / 60)m" }
        return "\(s / 86400)d \(s % 86400 / 3600)h"
    }
}
