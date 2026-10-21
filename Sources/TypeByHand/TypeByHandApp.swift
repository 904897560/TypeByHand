import AppKit
import ApplicationServices
import Carbon

/// 通过 CGEvent 逐字符模拟键盘输入（Unicode 方式，不依赖键盘布局）。
enum Typer {
    static func type(_ text: String, interval: useconds_t = 25_000) {
        let src = CGEventSource(stateID: .hidSystemState)
        for ch in text {
            let utf16 = Array(String(ch).utf16)
            for down in [true, false] {
                guard let ev = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: down) else { continue }
                ev.flags = []   // 避免热键的修饰键影响输入内容
                ev.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
                ev.post(tap: .cghidEventTap)
            }
            usleep(interval)
        }
    }

    /// 等待用户松开 ⌘⌃⌥⇧，最多 2 秒。
    static func waitForModifierRelease() {
        let mask: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift]
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            let flags = CGEventSource.flagsState(.combinedSessionState)
            if flags.intersection(mask).isEmpty { break }
            usleep(20_000)
        }
        usleep(80_000)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSTextFieldDelegate {
    static var shared: AppDelegate?

    private let defaults = UserDefaults.standard
    private var window: NSWindow!
    private let secureField = NSSecureTextField()
    private let plainField = NSTextField()
    private let showCheck = NSButton(checkboxWithTitle: "显示密码", target: nil, action: nil)
    private let delayField = NSTextField()
    private let startButton = NSButton(title: "开始输入", target: nil, action: nil)
    private let permButton = NSButton(title: "授予辅助功能权限", target: nil, action: nil)
    private let hotKeyButton = NSButton(title: "", target: nil, action: nil)
    private let hotKeyClear = NSButton(title: "清除", target: nil, action: nil)
    private let status = NSTextField(wrappingLabelWithString: "")

    private var countdownTimer: Timer?
    private var typing = false
    private var recorderMonitor: Any?

    private var hotKeyRef: EventHotKeyRef?
    private var handlerInstalled = false

    // MARK: 持久化设置
    private var delaySeconds: Double {
        get { defaults.object(forKey: "delay") as? Double ?? 2 }
        set { defaults.set(newValue, forKey: "delay") }
    }
    private var hotKeyCode: Int? {
        get { defaults.object(forKey: "hkCode") as? Int }
        set { defaults.set(newValue, forKey: "hkCode") }
    }
    private var hotKeyMods: Int { get { defaults.integer(forKey: "hkMods") } set { defaults.set(newValue, forKey: "hkMods") } }
    private var hotKeyName: String { get { defaults.string(forKey: "hkName") ?? "" } set { defaults.set(newValue, forKey: "hkName") } }

    private var password: String {
        get { showCheck.state == .on ? plainField.stringValue : secureField.stringValue }
        set { secureField.stringValue = newValue; plainField.stringValue = newValue }
    }

    // MARK: 启动
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        buildMenu()
        buildWindow()
        installHotKeyHandler()
        registerHotKey()
        refreshHotKeyUI()
        refreshPermission()
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.refreshPermission() }
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool { true }

    private func label(_ s: String) -> NSTextField {
        let l = NSTextField(labelWithString: s); return l
    }

    private func buildWindow() {
        secureField.placeholderString = "要输入的密码"
        plainField.placeholderString = "要输入的密码"
        plainField.isHidden = true
        secureField.delegate = self
        plainField.delegate = self

        // 两个输入框叠放，切换显示/隐藏
        let fieldBox = NSView()
        for f in [secureField, plainField] {
            f.translatesAutoresizingMaskIntoConstraints = false
            fieldBox.addSubview(f)
            NSLayoutConstraint.activate([
                f.leadingAnchor.constraint(equalTo: fieldBox.leadingAnchor),
                f.trailingAnchor.constraint(equalTo: fieldBox.trailingAnchor),
                f.topAnchor.constraint(equalTo: fieldBox.topAnchor),
                f.bottomAnchor.constraint(equalTo: fieldBox.bottomAnchor),
            ])
        }
        showCheck.target = self; showCheck.action = #selector(toggleShow)

        delayField.stringValue = format(delaySeconds)
        delayField.alignment = .right
        delayField.delegate = self
        delayField.widthAnchor.constraint(equalToConstant: 60).isActive = true
        let delayRow = NSStackView(views: [label("按钮延迟"), delayField, label("秒（0 = 立即，可填小数）")])
        delayRow.spacing = 8

        hotKeyButton.target = self; hotKeyButton.action = #selector(recordHotKey)
        hotKeyButton.widthAnchor.constraint(equalToConstant: 140).isActive = true
        hotKeyClear.target = self; hotKeyClear.action = #selector(clearHotKey)
        let hotKeyRow = NSStackView(views: [label("快捷键"), hotKeyButton, hotKeyClear])
        hotKeyRow.spacing = 8

        startButton.target = self; startButton.action = #selector(startWithDelay)
        startButton.keyEquivalent = "\r"
        permButton.target = self; permButton.action = #selector(requestPermission)
        let buttonRow = NSStackView(views: [startButton, permButton])
        buttonRow.spacing = 8

        status.textColor = .secondaryLabelColor
        status.font = .systemFont(ofSize: 11)
        status.stringValue = "快捷键会立即向当前焦点输入框键入密码。"

        let stack = NSStackView(views: [fieldBox, showCheck, delayRow, hotKeyRow, buttonRow, status])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        fieldBox.widthAnchor.constraint(equalToConstant: 360).isActive = true
        status.widthAnchor.constraint(equalToConstant: 360).isActive = true

        let vc = NSViewController(); vc.view = stack
        window = NSWindow(contentViewController: vc)
        window.title = "TypeByHand"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    private func buildMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem(); main.addItem(appItem)
        let appMenu = NSMenu(); appItem.submenu = appMenu
        appMenu.addItem(withTitle: "退出 TypeByHand", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let editItem = NSMenuItem(); main.addItem(editItem)
        let edit = NSMenu(title: "编辑"); editItem.submenu = edit
        edit.addItem(withTitle: "拷贝", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        NSApp.mainMenu = main
    }

    // MARK: 输入框同步 & 延迟
    func controlTextDidChange(_ obj: Notification) {
        guard let f = obj.object as? NSTextField else { return }
        if f === secureField { plainField.stringValue = secureField.stringValue }
        else if f === plainField { secureField.stringValue = plainField.stringValue }
        else if f === delayField {
            if let v = parseDelay(delayField.stringValue) { delaySeconds = v }
        }
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard (obj.object as? NSTextField) === delayField else { return }
        delayField.stringValue = format(delaySeconds)   // 非法输入回退到上次有效值
    }

    private func parseDelay(_ s: String) -> Double? {
        let t = s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard let v = Double(t), v >= 0, v <= 600 else { return nil }
        return v
    }

    private func format(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(format: "%g", v)
    }

    @objc private func toggleShow() {
        let on = showCheck.state == .on
        if on { plainField.stringValue = secureField.stringValue }
        else { secureField.stringValue = plainField.stringValue }
        plainField.isHidden = !on
        secureField.isHidden = on
    }

    // MARK: 权限
    private func refreshPermission() {
        let ok = AXIsProcessTrusted()
        permButton.isHidden = ok
        if !ok && !typing && countdownTimer == nil {
            status.stringValue = "需要在 系统设置 > 隐私与安全性 > 辅助功能 中允许 TypeByHand，然后重启本应用。"
        }
    }

    @objc private func requestPermission() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }

    // MARK: 按钮触发（带延迟）
    @objc private func startWithDelay() {
        guard canStart() else { return }
        window.makeFirstResponder(nil)
        let delay = parseDelay(delayField.stringValue) ?? delaySeconds
        let text = password
        let deadline = Date().addingTimeInterval(delay)
        startButton.isEnabled = false
        updateCountdown(deadline)
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] t in
            guard let self = self else { t.invalidate(); return }
            if Date() >= deadline {
                t.invalidate(); self.countdownTimer = nil
                self.performTyping(text, waitModifiers: false)
            } else {
                self.updateCountdown(deadline)
            }
        }
    }

    private func updateCountdown(_ deadline: Date) {
        let left = max(0, deadline.timeIntervalSinceNow)
        status.stringValue = String(format: "请点击目标密码框……%.1f 秒后开始输入", left)
    }

    // MARK: 热键触发（立即）
    func hotKeyFired() {
        guard canStart() else { return }
        if NSApp.isActive {
            status.stringValue = "请先切换到目标窗口再按快捷键。"
            return
        }
        performTyping(password, waitModifiers: true)
    }

    private func canStart() -> Bool {
        guard !typing, countdownTimer == nil else { return false }
        guard AXIsProcessTrusted() else {
            status.stringValue = "缺少辅助功能权限，请先点击“授予辅助功能权限”。"
            return false
        }
        guard !password.isEmpty else { status.stringValue = "密码为空"; return false }
        return true
    }

    private func performTyping(_ text: String, waitModifiers: Bool) {
        typing = true
        startButton.isEnabled = false
        status.stringValue = "输入中…"
        DispatchQueue.global(qos: .userInitiated).async {
            if waitModifiers { Typer.waitForModifierRelease() }
            Typer.type(text)
            DispatchQueue.main.async {
                self.typing = false
                self.startButton.isEnabled = true
                self.status.stringValue = "已输入 \(text.count) 个字符"
            }
        }
    }

    // MARK: 快捷键录制与注册
    @objc private func recordHotKey() {
        guard recorderMonitor == nil else { return }
        hotKeyButton.title = "请按下组合键…（Esc 取消）"
        recorderMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] ev in
            guard let self = self else { return ev }
            self.finishRecording()
            if ev.keyCode == UInt16(kVK_Escape) { self.refreshHotKeyUI(); return nil }
            let mods = ev.modifierFlags.intersection([.command, .control, .option, .shift])
            if mods.isEmpty {
                self.status.stringValue = "快捷键必须包含 ⌘ ⌃ ⌥ ⇧ 中至少一个修饰键。"
                self.refreshHotKeyUI()
                return nil
            }
            self.hotKeyCode = Int(ev.keyCode)
            self.hotKeyMods = Int(mods.rawValue)
            self.hotKeyName = Self.describe(ev, mods)
            self.registerHotKey()
            self.refreshHotKeyUI()
            return nil
        }
    }

    private func finishRecording() {
        if let m = recorderMonitor { NSEvent.removeMonitor(m); recorderMonitor = nil }
    }

    @objc private func clearHotKey() {
        finishRecording()
        defaults.removeObject(forKey: "hkCode")
        defaults.removeObject(forKey: "hkMods")
        defaults.removeObject(forKey: "hkName")
        unregisterHotKey()
        refreshHotKeyUI()
        status.stringValue = "已清除快捷键。"
    }

    private func refreshHotKeyUI() {
        hotKeyButton.title = hotKeyCode == nil ? "点击录制" : hotKeyName
        hotKeyClear.isEnabled = hotKeyCode != nil
    }

    private static func describe(_ ev: NSEvent, _ mods: NSEvent.ModifierFlags) -> String {
        var s = ""
        if mods.contains(.control) { s += "⌃" }
        if mods.contains(.option) { s += "⌥" }
        if mods.contains(.shift) { s += "⇧" }
        if mods.contains(.command) { s += "⌘" }
        let special: [Int: String] = [
            kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫",
            kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
            kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
            kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        ]
        if let n = special[Int(ev.keyCode)] { return s + n }
        return s + (ev.charactersIgnoringModifiers?.uppercased() ?? "Key\(ev.keyCode)")
    }

    private func installHotKeyHandler() {
        guard !handlerInstalled else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async { AppDelegate.shared?.hotKeyFired() }
            return noErr
        }, 1, &spec, nil, nil)
        handlerInstalled = true
    }

    private func unregisterHotKey() {
        if let r = hotKeyRef { UnregisterEventHotKey(r); hotKeyRef = nil }
    }

    private func registerHotKey() {
        unregisterHotKey()
        guard let code = hotKeyCode else { return }
        let flags = NSEvent.ModifierFlags(rawValue: UInt(hotKeyMods))
        var carbon: UInt32 = 0
        if flags.contains(.command) { carbon |= UInt32(cmdKey) }
        if flags.contains(.shift) { carbon |= UInt32(shiftKey) }
        if flags.contains(.option) { carbon |= UInt32(optionKey) }
        if flags.contains(.control) { carbon |= UInt32(controlKey) }
        let id = EventHotKeyID(signature: OSType(0x4B545950), id: 1)
        let rc = RegisterEventHotKey(UInt32(code), carbon, id, GetApplicationEventTarget(), 0, &hotKeyRef)
        if rc != noErr { status.stringValue = "快捷键注册失败（可能已被其他程序占用），请换一个。" }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
