import AppKit

enum JokeSource: String, CaseIterable {
    case dark
    case dad
    case advice
    case quote
    var title: String {
        switch self {
        case .dark: return "Dark Jokes"
        case .dad: return "Dad Jokes"
        case .advice: return "Advice"
        case .quote: return "Quotes"
        }
    }
}

private let stateKey = "meowy-cat"
private let scaleKey = "meowy-cat-scale"
private let modeKey = "meowy-cat-mode"
private let speedKey = "meowy-cat-speed"
private let jokesKey = "meowy-cat-jokes"
private let jokeSourceKey = "meowy-cat-joke-source"
private let agentsKey = "meowy-cat-agents"
private let catNameKey = "meowy-cat-name"
private let displayNameKey = "meowy-cat-display-name"
private let minimumSpeedPercent: CGFloat = 25
private let maximumSpeedPercent: CGFloat = 200
private let baseCatSize: CGFloat = 32
private let messageFont = NSFont.systemFont(ofSize: 12, weight: .medium)
private let messageCornerRadius: CGFloat = 12
private let messageBorderWidth: CGFloat = 0.5
private let messageHorizontalPadding: CGFloat = 18
private let messageVerticalPadding: CGFloat = 12
private let messageMaxWidth: CGFloat = 320
private let messageMinWidth: CGFloat = 120
private let messageTextWidth: CGFloat = messageMaxWidth - messageHorizontalPadding * 2
private final class CatPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class MeowyController: NSObject {
    private let sprites: SpriteSheet
    private let defaults: UserDefaults
    private let panel: CatPanel
    private let spriteView: SpriteView
    private var simulation: CatSimulation
    private var catScale: CGFloat
    private var speedPercent: CGFloat
    private(set) var mode: CatMode
    private var timer: Timer?
    private var screens: [CGRect] = []
    private var dockBounds = CGRect.zero
    private var isSuspended = false
    private(set) var isRunning = false
    private(set) var jokesEnabled: Bool
    private(set) var jokeSource: JokeSource
    private(set) var agentsEnabled: Bool
    private var agentMonitorTimer: Timer?
    private var agentStackPanel: NSPanel?
    private var agentStack: NSStackView?
    private var agentFloatPhase: CGFloat = 0
    private var pomodoroPanel: NSPanel?
    private var pomodoroLabel: NSTextField?
    private var pomodoroEnd: Date?
    private var pomodoroFloatPhase: CGFloat = 0
    private var pomodoroBlinkTimer: Timer?
    private var pomodoroCompletedUntil: Date?
    private var pomodoroTimer: Timer?
    private var reminderDue: Date?
    private var reminderTimer: Timer?
    private var reminderMessage: String = ""
    private var reminderShowingUntil: Date?
    private var reminderDisplayText: String = "Reminder"
    private var reminderBlinkTimer: Timer?
    private var isAgentActive = false
    private var lastClaudeStatus: String?
    private var claudeCompletionUntil: Date?
    private var lastCodexStatus: String?
    private var codexCompletionUntil: Date?
    private var lastCursorStatus: String?
    private var cursorCompletionUntil: Date?
    private var completionHideTimer: Timer?
    private(set) var catName: String
    private var isNameHovering = false
    private var namePanel: NSPanel?
    private var nameLabel: NSTextField?
    private var jokePanel: NSPanel?
    private var jokeBubbleView: NSView?
    private var jokeLabel: NSTextField?
    private var jokeHideTimer: Timer?
    private var jokeFetchTimer: Timer?
    private var isJokePaused = false
    private var isJokeBursting = false
    private var jokeFloatPhase: CGFloat = 0
    var scale: CGFloat { catScale }
    var speed: CGFloat { speedPercent }

