import AppKit
import Foundation

struct CommandResult {
    let code: Int32
    let output: String
}

final class PatchManager {
    static let shared = PatchManager()

    let appPath = "/Applications/Dia.app"
    let stateRoot = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/DiaZhPatch", isDirectory: true)
    let logURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/DiaZhHelper.log")

    private var patchDirectory: URL {
        Bundle.main.resourceURL!.appendingPathComponent("Patch", isDirectory: true)
    }

    private var patchCommand: URL {
        patchDirectory.appendingPathComponent("helper-driver.zsh")
    }

    private init() {}

    func runPatch(_ command: String, onOutput: ((String) -> Void)? = nil) -> CommandResult {
        guard FileManager.default.fileExists(atPath: patchCommand.path) else {
            return CommandResult(code: 127, output: "找不到内置补丁：\(patchCommand.path)")
        }
        var environment = ProcessInfo.processInfo.environment
        for key in environment.keys.filter({ $0.hasPrefix("DIA_") }) { environment.removeValue(forKey: key) }
        environment["PATH"] = "/usr/bin:/bin:/usr/sbin:/sbin"
        environment["DIA_ZH_MODE"] = "core"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [patchCommand.path, command]
        process.currentDirectoryURL = patchDirectory
        process.environment = environment
        process.standardInput = FileHandle.nullDevice

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
        } catch {
            return CommandResult(code: 126, output: "无法启动补丁：\(error.localizedDescription)")
        }
        var data = Data()
        while true {
            let chunk = pipe.fileHandleForReading.availableData
            if chunk.isEmpty { break }
            data.append(chunk)
            // Accumulate complete lines so a UTF-8 character split across reads
            // cannot garble progress messages.
            if let text = String(data: data, encoding: .utf8) { onOutput?(text) }
        }
        process.waitUntilExit()
        let output = String(data: data, encoding: .utf8) ?? ""
        if command != "status" { appendLog("\(command) (exit \(process.terminationStatus))\n\(output)") }
        return CommandResult(code: process.terminationStatus, output: output)
    }

    func status() -> CommandResult {
        runPatch("status")
    }

    func install(interactive: Bool, onOutput: ((String) -> Void)? = nil) -> CommandResult {
        let result = runPatch(interactive ? "repair" : "repair-background", onOutput: onOutput)
        if result.code == 0 { UserDefaults.standard.removeObject(forKey: "failedAutomaticVersion") }
        return result
    }

    func restore() -> CommandResult {
        runPatch("restore")
    }

    func isDiaRunning() -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: "company.thebrowser.dia").isEmpty
    }

    func automaticCheck() {
        guard FileManager.default.fileExists(atPath: appPath) else {
            appendLog("未找到 /Applications/Dia.app。")
            return
        }

        let current = status()
        guard current.code == 0 else {
            return
        }
        let state = PatchStatus(current.output)
        if state.isVerified { return }
        guard state.isOfficial, state.fields["覆盖级别"] != "incompatible", !isDiaRunning() else { return }
        // Do not repeat a failed mutation every five minutes on the same build.
        if UserDefaults.standard.string(forKey: "failedAutomaticVersion") == state.version { return }

        appendLog("检测到官方更新，开始安全重装。")
        let result = install(interactive: false)
        if result.code == 0 {
            notify(title: "Dia 中文补丁助手", message: "核心汉化资源已安装并校验，待下次启动 Dia 验证。")
        } else if result.code != 75 {
            UserDefaults.standard.set(state.version, forKey: "failedAutomaticVersion")
            notify(title: "Dia 中文补丁助手", message: "自动修复未完成，请打开助手查看日志并修复。")
        }
    }

    func appendLog(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let line = "[\(formatter.string(from: Date()))] \(message)\n"
        let directory = logURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: logURL.path) {
            FileManager.default.createFile(atPath: logURL.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: logURL) else { return }
        defer { try? handle.close() }
        do {
            try handle.seekToEnd()
            if let data = line.data(using: .utf8) { try handle.write(contentsOf: data) }
        } catch {}
    }

    private func notify(title: String, message: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", "display notification \"\(message)\" with title \"\(title)\""]
        try? process.run()
    }
}

