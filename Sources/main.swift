// main.swift — SideDock 应用入口
// 依据对 SideDock 1.1 (arm64) 的静态逆向证据重建:
//   AppDelegate / 状态栏菜单 / 全局与本地事件监听 / TCC 引导
// 注:无 nib 的 AppKit 应用需手动装配 delegate(不适用 @main 默认装配)
import AppKit
import SwiftUI
import ServiceManagement

let app = NSApplication.shared
let appDelegate = AppDelegate()
app.delegate = appDelegate
app.run()

final class AppDelegate: NSObject, NSApplicationDelegate {
    let state = AppState.shared
    var sidebar: SidebarController?
    var shelfBarController: ShelfBarController?
    var settingsWindow: NSWindow?
    var statusItem: NSStatusItem?
    var localKeyMonitor: Any?
    var globalMouseMonitor: Any?
    var localMouseMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        sidebar = SidebarController(state: state)
        sidebar?.show()

        shelfBarController = ShelfBarController(state: state)
        if state.settings.shelfBarVisible { shelfBarController?.show() }

        setupStatusItem()
        setupEventMonitors()
        state.music.startWatch()   // 面板未展开时也持续跟踪,展开即有数据

        NotificationCenter.default.addObserver(
            forName: .sideDockOpenSettings, object: nil, queue: .main
        ) { [weak self] _ in
            self?.openSettings()
        }