    init(sprites: SpriteSheet, defaults: UserDefaults = .standard) {
        self.sprites = sprites
        self.defaults = defaults
        let storedScale = defaults.object(forKey: scaleKey) as? Double ?? 1
        self.catScale = min(max(CGFloat(storedScale), 0.5), 2.5)
        let storedSpeed = defaults.object(forKey: speedKey) as? Double ?? 100
        self.speedPercent = min(max(CGFloat(storedSpeed), minimumSpeedPercent), maximumSpeedPercent)
        self.mode = defaults.string(forKey: modeKey)
            .flatMap(CatMode.init(rawValue:)) ?? .cursor
        if let storedJokes = defaults.object(forKey: jokesKey) as? Bool {
            self.jokesEnabled = storedJokes
        } else {
            self.jokesEnabled = true
        }
        self.jokeSource = JokeSource(rawValue: defaults.string(forKey: jokeSourceKey) ?? "") ?? .dark
        if let storedAgents = defaults.object(forKey: agentsKey) as? Bool {
            self.agentsEnabled = storedAgents
        } else {
            self.agentsEnabled = true
        }
        self.catName = defaults.string(forKey: catNameKey) ?? "Meowy"
        let saved = defaults.data(forKey: stateKey)
            .flatMap { try? JSONDecoder().decode(CatState.self, from: $0) }
        simulation = CatSimulation(state: saved ?? CatState())
        if mode == .dock {
            simulation.enterDockMode()
        }

        let catSize = baseCatSize * catScale
        panel = CatPanel(contentRect: CGRect(x: 0, y: 0, width: catSize, height: catSize),
                         styleMask: [.borderless, .nonactivatingPanel],
                         backing: .buffered, defer: false)
        spriteView = SpriteView(frame: CGRect(x: 0, y: 0, width: catSize, height: catSize))
        super.init()

        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isExcludedFromWindowsMenu = true
        panel.isMovable = false
        spriteView.setAccessibilityElement(false)
        spriteView.autoresizingMask = [.width, .height]
        panel.contentView = spriteView

        updateScreens()
        if !simulation.state.position.x.isFinite || !simulation.state.position.y.isFinite {
            simulation.state = CatState()
        }
        constrainPosition()
        drawCat()

        NotificationCenter.default.addObserver(self, selector: #selector(updateScreens),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
        let notifications = NSWorkspace.shared.notificationCenter
        notifications.addObserver(self, selector: #selector(suspend), name: NSWorkspace.willSleepNotification, object: nil)
        notifications.addObserver(self, selector: #selector(suspend), name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        notifications.addObserver(self, selector: #selector(resume), name: NSWorkspace.didWakeNotification, object: nil)
        notifications.addObserver(self, selector: #selector(resume), name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
        notifications.addObserver(self, selector: #selector(updateActivity),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        updateScreens()
        updateActivity()
        if mode == .dock { startJokeSchedule() }
        if agentsEnabled { startAgentMonitor() }
    }

    func stop() {
        isRunning = false
        jokeHideTimer?.invalidate()
        jokeHideTimer = nil
        jokeFetchTimer?.invalidate()
        jokeFetchTimer = nil
        stopAgentMonitor()
        pomodoroTimer?.invalidate()
        reminderTimer?.invalidate()
        reminderTimer = nil
        reminderBlinkTimer?.invalidate()
        reminderBlinkTimer = nil
        pomodoroTimer = nil
        isJokePaused = false
        jokePanel?.orderOut(nil)
        updateActivity()
        saveState()
    }

    func setScale(_ scale: CGFloat) {
        catScale = min(max(scale, 0.5), 2.5)
        defaults.set(Double(catScale), forKey: scaleKey)
        updateDockBounds()
        constrainPosition()

        let catSize = baseCatSize * catScale
        spriteView.frame = CGRect(x: 0, y: 0, width: catSize, height: catSize)
        panel.setFrame(
            CGRect(x: simulation.state.position.x - catSize / 2,
                   y: simulation.state.position.y - catSize / 2,
                   width: catSize,
                   height: catSize),
            display: true,
        )
        drawCat()
    }

    func setSpeedPercent(_ speed: CGFloat) {
        speedPercent = min(max(speed, minimumSpeedPercent), maximumSpeedPercent)
        defaults.set(Double(speedPercent), forKey: speedKey)
    }

    func setMode(_ mode: CatMode) {
        guard self.mode != mode else { return }
        self.mode = mode
        defaults.set(mode.rawValue, forKey: modeKey)
        if mode == .dock {
            simulation.enterDockMode()
            if isRunning { startJokeSchedule() }
        } else {
            simulation.enterCursorMode()
            stopJokeSchedule()
            isJokePaused = false
            jokeHideTimer?.invalidate()
            jokeHideTimer = nil
            jokePanel?.orderOut(nil)
        }
        constrainPosition()
        drawCat()
        saveState()
    }


    func setJokeSource(_ source: JokeSource) {
        jokeSource = source
        defaults.set(source.rawValue, forKey: jokeSourceKey)
    }

    func setJokesEnabled(_ enabled: Bool) {
        jokesEnabled = enabled
        defaults.set(enabled, forKey: jokesKey)
        if enabled {
            if isRunning && mode == .dock { startJokeSchedule() }
        } else {
            stopJokeSchedule()
            if isJokePaused { hideJokeBubble() }
        }
    }


    func setAgentsEnabled(_ enabled: Bool) {
        agentsEnabled = enabled
        defaults.set(enabled, forKey: agentsKey)
        if enabled {
            startAgentMonitor()
        } else {
            stopAgentMonitor()
            isAgentActive = false
            agentBubbleHideIfPossible()
        }
    }

    func startAgentMonitor() {
        stopAgentMonitor()
        guard isRunning, agentsEnabled else { return }
        agentMonitorTimer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            DispatchQueue.main.async { [weak self] in self?.pollAgentStatus() }
        }
        if let t = agentMonitorTimer { RunLoop.main.add(t, forMode: .common) }
        pollAgentStatus()
    }

    func stopAgentMonitor() {
        agentMonitorTimer?.invalidate()
        agentMonitorTimer = nil
    }

    private func agentMessageFile() -> String? {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".meowy/agent.txt")
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { return nil }
        return text
    }

    private func isExactProcess(_ name: String) -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        task.arguments = ["-x", name]
        task.standardOutput = Pipe()
        task.standardError = Pipe()
        do { try task.run() } catch { return false }
        task.waitUntilExit()
        return task.terminationStatus == 0
    }

    private func detectedAgentName() -> String? {
        if isExactProcess("claude") { return "Claude Code" }
        if isExactProcess("cursor-agent") || isExactProcess("agent") || isExactProcess("Cursor") { return "Cursor" }
        return nil
    }

    private func codexSessionFiles() -> [URL] {
        let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/sessions")
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else { return [] }
        var result: [URL] = []
        while let url = enumerator.nextObject() as? URL {
            if url.pathExtension == "jsonl" { result.append(url) }
        }
        return result
    }

    private func latestCodexSessionFile() -> URL? {
        let files = codexSessionFiles()
        var newest: URL?
        var newestDate: Date = .distantPast
        for url in files {
            if let values = try? url.resourceValues(forKeys: [.contentModificationDateKey]),
               let date = values.contentModificationDate, date > newestDate {
                newestDate = date
                newest = url
            }
        }
        return newest
    }

    private func codexFriendlyToolName(_ name: String) -> String {
        let lower = name.lowercased()
        if lower.contains("apply_patch") || lower.contains("write") || lower.contains("edit") {
            return "Edit"
        }
        if lower.contains("search") || lower == "rg" || lower.contains("grep") || lower.contains("glob") {
            return "Search"
        }
        if lower == "exec" || lower.hasPrefix("exec_") || lower.contains("shell") || lower.contains("bash") || lower.contains("zsh") {
            return "Bash"
        }
        if lower == "read" || lower.hasPrefix("read_") || lower.contains("read_file") || lower.contains("read_resource") {
            return "Read"
        }
        if lower == "write" || lower.hasPrefix("write_") || lower.contains("apply_patch") || lower.contains("edit") {
            return "Edit"
        }

        // Codex tool names are often snake_case. Keep unknown names readable in the bubble.
        return name
            .replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    private func codexActivityToolName(_ name: String, input: String?) -> String {
        let lowerName = name.lowercased()
        guard lowerName == "exec" || lowerName.hasPrefix("exec_") else {
            return codexFriendlyToolName(name)
        }

        let lowerInput = (input ?? "").lowercased()
        if lowerInput.contains("apply_patch") || lowerInput.contains("write_file") ||
            lowerInput.contains("filemanager.default.createfile") || lowerInput.contains(" >") {
            return "Edit"
        }
        if lowerInput.contains("rg ") || lowerInput.contains("grep ") ||
            lowerInput.contains("find ") || lowerInput.contains("glob") {
            return "Search"
        }
        if lowerInput.contains("sed ") || lowerInput.contains("cat ") ||
            lowerInput.contains("head ") || lowerInput.contains("tail ") ||
            lowerInput.contains("ls ") || lowerInput.contains("read_file") {
            return "Read"
        }
        if lowerInput.contains(" test") || lowerInput.contains("build.sh") ||
            lowerInput.contains("npm run") || lowerInput.contains("swiftc ") {
            return "Test"
        }
        if lowerInput.contains("git diff") || lowerInput.contains("git status") ||
            lowerInput.contains("git log") {
            return "Git"
        }
        return "Bash"
    }

    private func codexActivity() -> (busy: Bool, activity: String?) {
        guard let url = latestCodexSessionFile(),
              let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else { return (false, nil) }
        // Codex stores one JSON object per *actual* newline. Splitting on "\\n"
        // would leave the entire session as one invalid JSON object, which made every
        // active Codex process appear as merely "running".
        let lines = text.split(separator: "\n").suffix(300)
        var lastStarted = -1
        var lastComplete = -1
        var activity: String?

        for (index, line) in lines.enumerated() {
            guard let obj = try? JSONSerialization.jsonObject(with: Data(String(line).utf8)) as? [String: Any] else { continue }
            let type = obj["type"] as? String
            let payload = obj["payload"] as? [String: Any]
            if type == "event_msg" {
                switch payload?["type"] as? String {
                case "task_started":
                    lastStarted = index
                    activity = "Thinking"
                case "task_complete":
                    lastComplete = index
                case "patch_apply_begin", "patch_apply_end":
                    if index > lastStarted, lastStarted > lastComplete {
                        activity = "Using Edit"
                    }
                default:
                    break
                }
            } else if type == "response_item" {
                guard index > lastStarted, lastStarted > lastComplete else { continue }
                switch payload?["type"] as? String {
                case "function_call", "custom_tool_call":
                    if let name = payload?["name"] as? String {
                        activity = "Using " + codexActivityToolName(name, input: payload?["input"] as? String)
                    }
                case "reasoning":
                    activity = "Thinking"
                default:
                    break
                }
            }
        }

        guard lastStarted > lastComplete else { return (false, nil) }
        return (true, activity ?? "Thinking")
    }

    private func isCursorProcessRunning() -> Bool {
        isExactProcess("Cursor") || isExactProcess("cursor-agent") || isExactProcess("agent")
    }

    private func latestCursorTranscriptDate() -> Date? {
        let root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cursor/projects")
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        var newest = Date.distantPast
        while let url = enumerator.nextObject() as? URL {
            guard ["jsonl", "txt"].contains(url.pathExtension.lowercased()),
                  url.path.contains("/agent-transcripts/") else { continue }
            if let values = try? url.resourceValues(forKeys: [.contentModificationDateKey]),
               let date = values.contentModificationDate, date > newest {
                newest = date
            }
        }
        return newest == .distantPast ? nil : newest
    }

    private func cursorActivity() -> (busy: Bool, activity: String?) {
        // Cursor's terminal agent does not publish local session state, but its process
        // exists only while it is handling a request.
        if isExactProcess("cursor-agent") || isExactProcess("agent") {
            return (true, "Thinking")
        }
        // Cursor IDE writes its agent transcripts while a turn is in progress. Using
        // the transcript timestamp avoids reporting an idle editor as an active agent.
        guard isExactProcess("Cursor"),
              let updatedAt = latestCursorTranscriptDate(),
              Date().timeIntervalSince(updatedAt) < 8 else { return (false, nil) }
        return (true, "Working")
    }


    private func pollAgentStatus() {
        guard isRunning, agentsEnabled else { return }
        var statuses: [String] = []

        // Claude sessions
        var claudeBusy = false
        let sessions = detectedClaudeSessions()
        if !sessions.isEmpty {
            for session in sessions {
                if session.status == "busy" {
                    claudeBusy = true
                    let activity = latestClaudeActivity(for: session.sessionId)
                    statuses.append(activity.map { "Claude: " + $0 } ?? "Claude: working")
                }
            }
            if !claudeBusy {
                // Completion once
                if lastClaudeStatus == "busy" && !(claudeCompletionUntil.map { $0 > Date() } ?? false) {
                    claudeCompletionUntil = Date().addingTimeInterval(7)
                    let url = URL(fileURLWithPath: "/System/Library/Sounds/Blow.aiff")
                    NSSound(contentsOf: url, byReference: true)?.play()
                }
                if claudeCompletionUntil.map({ $0 > Date() }) ?? false {
                    statuses.append("Claude: work complete")
                }
            }
            lastClaudeStatus = claudeBusy ? "busy" : "idle"
        }

        // Codex sessions
        var codexBusy = false
        if isExactProcess("codex") {
            let info = codexActivity()
            if info.busy {
                codexBusy = true
                statuses.append("Codex: " + (info.activity ?? "working"))
            } else {
                if lastCodexStatus == "busy" && !(codexCompletionUntil.map { $0 > Date() } ?? false) {
                    codexCompletionUntil = Date().addingTimeInterval(7)
                    let url = URL(fileURLWithPath: "/System/Library/Sounds/Blow.aiff")
                    NSSound(contentsOf: url, byReference: true)?.play()
                }
                if codexCompletionUntil.map({ $0 > Date() }) ?? false {
                    statuses.append("Codex: work complete")
                }
            }
            lastCodexStatus = codexBusy ? "busy" : "idle"
        } else {
            lastCodexStatus = nil
        }

        // Cursor IDE and Cursor Agent CLI sessions
        if isCursorProcessRunning() {
            let info = cursorActivity()
            if info.busy {
                statuses.append("Cursor: " + (info.activity ?? "working"))
            } else {
                if lastCursorStatus == "busy" && !(cursorCompletionUntil.map { $0 > Date() } ?? false) {
                    cursorCompletionUntil = Date().addingTimeInterval(7)
                    let url = URL(fileURLWithPath: "/System/Library/Sounds/Blow.aiff")
                    NSSound(contentsOf: url, byReference: true)?.play()
                }
                if cursorCompletionUntil.map({ $0 > Date() }) ?? false {
                    statuses.append("Cursor: work complete")
                }
            }
            lastCursorStatus = info.busy ? "busy" : "idle"
        } else {
            if lastCursorStatus == "busy" && !(cursorCompletionUntil.map { $0 > Date() } ?? false) {
                cursorCompletionUntil = Date().addingTimeInterval(7)
                let url = URL(fileURLWithPath: "/System/Library/Sounds/Blow.aiff")
                NSSound(contentsOf: url, byReference: true)?.play()
            }
            if cursorCompletionUntil.map({ $0 > Date() }) ?? false {
                statuses.append("Cursor: work complete")
                lastCursorStatus = "idle"
            } else {
                lastCursorStatus = nil
            }
        }

        // Agent message file
        if let fileText = agentMessageFile() { statuses.append(fileText) }

        // Generic fallback
        if statuses.isEmpty, let name = detectedAgentName(),
           name != "Claude Code", name != "Cursor" {
            statuses.append("\(name) running")
        }

        if let until = reminderShowingUntil, Date() < until {
            if !reminderDisplayText.isEmpty && !statuses.contains(reminderDisplayText) {
                statuses.append(reminderDisplayText)
            }
        } else {
            reminderShowingUntil = nil
        }

        if statuses.isEmpty {
            isAgentActive = false
            agentStackPanel?.orderOut(nil)
            agentStackPanel = nil
        } else {
            isAgentActive = true
            showAgentStack(statuses)
        }
    }

    private func showAgentBubble(_ text: String) {
        let panel = ensureJokePanel()
        guard let label = jokeLabel, let container = jokeBubbleView else { return }
        label.stringValue = text
        label.font = messageFont
        label.alignment = .center
        label.preferredMaxLayoutWidth = messageTextWidth
        label.usesSingleLineMode = false
        let fit = label.fittingSize
        let bubbleWidth = min(max(fit.width + messageHorizontalPadding * 2, messageMinWidth), messageMaxWidth)
        let bubbleHeight = max(fit.height + messageVerticalPadding * 2, 34)
        container.frame = CGRect(x: 0, y: 0, width: bubbleWidth, height: bubbleHeight)
        label.frame = CGRect(x: messageHorizontalPadding, y: (bubbleHeight - fit.height) / 2,
                             width: bubbleWidth - messageHorizontalPadding * 2, height: fit.height)
        panel.setFrame(CGRect(x: 0, y: 0, width: bubbleWidth, height: bubbleHeight), display: true)
        updateJokeBubblePosition()
        panel.orderFrontRegardless()
    }



    private func isProcessAlive(_ pid: Int) -> Bool {
        Darwin.kill(Int32(pid), 0) == 0
    }

    private func detectedClaudeSessions() -> [(sessionId: String, pid: Int, status: String, updatedAt: Double)] {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/sessions")
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return [] }
        var result: [(sessionId: String, pid: Int, status: String, updatedAt: Double)] = []
        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let pid = json["pid"] as? Int,
                  isProcessAlive(pid),
                  let sessionId = json["sessionId"] as? String else { continue }
            let status = (json["status"] as? String) ?? "idle"
            let updatedAt = (json["updatedAt"] as? Double) ?? (json["startedAt"] as? Double) ?? 0
            result.append((sessionId, pid, status, updatedAt))
        }
        return result
    }

    private func latestClaudeTaskSummary(for sessionId: String) -> String? {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/tasks").appendingPathComponent(sessionId)
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey]) else { return nil }
        var candidates: [ (Date, String) ] = []
        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            let status = (json["status"] as? String) ?? ""
            guard status == "in_progress" else { continue }
            let subject = (json["activeForm"] as? String) ?? (json["subject"] as? String) ?? ""
            guard !subject.isEmpty else { continue }
            let date = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            // Prefer in-progress, but keep all.
            let rankDate = status == "in_progress" ? date.addingTimeInterval(1_000_000) : date
            candidates.append((rankDate, subject))
        }
        return candidates.sorted(by: { $0.0 > $1.0 }).first?.1
    }



    private func findClaudeSessionFile(_ sessionId: String) -> URL? {
        let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects")
        if let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) {
            while let url = enumerator.nextObject() as? URL {
                if url.lastPathComponent == "\(sessionId).jsonl" { return url }
            }
        }
        return nil
    }

    private func latestClaudeActivity(for sessionId: String) -> String? {
        guard let url = findClaudeSessionFile(sessionId) else { return nil }
        // Read tail efficiently
        guard let data = try? Data(contentsOf: url) else { return nil }
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        let lines = text.split(separator: "\n").suffix(80)
        for line in lines.reversed() {
            guard let obj = try? JSONSerialization.jsonObject(with: Data(String(line).utf8)) as? [String: Any],
                  let message = obj["message"] as? [String: Any],
                  let role = message["role"] as? String else { continue }
            if role == "user" {
                // Ignore tool results and internal/system messages; a real prompt means Claude is thinking.
                if let content = message["content"] as? [[String: Any]],
                   content.contains(where: { ($0["type"] as? String) == "tool_result" }) {
                    continue
                }
                var isPrompt = false
                if let content = message["content"] as? String {
                    let cleaned = content.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !cleaned.isEmpty && !cleaned.contains("<system-reminder>") { isPrompt = true }
                } else if let content = message["content"] as? [[String: Any]] {
                    isPrompt = content.contains(where: { ($0["type"] as? String) == "text" })
                }
                if isPrompt { return "Thinking" }
                continue
            }
            guard role == "assistant" else { continue }
            // tool use
            if let content = message["content"] as? [[String: Any]] {
                for item in content {
                    if (item["type"] as? String) == "tool_use", let name = item["name"] as? String {
                        return "Using " + name
                    }
                    if (item["type"] as? String) == "text", let t = item["text"] as? String {
                        let cleaned = t.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\n", with: " ")
                        if !cleaned.isEmpty { return String(cleaned.prefix(90)) }
                    }
                }
            }
            if let content = message["content"] as? String {
                let cleaned = content.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\n", with: " ")
                if !cleaned.isEmpty { return String(cleaned.prefix(90)) }
            }
        }
        return nil
    }

    private func latestClaudeTask() -> String? {
        let root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects")
        guard FileManager.default.fileExists(atPath: root.path) else { return nil }
        var newestURL: URL?
        var newestDate: Date = .distantPast
        if let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]) {
            while let url = enumerator.nextObject() as? URL {
                guard url.pathExtension == "jsonl" else { continue }
                if let vals = try? url.resourceValues(forKeys: [.contentModificationDateKey]),
                   let date = vals.contentModificationDate, date > newestDate {
                    newestDate = date
                    newestURL = url
                }
            }
        }
        guard let url = newestURL,
              let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let lines = text.split(separator: "\n").suffix(200)
        for line in lines.reversed() {
            guard let data = String(line).data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let message = json["message"] as? [String: Any],
                  (message["role"] as? String) == "user" else { continue }
            var candidate: String?
            if let content = message["content"] as? String {
                candidate = content
            } else if let content = message["content"] as? [[String: Any]] {
                for item in content {
                    if (item["type"] as? String) == "text", let t = item["text"] as? String {
                        candidate = t
                        break
                    }
                }
            }
            if let candidate {
                let cleaned = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !cleaned.isEmpty else { continue }
                // Skip tool results / large dumps.
                if cleaned.count > 400 { continue }
                let singleLine = cleaned.replacingOccurrences(of: "\n", with: " ")
                return String(singleLine.prefix(100))
            }
        }
        return nil
    }


    private func showAgentStack(_ texts: [String]) {
        let panel = ensureAgentStackPanel()
        guard let stack = agentStack else { return }
        for v in stack.arrangedSubviews { stack.removeArrangedSubview(v); v.removeFromSuperview() }
        var maxWidth: CGFloat = 120
        var totalHeight: CGFloat = 8
        let isReminder = (reminderShowingUntil.map { $0 > Date() } ?? false)
        if let layer = panel.contentView?.layer {
            layer.backgroundColor = isReminder ? NSColor.systemRed.withAlphaComponent(0.94).cgColor : NSColor.windowBackgroundColor.withAlphaComponent(0.94).cgColor
            layer.cornerRadius = messageCornerRadius
            layer.masksToBounds = true
            layer.borderWidth = messageBorderWidth
            layer.borderColor = isReminder ? NSColor.systemRed.cgColor : NSColor.separatorColor.cgColor
        }
        for text in texts {
            let label = NSTextField(wrappingLabelWithString: text)
            if isReminder && text == reminderDisplayText {
                label.font = messageFont
                label.textColor = .white
                label.alignment = .center
            } else {
                label.alignment = .center
                label.font = messageFont
                if text.contains("work complete") {
                    label.textColor = .systemGreen
                } else {
                    label.textColor = .labelColor
                }
                label.alignment = .center
            }
            label.preferredMaxLayoutWidth = messageTextWidth
            let fit = label.fittingSize
            maxWidth = max(maxWidth, fit.width)
            totalHeight += fit.height + 4
            label.frame.size = fit
            stack.addArrangedSubview(label)
        }
        let bubbleWidth = min(max(maxWidth + messageHorizontalPadding * 2, messageMinWidth), messageMaxWidth)
        panel.setFrame(CGRect(x: 0, y: 0, width: bubbleWidth, height: max(totalHeight + messageVerticalPadding, 24)), display: true)
        updateAgentStackPosition()
        panel.orderFrontRegardless()
    }

    private func ensureAgentStackPanel() -> NSPanel {
        if let panel = agentStackPanel { return panel }
        let panel = CatPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 2)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 4
        stack.wantsLayer = true
        stack.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.94).cgColor
        stack.layer?.cornerRadius = messageCornerRadius
        stack.layer?.masksToBounds = true
        stack.layer?.borderWidth = messageBorderWidth
        stack.layer?.borderColor = NSColor.separatorColor.cgColor
        stack.edgeInsets = NSEdgeInsets(top: messageVerticalPadding,
                                      left: messageHorizontalPadding,
                                      bottom: messageVerticalPadding,
                                      right: messageHorizontalPadding)
        panel.contentView = stack
        agentStackPanel = panel
        agentStack = stack
        return panel
    }

    private func updateAgentStackPosition() {
        guard let panel = agentStackPanel, panel.isVisible else { return }
        let center = simulation.state.position
        let catSize = baseCatSize * catScale
        let size = panel.frame.size
        let screen = DesktopGeometry.nearestScreen(to: center, screens: screens)
        var x = center.x - size.width / 2
        x = min(max(x, screen.minX + 8), screen.maxX - size.width - 8)
        var y = center.y + catSize / 2 + 8
        let showingAbove = y + size.height <= screen.maxY - 8
        if !showingAbove { y = center.y - catSize / 2 - size.height - 8 }
        var pomodoroOffset: CGFloat = 0
        if showingAbove && pomodoroPanel?.isVisible == true { pomodoroOffset = (pomodoroPanel?.frame.height ?? 18) + 8 }
        y += sin(agentFloatPhase) * 6 + pomodoroOffset
        panel.setFrameOrigin(CGPoint(x: x, y: y))
    }

    private func agentBubbleHideIfPossible() {
        jokePanel?.orderOut(nil)
        agentStackPanel?.orderOut(nil)
    }


    func setCatName(_ name: String) {
        catName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        defaults.set(catName, forKey: catNameKey)
        updateNamePanel()
    }

    private func ensureNamePanel() -> NSPanel {
        if let panel = namePanel { return panel }
        let panel = CatPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 2)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        let label = NSTextField(labelWithString: "")
        label.font = NSFont.systemFont(ofSize: 11, weight: .bold)
        label.textColor = .labelColor
        label.alignment = .center
        label.wantsLayer = true
        label.layer?.backgroundColor = NSColor.clear.cgColor
        label.layer?.cornerRadius = 0
        panel.contentView = label
        namePanel = panel
        nameLabel = label
        return panel
    }

    private func updateNameHoverState() {
        let mouse = NSEvent.mouseLocation
        let catFrame = panel.frame
        isNameHovering = catFrame.contains(mouse)
    }

    private func updateNamePanel() {
        updateNameHoverState()
        guard isNameHovering, !catName.isEmpty else { namePanel?.orderOut(nil); return }
        let panel = ensureNamePanel()
        guard let label = nameLabel else { return }
        label.stringValue = catName
        label.sizeToFit()
        let w = label.frame.width + messageHorizontalPadding * 2
        let h = label.frame.height + messageVerticalPadding * 2
        label.frame = NSRect(x: messageHorizontalPadding, y: messageVerticalPadding,
                             width: label.frame.width, height: label.frame.height)
        panel.setFrame(NSRect(x: 0, y: 0, width: w, height: h), display: true)
        updateNamePanelPosition()
        panel.orderFrontRegardless()
    }

    private func updateNamePanelPosition() {
        guard let panel = namePanel, panel.isVisible else { return }
        let center = simulation.state.position
        let catSize = baseCatSize * catScale
        let size = panel.frame.size
        var x = center.x - size.width / 2
        let screen = DesktopGeometry.nearestScreen(to: center, screens: screens)
        x = min(max(x, screen.minX + 4), screen.maxX - size.width - 4)
        let y = center.y + catSize / 2 + 6
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }


    func setReminder(minutes: Double, message: String) {
        guard minutes > 0 else { return }
        setReminder(due: Date().addingTimeInterval(minutes * 60), message: message)
    }

    func setReminder(due: Date, message: String) {
        reminderDue = due
        reminderMessage = message.isEmpty ? "Reminder" : message
        startReminderTimer()
    }

    private func startReminderTimer() {
        reminderTimer?.invalidate()
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            DispatchQueue.main.async { [weak self] in self?.checkReminderDue() }
        }
        RunLoop.main.add(timer, forMode: .common)
        reminderTimer = timer
    }

    func setPomodoro(minutes: Double) {
        guard minutes > 0 else { return }
        pomodoroEnd = Date().addingTimeInterval(minutes * 60)
        pomodoroCompletedUntil = nil
        updatePomodoroPanel()
        startPomodoroTimer()
    }

    private func ensurePomodoroPanel() -> NSPanel {
        if let panel = pomodoroPanel { return panel }
        let panel = CatPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.94).cgColor
        container.layer?.cornerRadius = messageCornerRadius
        container.layer?.masksToBounds = true
        container.layer?.borderWidth = messageBorderWidth
        container.layer?.borderColor = NSColor.separatorColor.cgColor

        let label = NSTextField(labelWithString: "")
        label.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        label.textColor = .labelColor
        label.alignment = .center
        container.addSubview(label)

        panel.contentView = container
        pomodoroPanel = panel
        // store container? We need for frame updates; use contentView.
        pomodoroLabel = label
        return panel
    }

    func updatePomodoroPanel() {
        // Completion state: show a green "00" for 7 seconds.
        if let until = pomodoroCompletedUntil {
            if Date() >= until {
                pomodoroCompletedUntil = nil
                pomodoroBlinkTimer?.invalidate()
                pomodoroBlinkTimer = nil
                pomodoroTimer?.invalidate()
                pomodoroTimer = nil
                pomodoroPanel?.alphaValue = 1.0
                pomodoroPanel?.orderOut(nil)
                return
            }
            let panel = ensurePomodoroPanel()
            guard let label = pomodoroLabel, let container = label.superview else { return }
            container.layer?.backgroundColor = NSColor.systemGreen.withAlphaComponent(0.94).cgColor
            label.textColor = .white
            label.stringValue = "Time\'s up 00:00"
            label.sizeToFit()
            let w = label.frame.width
            let h = label.frame.height
            container.frame = CGRect(x: 0, y: 0, width: w + 36, height: h + 24)
            label.frame = NSRect(x: 18, y: 12, width: w, height: h)
            panel.setFrame(CGRect(x: 0, y: 0, width: w + 36, height: h + 24), display: true)
            updatePomodoroPosition()
            panel.orderFrontRegardless()
            if pomodoroBlinkTimer == nil { startPomodoroBlinkTimer() }
            return
        }

        guard let end = pomodoroEnd else {
            pomodoroTimer?.invalidate()
            pomodoroTimer = nil
            pomodoroPanel?.orderOut(nil)
            return
        }
        let remaining = end.timeIntervalSinceNow
        if remaining <= 0 {
            NSSound(contentsOf: URL(fileURLWithPath: "/System/Library/Sounds/Blow.aiff"), byReference: true)?.play()
            pomodoroEnd = nil
            pomodoroCompletedUntil = Date().addingTimeInterval(7)
            updatePomodoroPanel()
            return
        }
        let panel = ensurePomodoroPanel()
        guard let label = pomodoroLabel, let container = label.superview else { return }
        container.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.94).cgColor
        label.textColor = .labelColor
        label.stringValue = formatPomodoroTime(remaining)
        label.sizeToFit()
        let w = label.frame.width
        let h = label.frame.height
        container.frame = CGRect(x: 0, y: 0, width: w + 36, height: h + 24)
        label.frame = NSRect(x: 18, y: 12, width: w, height: h)
        panel.setFrame(CGRect(x: 0, y: 0, width: w + 36, height: h + 24), display: true)
        updatePomodoroPosition()
        panel.orderFrontRegardless()
    }

    private func startPomodoroBlinkTimer() {
        pomodoroBlinkTimer?.invalidate()
        let timer = Timer(timeInterval: 0.4, repeats: true) { [weak self] _ in
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if let until = self.pomodoroCompletedUntil, Date() >= until { return }
                guard let panel = self.pomodoroPanel, panel.isVisible else { return }
                panel.alphaValue = panel.alphaValue > 0.5 ? 0.25 : 1.0
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        pomodoroBlinkTimer = timer
    }

    private func startPomodoroTimer() {
        pomodoroTimer?.invalidate()
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            DispatchQueue.main.async { [weak self] in self?.pomodoroFloatPhase += 0.18; self?.updatePomodoroPanel() }
        }
        timer.tolerance = 0.05
        RunLoop.main.add(timer, forMode: .common)
        pomodoroTimer = timer
    }

    private func formatPomodoroTime(_ t: TimeInterval) -> String {
        let total = Int(t.rounded(.up))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        if m > 0 { return String(format: "%d:%02d", m, s) }
        return String(format: "00:%02d", s)
    }

    private func updatePomodoroPosition() {
        guard let panel = pomodoroPanel, panel.isVisible else { return }
        let center = simulation.state.position
        let catSize = baseCatSize * catScale
        let size = panel.frame.size
        let screen = DesktopGeometry.nearestScreen(to: center, screens: screens)
        var x = center.x - size.width / 2
        x = min(max(x, screen.minX + 4), screen.maxX - size.width - 4)
        let floatOffset = sin(pomodoroFloatPhase) * 6
        let y = center.y + catSize / 2 + 2 + floatOffset
        panel.setFrameOrigin(CGPoint(x: x, y: y))
    }


    private func checkReminderDue() {
        guard let due = reminderDue, Date() >= due else { return }
        reminderDue = nil
        let message = reminderMessage.isEmpty ? "Reminder" : reminderMessage
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        reminderDisplayText = formatter.string(from: Date()) + " " + message
        reminderShowingUntil = Date().addingTimeInterval(12)
        showAgentStack([reminderDisplayText])
        NSSound(contentsOf: URL(fileURLWithPath: "/System/Library/Sounds/Blow.aiff"), byReference: true)?.play()
        startReminderBlinkTimer()
    }

    private func startReminderBlinkTimer() {
        reminderBlinkTimer?.invalidate()
        let timer = Timer(timeInterval: 0.4, repeats: true) { [weak self] _ in
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if let until = self.reminderShowingUntil, Date() >= until {
                    self.reminderBlinkTimer?.invalidate()
                    self.reminderBlinkTimer = nil
                    self.agentStackPanel?.alphaValue = 1.0
                    return
                }
                guard let panel = self.agentStackPanel, panel.isVisible else { return }
                panel.alphaValue = panel.alphaValue > 0.5 ? 0.25 : 1.0
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        reminderBlinkTimer = timer
    }

    func shutDown() {
        stop()
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    @objc private func updateActivity() {
        timer?.invalidate()
        timer = nil
        guard isRunning && !isSuspended else {
            panel.orderOut(nil)
            return
        }
        drawCat()
        panel.orderFrontRegardless()
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            spriteView.image = sprites.frame(.idle, index: 0)
            return
        }
        // Poll the global pointer; no input hooks, Accessibility, or recording permission needed.
        let timer = Timer(timeInterval: 0.1, target: self, selector: #selector(tick),
                          userInfo: nil, repeats: true)
        timer.tolerance = 0.005
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    @objc private func tick() {
        if isJokePaused {
            agentFloatPhase += 0.18
            updateAgentStackPosition()
            if !isJokeBursting {
                jokeFloatPhase += 0.18
                updateJokeBubblePosition()
            }
            updateNamePanel()
            checkReminderDue()
            updatePomodoroPanel()
            pomodoroFloatPhase += 0.18
            updatePomodoroPosition()
            drawCat()
            return
        }
        let speedMultiplier = speedPercent / 100
        if mode == .dock {
            simulation.stepOnDock(in: dockBounds, speed: 8 * speedMultiplier)
        } else {
            simulation.step(
                toward: NSEvent.mouseLocation,
                screens: screens,
                inset: baseCatSize * catScale / 2,
                speed: 10 * speedMultiplier,
            )
        }
        agentFloatPhase += 0.18
        updateAgentStackPosition()
        updateJokeBubblePosition()
        updateNamePanel()
        checkReminderDue()
        updatePomodoroPanel()
        pomodoroFloatPhase += 0.18
        updatePomodoroPosition()
        drawCat()
    }

    private func drawCat() {
        let state = simulation.state
        spriteView.image = sprites.frame(state.displayedAnimation, index: state.displayedFrame)
        panel.setFrameOrigin(CGPoint(x: state.position.x - baseCatSize * catScale / 2,
                                     y: state.position.y - baseCatSize * catScale / 2))
    }

    func startJokeSchedule() {
        stopJokeSchedule()
        guard isRunning, mode == .dock, jokesEnabled else { return }
        let fetchTimer = Timer(timeInterval: 300, repeats: true) { [weak self] _ in
            DispatchQueue.main.async { [weak self] in self?.fetchJoke() }
        }
        fetchTimer.tolerance = 10
        RunLoop.main.add(fetchTimer, forMode: .common)
        jokeFetchTimer = fetchTimer
        jokeFetchTimer?.tolerance = 10
        // Kick off one shortly so the feature is visible; then every 5 minutes.
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
            self?.fetchJoke()
        }
    }

    func stopJokeSchedule() {
        jokeFetchTimer?.invalidate()
        jokeFetchTimer = nil
    }

    private func fetchJoke() {
        guard isRunning, mode == .dock, jokesEnabled else { return }
        let source = jokeSource
        var request: URLRequest
        switch source {
        case .dark:
            request = URLRequest(url: URL(string: "https://v2.jokeapi.dev/joke/Dark?type=single")!)
        case .dad:
            var r = URLRequest(url: URL(string: "https://icanhazdadjoke.com/")!)
            r.setValue("application/json", forHTTPHeaderField: "Accept")
            request = r
        case .advice:
            request = URLRequest(url: URL(string: "https://api.adviceslip.com/advice")!)
        case .quote:
            request = URLRequest(url: URL(string: "https://zenquotes.io/api/random")!)
        }
        request.timeoutInterval = 12
        let task = URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
            var text = "Why did the cat sit on the computer?\nTo keep an eye on the mouse."
            if let data,
               let json = try? JSONSerialization.jsonObject(with: data) {
                switch source {
                case .dark:
                    if let dict = json as? [String: Any] {
                        if let joke = dict["joke"] as? String { text = joke }
                        else if let setup = dict["setup"] as? String, let delivery = dict["delivery"] as? String { text = setup + "\n" + delivery }
                    }
                case .dad:
                    if let dict = json as? [String: Any], let joke = dict["joke"] as? String { text = joke }
                case .advice:
                    if let dict = json as? [String: Any], let slip = dict["slip"] as? [String: Any], let advice = slip["advice"] as? String { text = advice }
                case .quote:
                    if let arr = json as? [[String: Any]], let first = arr.first,
                       let quote = first["q"] as? String {
                        text = quote
                        if let author = first["a"] as? String { text += "\n— " + author }
                    }
                }
            }
            DispatchQueue.main.async { self?.presentJoke(text) }
        }
        task.resume()
    }

    private func presentJoke(_ text: String) {
        guard isRunning, mode == .dock, !isAgentActive else { return }
        isJokePaused = true
        isJokeBursting = false
        jokeFloatPhase = 0
        simulation.pauseForJoke()
        showJokeBubble(text)
        jokeHideTimer?.invalidate()
        let hideTimer = Timer(timeInterval: 30, repeats: false) { [weak self] _ in
            DispatchQueue.main.async { [weak self] in self?.hideJokeBubble() }
        }
        RunLoop.main.add(hideTimer, forMode: .common)
        jokeHideTimer = hideTimer
    }

    private func hideJokeBubble() {
        jokeHideTimer?.invalidate()
        jokeHideTimer = nil
        guard let panel = jokePanel, panel.isVisible else {
            isJokePaused = false
            isJokeBursting = false
            return
        }
        isJokeBursting = true
        let originFrame = panel.frame
        let burstFrame = originFrame.insetBy(dx: -18, dy: -12)
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.35
            context.allowsImplicitAnimation = true
            panel.animator().alphaValue = 0
            panel.animator().setFrame(burstFrame, display: true)
        }, completionHandler: { [weak self] in
            DispatchQueue.main.async { [weak self] in
                panel.orderOut(nil)
                panel.alphaValue = 1
                self?.isJokeBursting = false
                self?.isJokePaused = false
                self?.jokeFloatPhase = 0
            }
        })
    }

    private func ensureJokePanel() -> NSPanel {
        if let panel = jokePanel { return panel }
        let panel = CatPanel(contentRect: .zero,
                             styleMask: [.borderless, .nonactivatingPanel],
                             backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 2)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false

        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.94).cgColor
        container.layer?.cornerRadius = messageCornerRadius
        container.layer?.masksToBounds = true
        container.layer?.borderWidth = messageBorderWidth
        container.layer?.borderColor = NSColor.separatorColor.cgColor

        let label = NSTextField(wrappingLabelWithString: "")
        label.font = messageFont
        label.textColor = .labelColor
        label.alignment = .center
        label.maximumNumberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        container.addSubview(label)

        panel.contentView = container
        jokePanel = panel
        jokeBubbleView = container
        jokeLabel = label
        return panel
    }

    private func showJokeBubble(_ text: String) {
        let panel = ensureJokePanel()
        guard let label = jokeLabel, let container = jokeBubbleView else { return }
        label.stringValue = text
        label.preferredMaxLayoutWidth = messageTextWidth
        label.usesSingleLineMode = false
        let fit = label.fittingSize

        let bubbleWidth = min(max(fit.width + messageHorizontalPadding * 2, messageMinWidth), messageMaxWidth)
        let bubbleHeight = max(fit.height + messageVerticalPadding * 2, 34)
        container.frame = CGRect(x: 0, y: 0, width: bubbleWidth, height: bubbleHeight)
        label.frame = CGRect(x: messageHorizontalPadding, y: (bubbleHeight - fit.height) / 2,
                             width: bubbleWidth - messageHorizontalPadding * 2, height: fit.height)
        panel.setFrame(CGRect(x: 0, y: 0, width: bubbleWidth, height: bubbleHeight), display: true)
        updateJokeBubblePosition()
        panel.orderFrontRegardless()
    }

    private func updateJokeBubblePosition() {
        guard let panel = jokePanel, panel.isVisible else { return }
        let catSize = baseCatSize * catScale
        let center = simulation.state.position
        let size = panel.frame.size
        let floatOffset = isJokeBursting ? 0 : sin(jokeFloatPhase) * 6
        var pomodoroOffset: CGFloat = 0
        if pomodoroPanel?.isVisible == true { pomodoroOffset = (pomodoroPanel?.frame.height ?? 18) + 8 }
        let screen = DesktopGeometry.nearestScreen(to: center, screens: screens)
        var originX = center.x - size.width / 2
        originX = min(max(originX, screen.minX + 8), screen.maxX - size.width - 8)
        let aboveY = center.y + catSize / 2 + 10 + floatOffset + pomodoroOffset
        let belowY = center.y - catSize / 2 - size.height - 10 + floatOffset
        var originY = aboveY
        if aboveY + size.height > screen.maxY - 8 {
            originY = belowY
        }
        if originY < screen.minY + 8 {
            originY = screen.minY + 8
        }
        if let agentPanel = agentStackPanel, agentPanel.isVisible {
            originY = max(originY, agentPanel.frame.maxY + 8)
            if originY + size.height > screen.maxY - 8 {
                originY = screen.maxY - size.height - 8
            }
        }
        panel.setFrameOrigin(CGPoint(x: originX, y: originY))
    }

    private func constrainPosition() {
        guard !screens.isEmpty else { return }
        if mode == .dock {
            simulation.state.position = DesktopGeometry.constrainToDock(
                simulation.state.position,
                dock: dockBounds,
            )
        } else {
            simulation.state.position = DesktopGeometry.constrain(
                simulation.state.position,
                screens: screens,
                inset: baseCatSize * catScale / 2,
            )
        }
    }

    private func dockItemCount() -> Int {
        var count = 0
        for key in ["persistent-apps", "persistent-others"] {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
            task.arguments = ["read", "com.apple.dock", key]
            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = Pipe()
            do {
                try task.run()
                task.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let text = String(data: data, encoding: .utf8) ?? ""
                count += max(0, text.components(separatedBy: "tile-type").count - 1)
            } catch {
                continue
            }
        }
        return count == 0 ? 0 : count
    }

    private func dockAutoHide() -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        task.arguments = ["read", "com.apple.dock", "autohide"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        do {
            try task.run()
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return text == "1"
        } catch {
            return false
        }
    }

    private func dockTileSize() -> Int {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        task.arguments = ["read", "com.apple.dock", "tilesize"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        do {
            try task.run()
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return Int(text) ?? 48
        } catch {
            return 48
        }
    }

    private func updateDockBounds() {
        guard let screen = NSScreen.screens.first(where: {
            $0.visibleFrame.minY > $0.frame.minY + 1
        }) ?? NSScreen.main ?? NSScreen.screens.first else {
            dockBounds = .zero
            return
        }

        let halfSize = baseCatSize * catScale / 2
        var minX = screen.frame.minX + halfSize
        var maxX = screen.frame.maxX - halfSize
        if !dockAutoHide() {
            let count = dockItemCount()
            let tileCount = count == 0 ? Int(screen.frame.width / CGFloat(dockTileSize() + 4)) : count
            let tileSize = dockTileSize()
            let estimatedDockWidth = CGFloat(tileCount) * CGFloat(tileSize + 4) + 20
            let center = screen.frame.midX
            minX = max(screen.frame.minX + halfSize, center - estimatedDockWidth / 2 + halfSize)
            maxX = min(screen.frame.maxX - halfSize, center + estimatedDockWidth / 2 - halfSize)
        }
        dockBounds = CGRect(
            x: minX,
            y: screen.visibleFrame.minY + halfSize,
            width: max(0, maxX - minX),
            height: 0,
        )
    }

    @objc private func updateScreens() {
        screens = NSScreen.screens.map(\.frame)
        guard !screens.isEmpty else { return }
        if !simulation.state.position.x.isFinite || !simulation.state.position.y.isFinite {
            simulation.state = CatState()
        }
        updateDockBounds()
        constrainPosition()
        drawCat()
        updateNamePanel()
    }

    @objc private func suspend() {
        isSuspended = true
        updateActivity()
        saveState()
    }

    @objc private func resume() {
        isSuspended = false
        updateScreens()
        updateActivity()
    }

    private func saveState() {
        guard let data = try? JSONEncoder().encode(simulation.state) else { return }
        defaults.set(data, forKey: stateKey)
    }
}

