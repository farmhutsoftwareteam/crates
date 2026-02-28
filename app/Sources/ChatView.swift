import SwiftUI

struct ChatView: View {
    let onDismiss: () -> Void
    @EnvironmentObject var chatVM:     ChatViewModel
    @EnvironmentObject var crateState: CrateState
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // ── Header ───────────────────────────────────────────
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("ASH")
                        .font(.system(size: 12, weight: .black))
                        .tracking(4)
                        .foregroundColor(.cratesPrimary)
                    Text("DJ SET ADVISOR")
                        .font(.system(size: 8, weight: .bold))
                        .tracking(2.5)
                        .foregroundColor(.cratesDim)
                }
                Spacer()
                Circle()
                    .fill(chatVM.isThinking ? Color.orange : Color.cratesLive)
                    .frame(width: 6, height: 6)

                // ── Close button ─────────────────────────────────
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.cratesDim)
                        .frame(width: 24, height: 24)
                        .background(Color.cratesBorder)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [])
                .padding(.leading, 8)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.cratesSurface)

            Rectangle().fill(Color.cratesBorder).frame(height: 1)

            // ── Messages ─────────────────────────────────────────
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        if chatVM.messages.isEmpty {
                            Text("Ask me to sort by energy, analyse BPM flow, or suggest Camelot key transitions.")
                                .font(.system(size: 11))
                                .foregroundColor(.cratesDim)
                                .padding(14)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        ForEach(chatVM.messages) { msg in
                            AshChatBubble(message: msg)
                                .id(msg.id)
                        }
                        if chatVM.isThinking {
                            AshThinkingIndicator()
                                .id("thinking")
                        }
                    }
                    .padding(.vertical, 10)
                }
                .background(Color.cratesBg)
                .onChange(of: chatVM.messages.count) { _ in
                    if let last = chatVM.messages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }

            Rectangle().fill(Color.cratesBorder).frame(height: 1)

            // ── Input ────────────────────────────────────────────
            HStack(alignment: .bottom, spacing: 10) {
                TextField("Ask Ash…", text: $chatVM.inputText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundColor(.cratesPrimary)
                    .lineLimit(1...5)
                    .focused($inputFocused)
                    .onSubmit {
                        if !NSEvent.modifierFlags.contains(.shift) { chatVM.send() }
                    }

                let isEmpty = chatVM.inputText.trimmingCharacters(in: .whitespaces).isEmpty
                Button(action: chatVM.send) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 10, weight: .black))
                        .foregroundColor(isEmpty ? .cratesGhost : Color.cratesBg)
                        .frame(width: 24, height: 24)
                        .background(isEmpty ? Color.cratesBorder : Color.cratesAccent)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(isEmpty)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.cratesSurface)
        }
        .background(Color.cratesBg)
        .onAppear {
            chatVM.setup(crateState: crateState)
            inputFocused = true
        }
    }
}

// MARK: - Bubble

struct AshChatBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == .user {
                Spacer(minLength: 32)
                Text(message.text)
                    .font(.system(size: 12))
                    .foregroundColor(Color.cratesBg)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.cratesAccent)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                Text(message.text + (message.isStreaming ? "▌" : ""))
                    .font(.system(size: 12))
                    .foregroundColor(.cratesDim)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.cratesElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                Spacer(minLength: 32)
            }
        }
        .padding(.horizontal, 10)
    }
}

// MARK: - Thinking indicator

struct AshThinkingIndicator: View {
    @State private var heights: [CGFloat] = [4, 4, 4]

    var body: some View {
        HStack(alignment: .center, spacing: 4) {
            ForEach(0..<3) { i in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.cratesAccent.opacity(0.7))
                    .frame(width: 3, height: heights[i])
                    .animation(
                        .easeInOut(duration: 0.45)
                        .repeatForever(autoreverses: true)
                        .delay(Double(i) * 0.15),
                        value: heights[i]
                    )
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.cratesElevated)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 10)
        .onAppear { heights = [12, 18, 8] }
    }
}
