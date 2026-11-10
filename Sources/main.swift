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
        patchDirectory.appendingPathComponent("dia-zh.command")
    }

    private init() {}

    func runPatch(_ command: String, environment extra: [String: String] = [:]) -> CommandResult {
        guard FileManager.default.fileExists(atPath: patchCommand.path) else {
            return CommandResult(code: 127, output: "找不到内置补丁：\(patchCommand.path)")
        }
        var environment = ProcessInfo.processInfo.environment
        extra.forEach { environment[$0] = $1 }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [patchCommand.path, command]
        process.currentDirectoryURL = patchDirectory
        process.environment = environment

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
        } catch {
            return CommandResult(code: 126, output: "无法启动补丁：\(error.localizedDescription)")
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(data: data, encoding: .utf8) ?? ""
        return CommandResult(code: process.terminationStatus, output: output)
    }

    func status() -> CommandResult {
        runPatch("status")
    }

    func install(interactive: Bool) -> CommandResult {
        let environment = interactive
            ? ["DIA_ZH_ASSUME_SMOKE_OK": "1"]
            : ["DIA_ZH_SKIP_SMOKE": "1"]
        return runPatch("apply", environment: environment)
    }

    func restore() -> CommandResult {
        runPatch("restore")
    }

    func isDiaRunning() -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: "company.thebrowser.dia").isEmpty
    }

    func automaticCheck() {
        appendLog("开始自动检查。")
        guard FileManager.default.fileExists(atPath: appPath) else {
            appendLog("未找到 /Applications/Dia.app。")
            return
        }

        let current = status()
        appendLog(current.output.trimmingCharacters(in: .whitespacesAndNewlines))
        guard current.code == 0 else {
            appendLog("状态检查失败，未进行写入。")
            return
        }

        if current.output.contains("补丁状态：applied") &&
            current.output.contains("有效的统一 ad-hoc 签名") {
            appendLog("当前版本已安装补丁。")
            return
        }
        guard current.output.contains("签名：Dia 官方签名") else {
            appendLog("Dia 不是可识别的官方签名，自动模式不会修改。")
            return
        }
        guard !current.output.contains("覆盖级别：incompatible") else {
            appendLog("当前 Dia 结构不兼容，自动模式不会修改。")
            notify(title: "Dia 中文补丁助手", message: "新版 Dia 暂不兼容，已保留官方原版。")
            return
        }
        guard !isDiaRunning() else {
            appendLog("检测到官方更新，但 Dia 正在运行；等待退出后再安装。")
            return
        }

        appendLog("检测到官方更新，开始安全重装。")
        let result = install(interactive: false)
        appendLog(result.output.trimmingCharacters(in: .whitespacesAndNewlines))
        if result.code == 0 {
            notify(title: "Dia 中文补丁助手", message: "新版 Dia 的中文补丁已自动安装。")
        } else {
            notify(title: "Dia 中文补丁助手", message: "自动安装失败，已尝试恢复官方原版。")
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

        let installButton = makeButton("安装 / 重新安装", action: #selector(installPatch), prominent: true)
        let refreshButton = makeButton("重新检测", action: #selector(refreshButtonPressed))
        let restoreButton = makeButton("恢复官方版", action: #selector(restoreOfficial))
        let openButton = makeButton("打开 Dia", action: #selector(openDia))
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
        let lines = result.output.components(separatedBy: .newlines)
        let version = lines.first { $0.hasPrefix("版本：") } ?? "版本：未知"
        let patch = lines.first { $0.hasPrefix("补丁状态：") } ?? "补丁状态：未知"
        let coverage = lines.first { $0.hasPrefix("覆盖级别：") } ?? "覆盖级别：未知"
        let signature = lines.first { $0.hasPrefix("签名：") } ?? "签名：未知"
        if patch.contains("applied") {
            statusTitle.stringValue = "中文补丁已生效"
            statusTitle.textColor = .systemGreen
        } else if signature.contains("官方签名") {
            statusTitle.stringValue = "检测到官方 Dia，等待安装补丁"
            statusTitle.textColor = .systemOrange
        } else {
            statusTitle.stringValue = "需要人工检查"
            statusTitle.textColor = .systemRed
        }
        statusDetail.stringValue = [version, patch, coverage, signature].joined(separator: "  ·  ")
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
        append("开始安装；如果 Dia 正在运行，将先安全退出……")
        DispatchQueue.global(qos: .userInitiated).async {
            let result = PatchManager.shared.install(interactive: true)
            DispatchQueue.main.async {
                self.append(result.output)
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
        let url = URL(fileURLWithPath: PatchManager.shared.appPath)
        NSWorkspace.shared.openApplication(at: url, configuration: .init()) { _, error in
            if let error = error { DispatchQueue.main.async { self.append("打开 Dia 失败：\(error.localizedDescription)") } }
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
}

let application = NSApplication.shared
let applicationDelegate = AppDelegate()
application.delegate = applicationDelegate
application.run()
