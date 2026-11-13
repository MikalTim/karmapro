// by cipher.org.uk
import Foundation

/// The AI Assistant's conversation (`AIWindowController`'s agent loop) without
/// its drawing: one conversation per server, like the one shared AI window.
///
/// Sending a prompt starts a streaming round with the project's sandboxed tools
/// (`list_files`, `read_file`, `search_files`, `run_command`); when the model asks
/// for tools they run, their results join the conversation and the next round starts,
/// at most five times. A task cut short (Stop, or a connection that dropped) keeps its
/// context so Continue can resume it.
///
/// Every change is posted as an `ai.stream` event `{seq, kind, text, level?}` with
/// `kind` one of:
///  - `delta`        text of the answer being written (append it);
///  - `thinking`     the model began reasoning (a "Thinking…" indicator replaces the text);
///  - `tool`         a tool ran: `text` is JSON `{label, output}` (the transcript's tool entry);
///  - `status`       the status line changed: `text`, with `level` `"info"` or `"error"`;
///  - `turnFinished` the round ended: fetch `state()` (the transcript now holds the answer);
///  - `error`        a request could not start: `text` is the message.
/// `seq` increases by one per event, so a front end that sees a gap fetches `state()`.
public final class AIChatService: @unchecked Sendable {
    public static let shared = AIChatService()

    /// One chronological item of the transcript pane.
    public struct EntryDTO: Codable, Sendable {
        /// "turn" (the dim "> prompt" marker), "tool" or "answer".
        public var kind: String
        /// Turn: the marker as shown (one line, at most 100 characters). Tool: the label line. Answer: the markdown text.
        public var text: String
        /// Tool only: the output as the pane shows it.
        public var output: String?
    }

    public struct StateDTO: Codable, Sendable {
        public var transcript: [EntryDTO]
        /// The answer being written (markdown), empty between rounds.
        public var streaming: String
        /// The model is reasoning and has not started answering.
        public var thinking: Bool
        /// A request is running: the Send button reads "Stop".
        public var requestInFlight: Bool
        public var canContinue: Bool
        public var canNewChat: Bool
        public var status: String
        /// "info" or "error".
        public var statusLevel: String
        /// The Send button's title: "Stop" while a request is running, else "Send to AI".
        public var sendTitle: String
        /// The sequence number of the last `ai.stream` event this state includes.
        public var seq: Int
    }

    private enum Entry {
        case turnMarker(String)
        case tool(name: String, args: String, output: String)
        case answer(String)
    }

    /// Serialises every state change, as the main thread does in the AppKit window.
    private let queue = DispatchQueue(label: "app.karmapro.service.ai-chat")
    private let bus = KarmaEventBus.shared

    private var conversation: [[String: Any]] = []
    private var transcript: [Entry] = []
    private var streamAccumulated = ""
    private var modelIsThinking = false
    private var requestInFlight = false
    /// Set when the user cancels via Stop, so the completion message can say the response was cut on purpose.
    private var cancelRequested = false
    /// True after the non-streaming fallback has been attempted once.
    private var usedFallback = false
    private var toolRound = 0
    /// True when the last task ended interrupted with its context still in `conversation`.
    private var lastTaskInterrupted = false
    private var status = ""
    private var statusLevel = "info"
    private var seq = 0

    init() {}

    // MARK: - State

    public func state() -> StateDTO {
        queue.sync { stateLocked() }
    }

    private func stateLocked() -> StateDTO {
        StateDTO(transcript: transcript.map { entry in
                    switch entry {
                    case .turnMarker(let text):
                        let oneLine = text.replacingOccurrences(of: "\n", with: " ")
                        let label = oneLine.count > 100 ? String(oneLine.prefix(100)) + "\u{2026}" : oneLine
                        return EntryDTO(kind: "turn", text: "> \(label)", output: nil)
                    case .tool(let name, let args, let output):
                        return EntryDTO(kind: "tool", text: AIChatText.toolDisplayLabel(name: name, args: args),
                                        output: AIChatText.toolDisplayOutput(output))
                    case .answer(let text):
                        return EntryDTO(kind: "answer", text: text, output: nil)
                    }
                 },
                 streaming: streamAccumulated,
                 thinking: modelIsThinking && requestInFlight,
                 requestInFlight: requestInFlight,
                 canContinue: !requestInFlight && lastTaskInterrupted && !conversation.isEmpty,
                 canNewChat: !requestInFlight && !conversation.isEmpty,
                 status: status,
                 statusLevel: statusLevel,
                 sendTitle: requestInFlight ? "Stop" : "Send to AI",
                 seq: seq)
    }