@MainActor
private final class CatSizeMenuView: NSView {
    let slider: NSSlider
    private let valueLabel: NSTextField

    init(target: AnyObject, action: Selector, value: Double) {
        slider = NSSlider(value: value, minValue: 0.5, maxValue: 2.5, target: target, action: action)
        valueLabel = NSTextField(labelWithString: "")
        super.init(frame: NSRect(x: 0, y: 0, width: 240, height: 52))

        valueLabel.font = NSFont.menuFont(ofSize: NSFont.smallSystemFontSize)
        valueLabel.frame = NSRect(x: 12, y: 32, width: 216, height: 16)
        updateValue(value)

        slider.isContinuous = true
        slider.frame = NSRect(x: 12, y: 6, width: 216, height: 20)

        addSubview(valueLabel)
        addSubview(slider)
    }

    func updateValue(_ value: Double) {
        valueLabel.stringValue = "Size: \(Int((value * 100).rounded()))%"
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

@MainActor
private final class CatSpeedMenuView: NSView {
    let slider: NSSlider
    private let valueLabel: NSTextField

    init(target: AnyObject, action: Selector, value: Double) {
        slider = NSSlider(
            value: value,
            minValue: Double(minimumSpeedPercent),
            maxValue: Double(maximumSpeedPercent),
            target: target,
            action: action,
        )
        valueLabel = NSTextField(labelWithString: "")
        super.init(frame: NSRect(x: 0, y: 0, width: 240, height: 52))

        valueLabel.font = NSFont.menuFont(ofSize: NSFont.smallSystemFontSize)
        valueLabel.frame = NSRect(x: 12, y: 32, width: 216, height: 16)
        updateValue(value)

        slider.isContinuous = true
        slider.frame = NSRect(x: 12, y: 6, width: 216, height: 20)

        addSubview(valueLabel)
        addSubview(slider)
    }

    func updateValue(_ value: Double) {
        valueLabel.stringValue = "Speed: \(Int(value.rounded()))%"
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

@MainActor
private final class StatusBarController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let meowy: MeowyController
    private let menu = NSMenu()
    private let toggleItem = NSMenuItem(title: "Start Meowy", action: #selector(toggleMeowy), keyEquivalent: "")
    private let cursorItem = NSMenuItem(title: "Follow Cursor", action: #selector(followCursor), keyEquivalent: "")
    private let dockItem = NSMenuItem(title: "Live on Dock", action: #selector(liveOnDock), keyEquivalent: "")
    private let jokesItem = NSMenuItem(title: "Jokes", action: nil, keyEquivalent: "")
    private var jokesSubMenu = NSMenu(title: "Jokes")
    private let jokesEnabledItem = NSMenuItem(title: "Enabled", action: #selector(toggleJokes), keyEquivalent: "")
    private let jokeSourceSubMenu = NSMenu(title: "Joke Source")
    private var jokeSourceMenuItems: [NSMenuItem] = []
    private let agentsItem = NSMenuItem(title: "Agents", action: nil, keyEquivalent: "")
    private let actionItemsItem = NSMenuItem(title: "Action Items", action: nil, keyEquivalent: "")
    private let actionItemsSubMenu = NSMenu(title: "Action Items")
    private let reminderItem = NSMenuItem(title: "Reminder", action: #selector(setReminder), keyEquivalent: "")
    private let pomodoroItem = NSMenuItem(title: "Pomodoro", action: #selector(setPomodoro), keyEquivalent: "")
    private let agentsEnabledItem = NSMenuItem(title: "Enabled", action: #selector(toggleAgents), keyEquivalent: "")
    private var agentsSubMenu = NSMenu(title: "Agents")
    private let catNameItem = NSMenuItem(title: "Cat Name", action: #selector(setCatName), keyEquivalent: "")
    private let quitItem = NSMenuItem(title: "Quit Meowy", action: #selector(quit), keyEquivalent: "q")
    private lazy var sizeMenuView = CatSizeMenuView(
        target: self,
        action: #selector(sizeChanged(_:)),
        value: Double(meowy.scale),
    )
    private lazy var speedMenuView = CatSpeedMenuView(
        target: self,
        action: #selector(speedChanged(_:)),
        value: Double(meowy.speed),
    )

    init(meowy: MeowyController) {
        self.meowy = meowy
        super.init()

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "cat.fill", accessibilityDescription: "Meowy")
                ?? NSImage(systemSymbolName: "pawprint.fill", accessibilityDescription: "Meowy")
            button.image?.isTemplate = true
        }
        statusItem.menu = menu

        toggleItem.target = self
        cursorItem.target = self
        dockItem.target = self
        jokesEnabledItem.target = self
        agentsEnabledItem.target = self
        reminderItem.target = self
        pomodoroItem.target = self

        jokesSubMenu = NSMenu(title: "Jokes")
        jokesSubMenu.addItem(jokesEnabledItem)
        jokesSubMenu.addItem(.separator())
        for (index, source) in JokeSource.allCases.enumerated() {
            let item = NSMenuItem(title: source.title, action: #selector(selectJokeSource(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
            jokeSourceMenuItems.append(item)
            jokesSubMenu.addItem(item)
        }
        jokesItem.submenu = jokesSubMenu

        agentsSubMenu = NSMenu(title: "Agents")
        agentsSubMenu.addItem(agentsEnabledItem)
        agentsSubMenu.addItem(.separator())
        let claudeItem = NSMenuItem(title: "Claude", action: nil, keyEquivalent: "")
        claudeItem.state = .on
        agentsSubMenu.addItem(claudeItem)
        let codexItem = NSMenuItem(title: "Codex", action: nil, keyEquivalent: "")
        codexItem.state = .on
        agentsSubMenu.addItem(codexItem)
        let cursorAgentItem = NSMenuItem(title: "Cursor", action: nil, keyEquivalent: "")
        cursorAgentItem.state = .on
        agentsSubMenu.addItem(cursorAgentItem)
        agentsItem.submenu = agentsSubMenu

        actionItemsSubMenu.addItem(reminderItem)
        actionItemsSubMenu.addItem(pomodoroItem)
        actionItemsItem.submenu = actionItemsSubMenu
        catNameItem.target = self
        quitItem.target = self
        menu.addItem(toggleItem)
        menu.addItem(.separator())
        menu.addItem(cursorItem)
        menu.addItem(dockItem)
        menu.addItem(.separator())
        menu.addItem(jokesItem)
        menu.addItem(agentsItem)
        menu.addItem(actionItemsItem)
        menu.addItem(.separator())
        menu.addItem(catNameItem)
        menu.addItem(.separator())
        let sizeItem = NSMenuItem()
        sizeItem.view = sizeMenuView
        menu.addItem(sizeItem)
        let speedItem = NSMenuItem()
        speedItem.view = speedMenuView
        menu.addItem(speedItem)
        menu.addItem(.separator())
        menu.addItem(quitItem)
        updateMenuState()
    }

    private func updateMenuState() {
        toggleItem.title = meowy.isRunning ? "Stop Meowy" : "Start Meowy"
        cursorItem.state = meowy.mode == .cursor ? .on : .off
        dockItem.state = meowy.mode == .dock ? .on : .off
        jokesEnabledItem.state = meowy.jokesEnabled ? .on : .off
        for (index, item) in jokeSourceMenuItems.enumerated() {
            item.state = JokeSource.allCases[index] == meowy.jokeSource ? .on : .off
            item.isEnabled = meowy.jokesEnabled
        }
        agentsEnabledItem.state = meowy.agentsEnabled ? .on : .off
        for item in agentsSubMenu.items where item != agentsEnabledItem {
            item.isEnabled = meowy.agentsEnabled
        }
        for (index, item) in jokeSourceMenuItems.enumerated() {
            item.state = JokeSource.allCases[index] == meowy.jokeSource ? .on : .off
        }

    }

    @objc private func statusItemPressed() {
        updateMenuState()
        guard let button = statusItem.button, let event = NSApp.currentEvent else { return }
        NSMenu.popUpContextMenu(menu, with: event, for: button)
    }

    @objc private func toggleMeowy() {
        if meowy.isRunning {
            meowy.stop()
        } else {
            meowy.start()
        }
        updateMenuState()
    }

    @objc private func followCursor() {
        meowy.setMode(.cursor)
        updateMenuState()
    }

    @objc private func liveOnDock() {
        meowy.setMode(.dock)
        updateMenuState()
    }
    @objc private func toggleJokes() {
        meowy.setJokesEnabled(!meowy.jokesEnabled)
        updateMenuState()
    }
    @objc private func selectJokeSource(_ sender: NSMenuItem) {
        let sources = JokeSource.allCases
        guard sender.tag >= 0, sender.tag < sources.count else { return }
        meowy.setJokeSource(sources[sender.tag])
        updateMenuState()
    }
    @objc private func toggleAgents() {
        meowy.setAgentsEnabled(!meowy.agentsEnabled)
        updateMenuState()
    }

    @objc private func sizeChanged(_ sender: NSSlider) {
        meowy.setScale(CGFloat(sender.doubleValue))
        sizeMenuView.updateValue(sender.doubleValue)
    }

    @objc private func speedChanged(_ sender: NSSlider) {
        meowy.setSpeedPercent(CGFloat(sender.doubleValue))
        speedMenuView.updateValue(sender.doubleValue)
    }

    @objc private func setCatName() {
        let alert = NSAlert()
        alert.messageText = "Cat name"
        alert.informativeText = "Enter the cat's name."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        field.stringValue = meowy.catName
        alert.accessoryView = field
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            meowy.setCatName(field.stringValue)
        }
    }


    @objc private func setReminder() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Reminder"
        alert.informativeText = "Enter minutes from now, or pick a time."
        let accessory = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 120))
        let minutesField = NSTextField(frame: NSRect(x: 0, y: 94, width: 280, height: 24))
        minutesField.stringValue = ""
        minutesField.placeholderString = "Minutes from now"
        let hourPopup = NSPopUpButton(frame: NSRect(x: 0, y: 62, width: 70, height: 24), pullsDown: false)
        hourPopup.addItems(withTitles: (1...12).map { "\($0)" })
        hourPopup.selectItem(at: 11)
        let minutePopup = NSPopUpButton(frame: NSRect(x: 80, y: 62, width: 70, height: 24), pullsDown: false)
        minutePopup.addItems(withTitles: (0...59).map { String(format: "%02d", $0) })
        minutePopup.selectItem(at: 39)
        let ampmPopup = NSPopUpButton(frame: NSRect(x: 160, y: 62, width: 70, height: 24), pullsDown: false)
        ampmPopup.addItems(withTitles: ["AM", "PM"])
        ampmPopup.selectItem(at: 1)
        let messageField = NSTextField(frame: NSRect(x: 0, y: 8, width: 280, height: 24))
        messageField.stringValue = ""
        messageField.placeholderString = "Message"
        accessory.addSubview(minutesField)
        accessory.addSubview(hourPopup)
        accessory.addSubview(minutePopup)
        accessory.addSubview(ampmPopup)
        accessory.addSubview(messageField)
        alert.accessoryView = accessory
        let observer = NotificationCenter.default.addObserver(forName: NSControl.textDidChangeNotification, object: nil, queue: .main) { _ in
            let minsFilled = !minutesField.stringValue.trimmingCharacters(in: .whitespaces).isEmpty
            hourPopup.isEnabled = !minsFilled
            minutePopup.isEnabled = !minsFilled
            ampmPopup.isEnabled = !minsFilled
            hourPopup.alphaValue = minsFilled ? 0.45 : 1.0
            minutePopup.alphaValue = minsFilled ? 0.45 : 1.0
            ampmPopup.alphaValue = minsFilled ? 0.45 : 1.0
        }
        minutesField.isEnabled = true
        hourPopup.isEnabled = true
        minutePopup.isEnabled = true
        ampmPopup.isEnabled = true
        minutesField.alphaValue = 1.0
        hourPopup.alphaValue = 1.0
        minutePopup.alphaValue = 1.0
        ampmPopup.alphaValue = 1.0
        alert.addButton(withTitle: "Set")
        alert.addButton(withTitle: "Cancel")
        let modalResult = alert.runModal()
        NotificationCenter.default.removeObserver(observer)
        if modalResult == .alertFirstButtonReturn {
            let minsText = minutesField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if minsText.isEmpty {
                var hour = Int(hourPopup.titleOfSelectedItem ?? "12") ?? 12
                if hour == 12 { hour = 0 }
                if (ampmPopup.titleOfSelectedItem ?? "AM") == "PM" { hour += 12 }
                let minute = Int(minutePopup.titleOfSelectedItem ?? "0") ?? 0
                let calendar = Calendar.current
                let now = Date()
                var due = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: now) ?? now
                if due <= now { due = calendar.date(byAdding: .day, value: 1, to: due) ?? due }
                meowy.setReminder(due: due, message: messageField.stringValue)
            } else {
                let mins = Double(minsText) ?? 0
                meowy.setReminder(minutes: mins, message: messageField.stringValue)
            }
        }
    }

    @objc private func setPomodoro() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Pomodoro"
        alert.informativeText = "Hours and minutes"
        let accessory = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 60))
        let hoursField = NSTextField(frame: NSRect(x: 0, y: 34, width: 130, height: 24))
        hoursField.stringValue = "0"
        hoursField.placeholderString = "Hours"
        let minutesField = NSTextField(frame: NSRect(x: 150, y: 34, width: 130, height: 24))
        minutesField.stringValue = "25"
        minutesField.placeholderString = "Minutes"
        accessory.addSubview(hoursField)
        accessory.addSubview(minutesField)
        alert.accessoryView = accessory
        alert.addButton(withTitle: "Start")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            let hours = Double(hoursField.stringValue) ?? 0
            let minutes = Double(minutesField.stringValue) ?? 0
            meowy.setPomodoro(minutes: hours * 60 + minutes)
            meowy.updatePomodoroPanel()
        }
    }

    @objc private func quit() {
        meowy.shutDown()
        NSApplication.shared.terminate(nil)
    }
}

@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate {
    private var meowy: MeowyController?
    private var statusBar: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)

        guard let url = Bundle.main.url(forResource: "Meowy", withExtension: "gif"),
              let sprites = SpriteSheet(url: url) else {
            let alert = NSAlert()
            alert.messageText = "Meowy could not start"
            alert.informativeText = "The bundled Meowy sprite sheet could not be loaded."
            alert.runModal()
            NSApplication.shared.terminate(nil)
            return
        }

        let meowy = MeowyController(sprites: sprites)
        self.meowy = meowy
        self.statusBar = StatusBarController(meowy: meowy)
        meowy.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        meowy?.shutDown()
    }
}

@main
@MainActor
private struct CATApp {
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.run()
    }
}