final class LaunchAgentManager {
    static let shared = LaunchAgentManager()
    let label = "io.github.yyxwz.dia-zh-helper.auto"

    var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    var isInstalled: Bool {
        FileManager.default.fileExists(atPath: plistURL.path)
    }

    func install() throws {
        guard let executable = Bundle.main.executablePath else {
            throw NSError(domain: label, code: 1, userInfo: [NSLocalizedDescriptionKey: "找不到应用可执行文件"])
        }
        try FileManager.default.createDirectory(
            at: plistURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let logPath = PatchManager.shared.logURL.path
        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [executable, "--auto-check"],
            "RunAtLoad": true,
            "StartInterval": 300,
            "ProcessType": "Background",
            "StandardOutPath": logPath,
            "StandardErrorPath": logPath
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: plistURL, options: .atomic)
        _ = runLaunchctl(["bootout", "gui/\(getuid())/\(label)"])
        let result = runLaunchctl(["bootstrap", "gui/\(getuid())", plistURL.path])
        guard result.code == 0 else {
            throw NSError(domain: label, code: Int(result.code), userInfo: [NSLocalizedDescriptionKey: result.output])
        }
    }

    func uninstall() throws {
        _ = runLaunchctl(["bootout", "gui/\(getuid())/\(label)"])
        if FileManager.default.fileExists(atPath: plistURL.path) {
            try FileManager.default.removeItem(at: plistURL)
        }
    }

    private func runLaunchctl(_ arguments: [String]) -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do { try process.run() } catch {
            return CommandResult(code: 126, output: error.localizedDescription)
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return CommandResult(
            code: process.terminationStatus,
            output: String(data: data, encoding: .utf8) ?? ""
        )
    }
}