    private func post(_ kind: String, _ text: String, level: String? = nil) {
        seq += 1
        bus.post("ai.stream", StreamEvent(seq: seq, kind: kind, text: text, level: level))
    }

    private struct StreamEvent: Codable {
        var seq: Int
        var kind: String
        var text: String
        var level: String?
    }

    private func setStatus(_ text: String, error: Bool = false) {
        status = text
        statusLevel = error ? "error" : "info"
        post("status", text, level: statusLevel)
    }

    // MARK: - Actions

    /// The Send button. While a request is running it acts as Stop (`sendClicked`).
    public func send(text: String) -> StateDTO {
        queue.sync {
            if requestInFlight {
                stopRequestedLocked()
                return stateLocked()
            }
            let prompt = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !prompt.isEmpty else {
                setStatus("Type or paste a prompt first.", error: true)
                return stateLocked()
            }
            guard keyIsPresentLocked() else { return stateLocked() }
            runUserTurn(content: prompt, marker: prompt, model: OpenRouterClient.shared.selectedModel,
                        isNewConversation: conversation.isEmpty)
            return stateLocked()
        }
    }

    /// A ready-made "How to fix it" request for a finding, sent like the Send button does.
    public func askHowToFix(path: String, line: Int, lineText: String) -> StateDTO {
        send(text: "How to fix the vulnerability at: \(path):\(line)\n\n\(lineText)")
    }

    /// An arbitrary ready-made question, sent like the Send button does (the package scan's right-click menu).
    public func ask(_ question: String) -> StateDTO {
        send(text: question)
    }

    /// Resumes the interrupted task: the whole conversation is sent back with an instruction to continue.
    public func continueTurn() -> StateDTO {
        queue.sync {
            guard !requestInFlight, lastTaskInterrupted, !conversation.isEmpty else { return stateLocked() }
            guard keyIsPresentLocked() else { return stateLocked() }
            runUserTurn(content: "Your previous response was interrupted. Continue exactly where you stopped \u{2014} do not repeat text you already produced, and complete the remaining work.",
                        marker: "continue interrupted response",
                        model: OpenRouterClient.shared.selectedModel,
                        isNewConversation: false)
            return stateLocked()
        }
    }

    /// Clears the conversation and the transcript so the next prompt starts fresh.
    public func newChat() -> StateDTO {
        queue.sync {
            guard !requestInFlight else { return stateLocked() }
            conversation = []
            transcript = []
            streamAccumulated = ""
            modelIsThinking = false
            toolRound = 0
            lastTaskInterrupted = false
            cancelRequested = false
            usedFallback = false
            setStatus("New conversation \u{2014} the previous context was cleared.")
            post("turnFinished", "")
            return stateLocked()
        }
    }

    /// Stop: cancels the request in flight; the partial answer is kept.
    public func stop() -> StateDTO {
        queue.sync {
            if requestInFlight { stopRequestedLocked() }
            return stateLocked()
        }
    }

