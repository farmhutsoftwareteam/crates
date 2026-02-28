import Foundation
import Combine

/// Spawns and manages the Claude CLI subprocess, sending and receiving NDJSON.
@MainActor
class ClaudeProcess: ObservableObject {
    private var process: Process?
    private var stdinPipe: Pipe?
    private var stdoutPipe: Pipe?
    private var lineBuffer = ""

    var onEvent: ((ClaudeEvent) -> Void)?

    var isRunning: Bool { process?.isRunning == true }

    // MARK: - Lifecycle

    func start(systemPrompt: String) {
        guard !isRunning else { return }

        let claudePath = findClaudePath() ?? "/usr/local/bin/claude"

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: claudePath)
        proc.arguments = [
            "--output-format", "stream-json",
            "--input-format", "stream-json",
            "--dangerously-skip-permissions",
            "--system", systemPrompt,
        ]
        // Strip CLAUDECODE so claude can run as a subprocess
        var env = ProcessInfo.processInfo.environment
        env.removeValue(forKey: "CLAUDECODE")
        proc.environment = env

        let stdin  = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        proc.standardInput  = stdin
        proc.standardOutput = stdout
        proc.standardError  = stderr

        stdinPipe  = stdin
        stdoutPipe = stdout

        // Read stdout on background thread
        stdout.fileHandleForReading.readabilityHandler = { [weak self] fh in
            let data = fh.availableData
            guard !data.isEmpty else { return }
            if let text = String(data: data, encoding: .utf8) {
                Task { @MainActor [weak self] in
                    self?.handleRawOutput(text)
                }
            }
        }

        // Ignore stderr (or log)
        stderr.fileHandleForReading.readabilityHandler = { fh in
            _ = fh.availableData
        }

        proc.terminationHandler = { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.onEvent?(.turnEnd)
            }
        }

        do {
            try proc.run()
            process = proc
        } catch {
            onEvent?(.error("Failed to launch Claude: \(error.localizedDescription)"))
        }
    }

    func stop() {
        process?.terminate()
        process = nil
        stdinPipe = nil
        stdoutPipe = nil
    }

    // MARK: - Send message

    func send(userMessage: String) {
        guard isRunning, let pipe = stdinPipe else { return }
        let payload: [String: Any] = ["type": "user", "message": ["role": "user", "content": userMessage]]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let line = String(data: data, encoding: .utf8) else { return }
        let bytes = Data((line + "\n").utf8)
        pipe.fileHandleForWriting.write(bytes)
    }

    // MARK: - Output parsing

    private func handleRawOutput(_ text: String) {
        lineBuffer += text
        while let newlineRange = lineBuffer.range(of: "\n") {
            let line = String(lineBuffer[lineBuffer.startIndex..<newlineRange.lowerBound])
            lineBuffer.removeSubrange(lineBuffer.startIndex...newlineRange.lowerBound)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty {
                let event = NdjsonParser.parse(line: trimmed)
                onEvent?(event)
            }
        }
    }

    // MARK: - Locate claude CLI

    private func findClaudePath() -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            "\(home)/.local/bin/claude",
            "\(home)/.claude/local/claude",
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
            "/usr/bin/claude",
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0) }
    }
}
