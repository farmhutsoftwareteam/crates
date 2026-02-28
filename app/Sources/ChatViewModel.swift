import Foundation
import Combine

struct ChatMessage: Identifiable {
    let id = UUID()
    var role: Role
    var text: String
    var isStreaming: Bool = false

    enum Role {
        case user
        case assistant
    }
}

@MainActor
class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var inputText: String = ""
    @Published var isThinking: Bool = false

    private var claude: ClaudeProcess?
    private var executor: ToolExecutor?
    private var currentAssistantMsgId: UUID?
    private var pendingTextBuffer = ""

    func setup(crateState: CrateState) {
        executor = ToolExecutor(crateState: crateState)
        let proc = ClaudeProcess()
        proc.onEvent = { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handle(event: event)
            }
        }
        proc.start(systemPrompt: PromptInstructions.system)
        claude = proc
    }

    func send() {
        let text = inputText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, let proc = claude, proc.isRunning else { return }
        inputText = ""
        messages.append(ChatMessage(role: .user, text: text))
        isThinking = true
        pendingTextBuffer = ""
        // Start a new assistant message placeholder
        let placeholder = ChatMessage(role: .assistant, text: "", isStreaming: true)
        currentAssistantMsgId = placeholder.id
        messages.append(placeholder)
        proc.send(userMessage: text)
    }

    func teardown() {
        claude?.stop()
        claude = nil
    }

    // MARK: - Event handling

    private func handle(event: ClaudeEvent) {
        switch event {
        case .assistantText(let chunk):
            pendingTextBuffer += chunk
            flushTextToCurrentMessage()

        case .toolAction(let action):
            // Execute the action
            let feedback = executor?.execute(action)
            // If the action returns data (e.g. get_crate), feed it back as a system message
            if let feedback {
                // Inject the crate state as next user turn context
                claude?.send(userMessage: "[Tool result]\n\(feedback)")
            }
            // Annotate the message that an action was taken
            appendActionAnnotation(action)

        case .turnEnd:
            finalizeCurrentMessage()
            isThinking = false

        case .error(let msg):
            finalizeCurrentMessage()
            isThinking = false
            messages.append(ChatMessage(role: .assistant, text: "⚠️ \(msg)"))

        case .unknown:
            break
        }
    }

    private func flushTextToCurrentMessage() {
        guard let id = currentAssistantMsgId,
              let idx = messages.firstIndex(where: { $0.id == id }) else { return }
        // Filter out any raw <crates-action> blocks from display
        let cleaned = cleanActionBlocks(pendingTextBuffer)
        messages[idx].text = cleaned
    }

    private func finalizeCurrentMessage() {
        guard let id = currentAssistantMsgId,
              let idx = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[idx].isStreaming = false
        if messages[idx].text.isEmpty {
            messages.remove(at: idx)
        }
        currentAssistantMsgId = nil
        pendingTextBuffer = ""
    }

    private func appendActionAnnotation(_ action: CratesAction) {
        let label: String
        switch action {
        case .getCrate:              label = "🔍 Reading crate…"
        case .reorderSongs:          label = "🔀 Reordered set"
        case .addSong(let t, _, _, _, _): label = "➕ Added \"\(t)\""
        case .setSongNotes(let p, _):label = "📝 Updated track \(p) notes"
        case .suggestOrder:          label = "🤔 Analysing energy flow…"
        }
        // Insert annotation before the current streaming message
        let annotation = ChatMessage(role: .assistant, text: label)
        if let id = currentAssistantMsgId,
           let idx = messages.firstIndex(where: { $0.id == id }) {
            messages.insert(annotation, at: idx)
        } else {
            messages.append(annotation)
        }
    }

    // MARK: - Helpers

    private func cleanActionBlocks(_ text: String) -> String {
        let pattern = #"<crates-action>[\s\S]*?</crates-action>"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