    /// `sendClicked` / `continueClicked` refuse to start without an API key for providers that need one.
    private func keyIsPresentLocked() -> Bool {
        let client = OpenRouterClient.shared
        if client.requiresAPIKey && client.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            setStatus("Enter your \(client.provider.name) API key and click Connect.", error: true)
            return false
        }
        return true
    }

    // MARK: - The agent loop

    /// Appends a user turn (refreshing the system message so the open project is described) and starts the
    /// streaming loop. The first prompt starts a new conversation; later prompts append to it.
    private func runUserTurn(content: String, marker: String, model: String, isNewConversation: Bool) {
        let root = KarmaWorkspace.shared.read { $0.root }
        if isNewConversation {
            conversation = [["role": "system", "content": AIChatText.systemPrompt(projectRoot: root)],
                            ["role": "user", "content": content]]
            transcript = [.turnMarker(marker)]
        } else {
            if let first = conversation.first, first["role"] as? String == "system" {
                conversation[0]["content"] = AIChatText.systemPrompt(projectRoot: root)
            }
            conversation.append(["role": "user", "content": content])
            transcript.append(.turnMarker(marker))
        }
        streamAccumulated = ""
        modelIsThinking = false
        cancelRequested = false
        usedFallback = false
        toolRound = 0
        lastTaskInterrupted = false
        requestInFlight = true
        setStatus("Waiting for \(model)\u{2026}")
        post("turnFinished", "")
        runStreamingRound(model: model)
    }

    /// One streaming round. When the model asks for tools they are executed, the results are appended and
    /// the next round starts.
    private func runStreamingRound(model: String) {
        // Stop pressed between rounds: no new request is started and no completion will fire.
        guard !cancelRequested else {
            requestInFlight = false
            post("turnFinished", "")
            return
        }
        let started = OpenRouterClient.shared.sendStreamingMessages(
            messages: conversation,
            tools: AIToolExecutor.toolDefinitions,
            model: model,
            onPart: { [self] part in
                queue.async { [self] in
                    guard requestInFlight else { return }
                    switch part {
                    case .reasoning:
                        if !modelIsThinking {
                            modelIsThinking = true
                            setStatus("Model is thinking\u{2026}")
                            post("thinking", "")
                        }
                    case .content(let text):
                        if streamAccumulated.isEmpty { setStatus("Receiving response\u{2026}") }
                        modelIsThinking = false
                        streamAccumulated += text
                        post("delta", text)
                    }
                }
            },
            completion: { [self] result in
                queue.async { [self] in
                    switch result {
                    case .failure(let error):
                        finishStreamingRound(error: error, model: model)
                    case .success(let streamResult):
                        if streamResult.toolCalls.isEmpty || toolRound >= 5 {
                            finishStreamingRound(success: streamResult, model: model)
                        } else {
                            executeToolCalls(streamResult, model: model)
                        }
                    }
                }
            })
        if !started {
            requestInFlight = false
            post("turnFinished", "")
        }
    }

    private func finishStreamingRound(success: OpenRouterStreamResult? = nil, error: Error? = nil, model: String = "") {
        requestInFlight = false
        if let result = success {
            // A stream that died mid-answer arrives as a success carrying the part that arrived, marked as interrupted.
            let cutShort = result.interrupted && !result.content.isEmpty
            finalizeAssistantTurn(content: result.content, interrupted: cancelRequested || cutShort)
            if cancelRequested {
                lastTaskInterrupted = true
                setStatus("Stopped \u{2014} press Continue to resume with context, or type a new prompt.")
            } else if cutShort {
                lastTaskInterrupted = true
                setStatus("The connection dropped before the answer was finished \u{2014} press Continue to resume with context.")
            } else {
                lastTaskInterrupted = false
                setStatus("Done.")
            }
        } else if let error {
            if (error as NSError).code == NSURLErrorCancelled {
                finalizeAssistantTurn(content: streamAccumulated, interrupted: true)
                lastTaskInterrupted = true
                setStatus("Cancelled \u{2014} press Continue to resume with context.")
            } else if !usedFallback && toolRound == 0 {
                // Streaming failed (timeout or connection): retry once without streaming so an answer still arrives.
                sendFallback(model: model)
                return
            } else {
                finalizeAssistantTurn(content: streamAccumulated, interrupted: !streamAccumulated.isEmpty)
                lastTaskInterrupted = true
                setStatus("Failed: \(error.localizedDescription) \u{2014} press Continue to retry with context.", error: true)
            }
        }
        post("turnFinished", "")
    }

    /// Moves the finished round's text into the transcript and appends the assistant message to the
    /// conversation, so later prompts and Continue see everything produced so far. Interrupted answers are
    /// stored with a marker telling the model where it stopped.
    private func finalizeAssistantTurn(content: String, interrupted: Bool) {
        if !content.isEmpty {
            transcript.append(.answer(content))
            let stored = interrupted
                ? content + "\n\n_[response interrupted here \u{2014} continue from this point]_"
                : content
            conversation.append(["role": "assistant", "content": stored])
        }
        streamAccumulated = ""
        modelIsThinking = false
    }

    /// Runs the model's requested tools concurrently on background queues, appends their results to the
    /// conversation and starts the next streaming round.
    private func executeToolCalls(_ streamResult: OpenRouterStreamResult, model: String) {
        toolRound += 1
        // The assistant turn that requested the tools.
        var assistantMessage: [String: Any] = ["role": "assistant"]
        assistantMessage["content"] = streamResult.content.isEmpty ? NSNull() : streamResult.content
        assistantMessage["tool_calls"] = streamResult.toolCalls.map { call in
            ["id": call.id, "type": "function",
             "function": ["name": call.name, "arguments": call.arguments]]
        }
        conversation.append(assistantMessage)

        guard let root = KarmaWorkspace.shared.read({ $0.root }) else {
            requestInFlight = false
            setStatus("No project open \u{2014} tools need a project.", error: true)
            post("turnFinished", "")
            return
        }
        let executor = AIToolExecutor(projectRoot: root)
        setStatus("Running tools (round \(toolRound))\u{2026}")

        var results: [Int: String] = [:]
        // Several tools run at once; a dictionary is not safe to mutate from several threads.
        let resultsLock = NSLock()
        let group = DispatchGroup()
        for (index, call) in streamResult.toolCalls.enumerated() {
            group.enter()
            DispatchQueue.global().async { [self] in
                let output = executor.execute(name: call.name, argumentsJSON: call.arguments)
                resultsLock.lock()
                results[index] = output
                resultsLock.unlock()
                queue.async { [self] in
                    let shown = String(output.prefix(4000))
                    transcript.append(.tool(name: call.name, args: call.arguments, output: shown))
                    let payload = ToolEvent(label: AIChatText.toolDisplayLabel(name: call.name, args: call.arguments),
                                            output: AIChatText.toolDisplayOutput(shown))
                    post("tool", String(decoding: KarmaJSON.data(payload), as: UTF8.self))
                }
                group.leave()
            }
        }
        group.notify(queue: queue) { [self] in
            // Stop pressed while tools ran: no next round will start and no completion will fire. Every
            // requested tool call still needs a tool message before the conversation may continue.
            guard !cancelRequested else {
                for call in streamResult.toolCalls {
                    conversation.append(["role": "tool",
                                         "tool_call_id": call.id,
                                         "content": "{\"ok\":false,\"error\":\"stopped by user before execution\"}"])
                }
                lastTaskInterrupted = true
                finalizeAssistantTurn(content: streamAccumulated, interrupted: true)
                requestInFlight = false
                setStatus("Stopped \u{2014} press Continue to resume with context.")
                post("turnFinished", "")
                return
            }
            resultsLock.lock()
            let collected = results
            resultsLock.unlock()
            for (index, call) in streamResult.toolCalls.enumerated() {
                conversation.append(["role": "tool",
                                     "tool_call_id": call.id,
                                     "content": collected[index] ?? "{\"ok\":false,\"error\":\"no result\"}"])
            }
            streamAccumulated = ""   // the next round's answer replaces this round's text
            runStreamingRound(model: model)
        }
    }

    private struct ToolEvent: Codable {
        var label: String
        var output: String
    }

    /// One-shot retry through the non-streaming endpoint (when the streaming request failed). The whole
    /// conversation is sent so the retry keeps the same context.
    private func sendFallback(model: String) {
        usedFallback = true
        setStatus("Streaming unavailable \u{2014} retrying without streaming\u{2026}")
        requestInFlight = true
        OpenRouterClient.shared.sendChatMessages(messages: conversation, model: model) { [self] result in
            queue.async { [self] in
                requestInFlight = false
                switch result {
                case .success(let content):
                    finalizeAssistantTurn(content: content, interrupted: false)
                    lastTaskInterrupted = false
                    setStatus("Done (non-streaming).")
                case .failure(let error):
                    if (error as NSError).code == NSURLErrorCancelled {
                        finalizeAssistantTurn(content: streamAccumulated, interrupted: true)
                        lastTaskInterrupted = true
                        setStatus("Cancelled \u{2014} press Continue to resume with context.")
                    } else {
                        finalizeAssistantTurn(content: streamAccumulated, interrupted: !streamAccumulated.isEmpty)
                        lastTaskInterrupted = true
                        setStatus("Failed: \(error.localizedDescription) \u{2014} press Continue to retry with context.", error: true)
                    }
                }
                post("turnFinished", "")
            }
        }
    }

    /// Stop: cancel the request in flight; the partial response is kept.
    private func stopRequestedLocked() {
        cancelRequested = true
        setStatus("Cancelling\u{2026}")
        OpenRouterClient.shared.cancelActiveStream(scope: .assistant)
        // Between streaming rounds (while tools run) there is no network request to cancel and no completion
        // will fire: finish the round here, or the Stop button would stay stuck.
        guard OpenRouterClient.shared.hasActiveRequest(scope: .assistant) else {
            if !streamAccumulated.isEmpty || modelIsThinking {
                finishStreamingRound(success: OpenRouterStreamResult(reasoning: "", content: streamAccumulated, toolCalls: []))
            } else {
                finishStreamingRound(error: NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled,
                                                    userInfo: [NSLocalizedDescriptionKey: "Request cancelled."]))
            }
            return
        }
    }
}