        // 对齐原版 --promoshot(证据:cacheDisplayInRect:toBitmapImageRep:)
        if let outDir = ProcessInfo.processInfo.environment["SIDEDOCK_PROMOSHOT"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                self?.runPromoshot(outDir: outDir)
            }
        }
    }

    /// 把展开面板逐 Tab 渲染成 PNG,供与原版截图比对
    private func runPromoshot(outDir: String) {
        guard let sidebar = sidebar else { return }
        sidebar.expand()
        // 演示剪贴板数据(仿原作 promoshot 的演示数据流程;仅渲染模式注入)
        if state.clipboard.entries.isEmpty {
            let now = Date()
            state.clipboard.entries = [
                ClipEntry(text: "https://github.com/xiaohao/sidedock/pull/42",
                          copiedAt: now.addingTimeInterval(-300),
                          sourceBundle: "com.apple.Safari", sourceName: "Safari"),
                ClipEntry(text: "会议链接:https://meet.company.com/wed-standup",
                          copiedAt: now.addingTimeInterval(-1800), pinned: true,
                          pinnedAt: now.addingTimeInterval(-1700),
                          sourceBundle: "com.apple.Notes", sourceName: "备忘录"),
                ClipEntry(text: "转账备注:11 月房租 + 水电 3800",
                          copiedAt: now.addingTimeInterval(-7200),
                          sourceBundle: "com.tencent.xinWeChat", sourceName: "微信"),
            ]
        }
        let tabs: [PanelTab] = [.todo, .notes, .downloads, .shelf, .passwords]

        func step(_ idx: Int) {
            guard idx < tabs.count else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { NSApp.terminate(nil) }
                return
            }
            let tab = tabs[idx]
            state.settings.tab = tab
            if tab == .shelf { state.ui.shelfSegmentClips = true }   // 渲染剪贴板段
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                if let view = sidebar.panel.contentView, view.bounds.width > 50,
                   let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                              pixelsWide: Int(view.bounds.width * 2),
                                              pixelsHigh: Int(view.bounds.height * 2),
                                              bitsPerSample: 8, samplesPerPixel: 4,
                                              hasAlpha: true, isPlanar: false,
                                              colorSpaceName: .calibratedRGB,
                                              bytesPerRow: 0, bitsPerPixel: 0) {
                    rep.size = view.bounds.size
                    view.cacheDisplay(in: view.bounds, to: rep)
                    if let png = rep.representation(using: .png, properties: [:]) {
                        let url = URL(fileURLWithPath: outDir).appendingPathComponent("panel-\(tab.rawValue).png")
                        try? png.write(to: url)
                        print("[promoshot] wrote \(url.path)")
                    }
                }
                step(idx + 1)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { step(0) }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    // MARK: - 状态栏(证据: statusItemWithLength: / toggleSidebar / toggleShelfBar /
    // toggleLaunchAtLogin / openSettings / 打开系统设置)
    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = Self.sidebarTemplateIcon()
        item.button?.image?.isTemplate = true

        let menu = NSMenu()
        menu.addItem(withTitle: "展开 / 收起侧边栏", action: #selector(toggleSidebar), keyEquivalent: "")
        menu.addItem(withTitle: "显示货架条", action: #selector(toggleShelfBar), keyEquivalent: "")
            .state = state.settings.shelfBarVisible ? .on : .off
        menu.addItem(.separator())
        menu.addItem(withTitle: "开机时启动", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
            .state = launchAtLoginEnabled ? .on : .off
        menu.addItem(withTitle: "设置…", action: #selector(openSettings), keyEquivalent: ",")
        menu.addItem(withTitle: "打开系统设置", action: #selector(openSystemSettings), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出 SideDock", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.autoenablesItems = false
        for it in menu.items where it.action != #selector(NSApplication.terminate(_:)) { it.target = self }
        item.menu = menu
        statusItem = item
    }

    private var launchAtLoginEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    @objc private func toggleSidebar() { sidebar?.toggleExpanded() }

    @objc private func toggleShelfBar() {
        state.settings.shelfBarVisible.toggle()
        state.persistSettings()
        (statusItem?.menu?.items.first { $0.action == #selector(toggleShelfBar) })?
            .state = state.settings.shelfBarVisible ? .on : .off
        if state.settings.shelfBarVisible { shelfBarController?.show() } else { shelfBarController?.hide() }
    }

    @objc private func toggleLaunchAtLogin() {
        // 证据: SMAppService mainAppService registerAndReturnError: / alertWithError:
        do {
            let service = SMAppService.mainApp
            if service.status == .enabled { try service.unregister() } else { try service.register() }
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = "开机启动设置失败"
            alert.runModal()
        }
        (statusItem?.menu?.items.first { $0.action == #selector(toggleLaunchAtLogin) })?
            .state = launchAtLoginEnabled ? .on : .off
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 420, height: 520),
                styleMask: [.titled, .closable],
                backing: .buffered, defer: false
            )
            w.title = "SideDock 设置"
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: SettingsView(state: state))
            settingsWindow = w
        }
        settingsWindow?.center()
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func openSystemSettings() {
        // 证据: x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - 事件监听(证据: addGlobalMonitorForEventsMatchingMask: /
    // outsideClickMonitor / 应用内快捷键 / 侧边栏处于焦点时按下即收起)
    private func setupEventMonitors() {
        // 应用内快捷键:面板获得焦点时按下即切换
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let sidebar = self.sidebar else { return event }
            if let hk = self.state.settings.hotkey, hk.matches(event) {
                sidebar.toggleExpanded()
                return nil
            }
            return event
        }
        // 点击面板外部时收起(可关)
        let handler: (NSEvent) -> Void = { [weak self] _ in
            guard let self, let panel = self.sidebar?.panel else { return }
            let keepOpen = self.state.settings.pinned || self.state.settings.clickOutsideKeepsOpen
            guard !keepOpen, self.sidebar?.isExpanded == true else { return }
            let pt = NSEvent.mouseLocation
            let inPanel = panel.frame.contains(pt)
            let inSettings = self.settingsWindow?.frame.contains(pt) ?? false
            let inShelfBar = self.shelfBarController?.window?.frame.contains(pt) ?? false
            if !(inPanel || inSettings || inShelfBar) { self.sidebar?.collapse() }
        }
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: handler)
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { event in
            handler(event)
            return event
        }
    }

    static func sidebarTemplateIcon() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.black.setFill()
        let body = NSBezierPath(roundedRect: NSRect(x: 4, y: 3, width: 10, height: 12), xRadius: 2.5, yRadius: 2.5)
        body.fill()
        NSColor.white.setFill()
        let handle = NSBezierPath(roundedRect: NSRect(x: 11.5, y: 3, width: 2.5, height: 12), xRadius: 1.2, yRadius: 1.2)
        handle.fill()
        image.unlockFocus()
        image.isTemplate = true
        return image
    }
}