final class MainWindowController: NSWindowController {
    private(set) var isBusy = false
    private let statusTitle = NSTextField(labelWithString: "正在检查 Dia…")
    private let statusDetail = NSTextField(wrappingLabelWithString: "")
    private let logView = NSTextView()
    private let progress = NSProgressIndicator()
    private let autoCheck = NSButton(checkboxWithTitle: "Dia 更新后自动重装（仅在 Dia 已退出时）", target: nil, action: nil)
    private var operationButtons: [NSButton] = []

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 520),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Dia 中文补丁助手"
        window.center()
        window.isReleasedWhenClosed = false
        super.init(window: window)
        buildUI()
        refreshStatus()
    }

    required init?(coder: NSCoder) { nil }

    private func buildUI() {
        guard let content = window?.contentView else { return }

        let icon = NSImageView(image: NSImage(systemSymbolName: "character.book.closed.fill", accessibilityDescription: nil)!)
        icon.contentTintColor = NSColor.systemIndigo
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 42).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 42).isActive = true

        let title = NSTextField(labelWithString: "Dia 中文补丁助手")
        title.font = .systemFont(ofSize: 24, weight: .bold)
        let subtitle = NSTextField(labelWithString: "检测官方更新，安全备份并重新安装简体中文补丁")
        subtitle.textColor = .secondaryLabelColor
        subtitle.font = .systemFont(ofSize: 13)
        let titleStack = NSStackView(views: [title, subtitle])
        titleStack.orientation = .vertical
        titleStack.alignment = .leading
        titleStack.spacing = 3
        let header = NSStackView(views: [icon, titleStack])
        header.orientation = .horizontal
        header.spacing = 14
        header.alignment = .centerY

        let statusBox = NSBox()
        statusBox.boxType = .custom
        statusBox.cornerRadius = 12
        statusBox.borderColor = NSColor.separatorColor
        statusBox.borderWidth = 1
        statusBox.fillColor = NSColor.controlBackgroundColor
        statusTitle.font = .systemFont(ofSize: 16, weight: .semibold)
        statusDetail.font = .systemFont(ofSize: 12)
        statusDetail.textColor = .secondaryLabelColor
        statusDetail.maximumNumberOfLines = 3
        let statusStack = NSStackView(views: [statusTitle, statusDetail])
        statusStack.orientation = .vertical
        statusStack.alignment = .leading
        statusStack.spacing = 6
        statusStack.translatesAutoresizingMaskIntoConstraints = false
        statusBox.contentView?.addSubview(statusStack)
        NSLayoutConstraint.activate([
            statusStack.leadingAnchor.constraint(equalTo: statusBox.contentView!.leadingAnchor, constant: 16),
            statusStack.trailingAnchor.constraint(equalTo: statusBox.contentView!.trailingAnchor, constant: -16),
            statusStack.topAnchor.constraint(equalTo: statusBox.contentView!.topAnchor, constant: 14),
            statusStack.bottomAnchor.constraint(equalTo: statusBox.contentView!.bottomAnchor, constant: -14)
        ])

        let installButton = makeButton("检查并修复", action: #selector(installPatch), prominent: true)
        let refreshButton = makeButton("重新检测", action: #selector(refreshButtonPressed))
        let restoreButton = makeButton("恢复官方版", action: #selector(restoreOfficial))
        let openButton = makeButton("打开并验证 Dia", action: #selector(openDia))
        operationButtons = [installButton, refreshButton, restoreButton, openButton]
        let buttonRow = NSStackView(views: operationButtons)
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 10
        buttonRow.distribution = .fillEqually

        autoCheck.target = self
        autoCheck.action = #selector(toggleAutomaticInstall)
        autoCheck.state = LaunchAgentManager.shared.isInstalled ? .on : .off
        autoCheck.font = .systemFont(ofSize: 13, weight: .medium)

        progress.style = .spinning
        progress.controlSize = .small
        progress.isDisplayedWhenStopped = false
        let autoRow = NSStackView(views: [autoCheck, progress])
        autoRow.orientation = .horizontal
        autoRow.spacing = 10

        logView.isEditable = false
        logView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        logView.textColor = .secondaryLabelColor
        logView.backgroundColor = .textBackgroundColor
        logView.textContainerInset = NSSize(width: 10, height: 8)
        let scroll = NSScrollView()
        scroll.documentView = logView
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 150).isActive = true

        let footnote = NSTextField(wrappingLabelWithString: "自动模式只处理结构兼容且带官方签名的新版 Dia；安装前会创建同版本完整备份，失败时自动恢复。")
        footnote.font = .systemFont(ofSize: 11)
        footnote.textColor = .tertiaryLabelColor

        let stack = NSStackView(views: [header, statusBox, buttonRow, autoRow, scroll, footnote])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20),
            statusBox.widthAnchor.constraint(equalTo: stack.widthAnchor),
            buttonRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            autoRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor),
            footnote.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
    }

    private func makeButton(_ title: String, action: Selector, prominent: Bool = false) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        button.controlSize = .large
        if prominent { button.keyEquivalent = "\r" }
        return button
    }

    private func setBusy(_ busy: Bool) {
        isBusy = busy
        operationButtons.forEach { $0.isEnabled = !busy }
        autoCheck.isEnabled = !busy
        busy ? progress.startAnimation(nil) : progress.stopAnimation(nil)
    }

    private func append(_ text: String) {
        guard !text.isEmpty else { return }
        let separator = logView.string.isEmpty ? "" : "\n"
        logView.string += separator + text.trimmingCharacters(in: .whitespacesAndNewlines)
        logView.scrollToEndOfDocument(nil)
    }

    private func updateStatus(from result: CommandResult) {
        append(result.output)
        guard result.code == 0 else {
            statusTitle.stringValue = "状态检查失败"
            statusTitle.textColor = .systemRed
            statusDetail.stringValue = result.output
            return
        }
        let state = PatchStatus(result.output)
        statusTitle.stringValue = state.title
        statusTitle.textColor = state.isVerified ? .systemGreen : .systemOrange
        statusDetail.stringValue = state.detail
    }

    private func refreshStatus() {
        setBusy(true)
        DispatchQueue.global(qos: .userInitiated).async {
            let result = PatchManager.shared.status()
            DispatchQueue.main.async {
                self.updateStatus(from: result)
                self.setBusy(false)
            }
        }
    }

    @objc private func refreshButtonPressed() { refreshStatus() }

    @objc private func installPatch() {
        setBusy(true)
        statusTitle.stringValue = "正在检查并修复…"
        append("正在检查并修复；备份和签名可能需要几分钟，请等待完成。")
        let initialLog = logView.string + "\n"
        DispatchQueue.global(qos: .userInitiated).async {
            let result = PatchManager.shared.install(interactive: true, onOutput: { output in
                DispatchQueue.main.async {
                    self.logView.string = initialLog + output
                    self.logView.scrollToEndOfDocument(nil)
                }
            })
            DispatchQueue.main.async {
                self.append(result.code == 0 ? "修复完成，正在重新核验资源。" : "修复未完成，请查看上方错误。")
                self.setBusy(false)
                self.refreshStatus()
                if result.code != 0 { NSSound.beep() }
            }
        }
    }

    @objc private func restoreOfficial() {
        let alert = NSAlert()
        alert.messageText = "恢复官方版 Dia？"
        alert.informativeText = "将使用本次安装前的同版本官方备份。Dia 会先退出，中文补丁将被移除。"
        alert.addButton(withTitle: "恢复")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        setBusy(true)
        DispatchQueue.global(qos: .userInitiated).async {
            let result = PatchManager.shared.restore()
            DispatchQueue.main.async {
                self.append(result.output)
                self.setBusy(false)
                self.refreshStatus()
            }
        }
    }

    @objc private func openDia() {
        setBusy(true)
        DispatchQueue.global(qos: .userInitiated).async {
            let result = PatchManager.shared.runPatch("launch")
            DispatchQueue.main.async {
                self.append(result.output)
                self.setBusy(false)
                self.refreshStatus()
            }
        }
    }

    @objc private func toggleAutomaticInstall() {
        do {
            if autoCheck.state == .on {
                try LaunchAgentManager.shared.install()
                append("已开启自动检查：每 5 分钟检查一次，只在 Dia 退出后安装。")
            } else {
                try LaunchAgentManager.shared.uninstall()
                append("已关闭自动检查。")
            }
        } catch {
            autoCheck.state = LaunchAgentManager.shared.isInstalled ? .on : .off
            append("自动检查设置失败：\(error.localizedDescription)")
            NSSound.beep()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowController: MainWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let arguments = CommandLine.arguments
        if arguments.contains("--auto-check") {
            NSApp.setActivationPolicy(.accessory)
            DispatchQueue.global(qos: .utility).async {
                PatchManager.shared.automaticCheck()
                DispatchQueue.main.async { NSApp.terminate(nil) }
            }
            return
        }
        if arguments.contains("--install-agent") {
            do {
                try LaunchAgentManager.shared.install()
                print("自动检查已开启。")
                exit(0)
            } catch {
                fputs("开启自动检查失败：\(error.localizedDescription)\n", stderr)
                exit(1)
            }
        }
        if arguments.contains("--remove-agent") {
            do {
                try LaunchAgentManager.shared.uninstall()
                print("自动检查已关闭。")
                exit(0)
            } catch {
                fputs("关闭自动检查失败：\(error.localizedDescription)\n", stderr)
                exit(1)
            }
        }

        NSApp.setActivationPolicy(.regular)
        windowController = MainWindowController()
        windowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if windowController?.isBusy == true {
            windowController?.showWindow(nil)
            NSSound.beep()
            return .terminateCancel
        }
        return .terminateNow
    }
}

// CLI checks finish without creating an AppKit event loop or UI windows.
if let command = CommandLine.arguments.dropFirst().first,
   ["--status", "--audit", "--repair", "--repair-background"].contains(command) {
    let result = PatchManager.shared.runPatch(String(command.dropFirst(2)), onOutput: nil)
    print(result.output)
    exit(result.code)
}
let application = NSApplication.shared
let applicationDelegate = AppDelegate()
application.delegate = applicationDelegate
application.run()
