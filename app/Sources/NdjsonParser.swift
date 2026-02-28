import Foundation

/// Parses a stream of bytes into NDJSON lines and converts them to ClaudeEvents.
struct NdjsonParser {

    /// Parse raw bytes into Claude events. Handles partial lines across calls.
    static func parse(line: String) -> ClaudeEvent {
        guard let data = line.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .unknown
        }

        let type = json["type"] as? String ?? ""

        switch type {
        case "assistant":
            // { type: "assistant", message: { content: [{ type: "text", text: "..." }] } }
            if let message = json["message"] as? [String: Any],
               let content = message["content"] as? [[String: Any]] {
                let text = content
                    .filter { $0["type"] as? String == "text" }
                    .compactMap { $0["text"] as? String }
                    .joined()
                if !text.isEmpty {
                    return parseAssistantText(text)
                }
            }
            return .unknown

        case "content_block_delta":
            // { type: "content_block_delta", delta: { type: "text_delta", text: "..." } }
            if let delta = json["delta"] as? [String: Any],
               delta["type"] as? String == "text_delta",
               let text = delta["text"] as? String {
                return parseAssistantText(text)
            }
            return .unknown

        case "message_stop", "message_delta":
            if type == "message_stop" { return .turnEnd }
            return .unknown

        case "result":
            // Stream-json final result object
            if let subtype = json["subtype"] as? String, subtype == "error",
               let errorMsg = json["error"] as? String {
                return .error(errorMsg)
            }
            return .turnEnd

        case "system":
            // Init message, ignore
            return .unknown

        case "error":
            let msg = (json["error"] as? [String: Any])?["message"] as? String ?? "Unknown error"
            return .error(msg)

        default:
            return .unknown
        }
    }

    // MARK: - Text parsing: extract <crates-action> blocks

    private static func parseAssistantText(_ text: String) -> ClaudeEvent {
        // Check if the full accumulated text (or this chunk) contains a crates-action block
        // We look for complete blocks within this chunk
        let pattern = #"<crates-action>([\s\S]*?)</crates-action>"#
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let range = Range(match.range(at: 1), in: text) {
            let json = String(text[range])
            if let action = CratesAction.decode(from: json) {
                return .toolAction(action)
            }
        }
        return .assistantText(text)
    }
}
