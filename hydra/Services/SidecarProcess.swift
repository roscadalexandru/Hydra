import Foundation

// MARK: - Protocol

protocol SidecarProcessProtocol: AnyObject, Sendable {
    var events: AsyncStream<SidecarMessage> { get }
    var isRunning: Bool { get }
    func start() throws
    @discardableResult
    func send<P: Encodable>(method: String, params: P) throws -> Int
    func terminate()
}

// MARK: - Implementation

final class SidecarProcess: SidecarProcessProtocol, @unchecked Sendable {

    private let nodePath: String
    private let sidecarScript: String
    private let lock = NSLock()
    private var process: Process?
    private var stdinPipe: Pipe?
    private var nextRequestId = 1
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()
    private var eventContinuation: AsyncStream<SidecarMessage>.Continuation?
    private let readQueue = DispatchQueue(label: "com.hydra.sidecar.stdout")

    let events: AsyncStream<SidecarMessage>

    var isRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return process?.isRunning ?? false
    }

    init(nodePath: String? = nil, sidecarScript: String) {
        self.nodePath = nodePath ?? SidecarProcess.detectNodePath()
        self.sidecarScript = sidecarScript
        let (stream, continuation) = AsyncStream<SidecarMessage>.makeStream()
        self.events = stream
        self.eventContinuation = continuation
    }

    deinit {
        // Don't finish the continuation here — readStdout owns that via EOF.
        // Just force-kill the process if still running.
        lock.lock()
        let proc = process
        lock.unlock()
        if let proc = proc, proc.isRunning {
            proc.terminate()
        }
    }

    func start() throws {
        lock.lock()
        defer { lock.unlock() }

        guard process == nil else {
            throw SidecarProcessError.alreadyRunning
        }

        let proc = Process()
        let stdin = Pipe()
        let stdout = Pipe()

        proc.executableURL = URL(fileURLWithPath: nodePath)
        proc.arguments = [sidecarScript]
        proc.standardInput = stdin
        proc.standardOutput = stdout
        // Inherit parent's stderr — avoids 64KB pipe buffer deadlock
        // since we don't need to capture sidecar stderr programmatically

        self.process = proc
        self.stdinPipe = stdin

        // Ignore SIGPIPE so broken-pipe writes throw instead of crashing
        signal(SIGPIPE, SIG_IGN)

        try proc.run()

        // Read stdout on a dedicated dispatch queue (not the cooperative pool)
        let continuation = self.eventContinuation
        readQueue.async { [weak self, decoder] in
            SidecarProcess.readStdout(
                from: stdout.fileHandleForReading,
                decoder: decoder,
                continuation: continuation
            )
            // Nil out the continuation under lock after EOF
            self?.lock.lock()
            self?.eventContinuation = nil
            self?.lock.unlock()
        }
    }

    @discardableResult
    func send<P: Encodable>(method: String, params: P) throws -> Int {
        lock.lock()
        defer { lock.unlock() }

        guard let process = process, process.isRunning, let stdinPipe = stdinPipe else {
            throw SidecarProcessError.notRunning
        }

        let id = nextRequestId
        nextRequestId += 1

        let request = RpcRequest(id: id, method: method, params: params)
        let data = try encoder.encode(request)
        let handle = stdinPipe.fileHandleForWriting
        try handle.write(contentsOf: data)
        try handle.write(contentsOf: Data("\n".utf8))

        return id
    }

    func terminate() {
        lock.lock()
        guard let process = process, process.isRunning else {
            lock.unlock()
            return
        }
        lock.unlock()

        // Try graceful shutdown first
        try? send(method: "shutdown", params: [String: String]())

        // Close stdin so the sidecar receives EOF and can exit cleanly
        lock.lock()
        stdinPipe?.fileHandleForWriting.closeFile()
        lock.unlock()

        // Schedule forced termination after 2 seconds
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.lock.lock()
            let proc = self?.process
            self?.lock.unlock()
            if let proc = proc, proc.isRunning {
                proc.terminate()
            }
        }
    }

    // MARK: - Private

    private static func readStdout(
        from handle: FileHandle,
        decoder: JSONDecoder,
        continuation: AsyncStream<SidecarMessage>.Continuation?
    ) {
        var buffer = Data()
        let newline = UInt8(0x0A) // '\n'

        while true {
            let chunk = handle.availableData
            if chunk.isEmpty { break } // EOF

            buffer.append(chunk)

            while let newlineIndex = buffer.firstIndex(of: newline) {
                let lineData = buffer[buffer.startIndex..<newlineIndex]
                buffer = Data(buffer[buffer.index(after: newlineIndex)...])

                if lineData.isEmpty { continue }

                do {
                    let message = try decoder.decode(SidecarMessage.self, from: Data(lineData))
                    continuation?.yield(message)
                } catch {
                    #if DEBUG
                    NSLog("[SidecarProcess] Failed to decode line: %@\nRaw: %@", error.localizedDescription, String(data: Data(lineData), encoding: .utf8) ?? "<non-UTF8>")
                    #endif
                }
            }
        }

        continuation?.finish()
    }

    private static func detectNodePath() -> String {
        for path in ["/opt/homebrew/bin/node", "/usr/local/bin/node"] {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }
        // Fallback: try `which node`
        let proc = Process()
        let pipe = Pipe()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        proc.arguments = ["node"]
        proc.standardOutput = pipe
        do {
            try proc.run()
            proc.waitUntilExit()
            if proc.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if !path.isEmpty { return path }
            }
        } catch {}
        return "/usr/local/bin/node"
    }
}

enum SidecarProcessError: Error {
    case notRunning
    case alreadyRunning
}
