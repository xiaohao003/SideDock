// main.swift — SideDock 应用入口
// 依据对 SideDock 1.1 (arm64) 的静态逆向证据重建:
//   AppDelegate / 状态栏菜单 / 全局与本地事件监听 / TCC 引导
// 注:无 nib 的 AppKit 应用需手动装配 delegate(不适用 @main 默认装配)
import AppKit
import Combine
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
    // 菜单栏剪贴板入口暂时下线(代码保留在 ClipboardBar.swift,恢复时在此创建
    // ClipboardBarController 并调用 setupThemeSync 里的两个 sink 即可)
    var settingsWindow: NSWindow?
    var statusItem: NSStatusItem?
    var localKeyMonitor: Any?
    var globalMouseMonitor: Any?
    var localMouseMonitor: Any?
    var themeCancellables = Set<Combine.AnyCancellable>()
    var themeObserver: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupEditMenu()

        sidebar = SidebarController(state: state)
        sidebar?.show()

        shelfBarController = ShelfBarController(state: state)
        if state.settings.shelfBarVisible { shelfBarController?.show() }

        setupStatusItem()
        setupEventMonitors()
        setupThemeSync()
        state.clipboard.startWatching()   // 剪贴板监听必须在启动时挂上(轮询 changeCount)
        state.music.startWatch()   // 面板未展开时也持续跟踪,展开即有数据

        NotificationCenter.default.addObserver(
            forName: .sideDockOpenSettings, object: nil, queue: .main
        ) { [weak self] _ in
            self?.openSettings()
        }

        // 诊断导出:SIDEDOCK_DUMP_PANEL=<png 路径> → 原样渲染当前面板 + 打印生效设置后退出
        // (不强改主题/尺寸,用于排查"设置变深了面板还是浅色"这类运行时问题)
        // SIDEDOCK_DUMP_PANEL_FLIP=<png2> 时:第一张之后模拟用户切到深色再导一张,
        // 用于复现"会话中途切主题面板不刷新"。
        if let dumpPath = ProcessInfo.processInfo.environment["SIDEDOCK_DUMP_PANEL"] {
            let flipPath = ProcessInfo.processInfo.environment["SIDEDOCK_DUMP_PANEL_FLIP"]
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                self?.dumpPanelForDiagnostics(to: dumpPath, thenFlipTo: flipPath)
            }
        }

        // 对齐原版 --promoshot(证据:cacheDisplayInRect:toBitmapImageRep:)
        if let outDir = ProcessInfo.processInfo.environment["SIDEDOCK_PROMOSHOT"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                self?.runPromoshot(outDir: outDir)
            }
        }
    }

    /// 诊断:按当前状态渲染面板 + 打印设置,不动任何用户数据
    private func dumpPanelForDiagnostics(to path: String, thenFlipTo flipPath: String? = nil) {
        sidebar?.expand()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.renderPanelPNG(to: path)
            print("[dump] settings = \(self.settingsJSON())")
            print("[dump] panelAppearance = \(self.sidebar?.panel.appearance?.name.rawValue ?? "?") " +
                  "settingsWindowAppearance = \(self.settingsWindow?.appearance?.name.rawValue ?? "nil")")
            if let flipPath {
                // 模拟用户在设置里把主题切到深色(与 Picker 同一路径)
                self.state.applyThemeMode(.dark)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.renderPanelPNG(to: flipPath)
                    print("[dump][flip] settings = \(self.settingsJSON())")
                    print("[dump][flip] panelAppearance = \(self.sidebar?.panel.appearance?.name.rawValue ?? "?")")
                    NSApp.terminate(nil)
                }
            } else {
                NSApp.terminate(nil)
            }
        }
    }

    private func settingsJSON() -> String {
        if let data = try? JSONEncoder().encode(state.settings) {
            return String(data: data, encoding: .utf8) ?? "?"
        }
        return "?"
    }

    private func renderPanelPNG(to path: String) {
        guard let view = sidebar?.panel.contentView, view.bounds.width > 50,
              let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                         pixelsWide: Int(view.bounds.width * 2),
                                         pixelsHigh: Int(view.bounds.height * 2),
                                         bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .calibratedRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0) else { return }
        rep.size = view.bounds.size
        view.cacheDisplay(in: view.bounds, to: rep)
        if let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: path))
            print("[dump] wrote \(path)")
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
        // 与原版 --promoshot 输出基本同款(panel-{todo,shelf}-{light,dark} +
        // notes/downloads/passwords-light);剪贴板是本项目新增 Tab,无原版对应,
        // 输出 panel-clipboard-light.png 做回归记录。主题强制按每张固定,
        // 不读用户已存设置(否则共享 defaults 域会把渲染带偏)。
        let jobs: [(file: String, tab: PanelTab, dark: Bool)] = [
            ("panel-todo-light.png",       .todo,      false),
            ("panel-todo-dark.png",        .todo,      true),
            ("panel-notes-light.png",      .notes,     false),
            ("panel-downloads-light.png",  .downloads, false),
            ("panel-passwords-light.png",  .passwords, false),
            ("panel-shelf-light.png",      .shelf,     false),
            ("panel-shelf-dark.png",       .shelf,     true),
            ("panel-clipboard-light.png",  .clipboard, false),
        ]
        let savedSettings = state.settings
        // 渲染对照原版 promoshot:音乐卡强制显示(与用户设置无关)
        state.settings.musicCardVisible = true
        // 演示数据对齐原版 promoshot(仅渲染用;JSON 落在隔离的 SIDEDOCK_DATA_DIR,
        // 密码只注入内存条目、不写钥匙串)
        if state.todos.items.isEmpty {
            let cal = Calendar.current
            let day = cal.startOfDay(for: Date())
            func at(_ h: Int, _ m: Int, days: Int = 0) -> Date {
                cal.date(byAdding: DateComponents(day: days, hour: h, minute: m), to: day)!
            }
            let now = Date()
            state.todos.items = [
                TodoItem(title: "提交季度报销单", due: at(9, 0), createdAt: now),
                TodoItem(title: "给妈妈打视频电话", due: at(14, 8), createdAt: now),
                TodoItem(title: "整理周会纪要要发到大群", due: at(18, 0), createdAt: now),
                TodoItem(title: "回复客户邮件", due: at(19, 30), createdAt: now),
                TodoItem(title: "给设计稿补标注", due: at(10, 0, days: 1)),
                TodoItem(title: "预约年度体检", due: at(11, 0, days: 1)),
                TodoItem(title: "复盘上线首周数据", due: at(10, 0, days: 3)),
                TodoItem(title: "更新依赖到最新版本", due: at(15, 0, days: 3)),
                TodoItem(title: "写月度 OKR 草稿", due: at(10, 0, days: 4)),
                TodoItem(title: "处理发票报销", due: at(16, 0, days: 4)),
                TodoItem(title: "清理测试设备", due: at(11, 0, days: 5)),
                TodoItem(title: "回访 3 位种子用户", due: at(14, 0, days: 5)),
                TodoItem(title: "准备分享会大纲", due: at(10, 0, days: 6)),
                TodoItem(title: "检查自动备份任务", due: at(17, 0, days: 6)),
                TodoItem(title: "确认新 Logo 定稿", due: at(12, 0, days: -1), done: true, doneAt: now),
                TodoItem(title: "续费域名", due: at(12, 0, days: -2), done: true, doneAt: now),
                TodoItem(title: "回复周末值班消息", due: at(12, 0, days: -3), done: true, doneAt: now),
            ]
        }
        if state.notes.notes.isEmpty {
            let now = Date()
            state.notes.notes = [
                Note(text: "周三晨会要点\n- 讲新版侧边栏的三个卖点\n- 收集大家的改进意见",
                     createdAt: now.addingTimeInterval(-600)),
                Note(text: "灵感：把宣传图的配色用到加载动画里", createdAt: now.addingTimeInterval(-86400)),
                Note(text: "密码：家里 Wi-Fi 是 zhilan-2019（别外传）",
                     createdAt: now.addingTimeInterval(-2 * 86400)),
            ]
        }
        if state.vault.entries.isEmpty {
            state.vault.entries = [
                VaultEntry(site: "GitHub", account: "xiaohao-dev"),
                VaultEntry(site: "工作邮箱", account: "xiaohao@company.com"),
                VaultEntry(site: "NAS 管理后台", account: "admin"),
            ]
        }
        if state.shelf.items.isEmpty {
            // 造 6 个空演示文件,只为拿到文件类型图标
            let dir = FileManager.default.temporaryDirectory
                .appendingPathComponent("SideDockPromo", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let names = ["年度总结.pptx", "合同扫描件.pdf", "设计素材包.zip",
                         "会议纪要.md", "封面草图.png", "销售数据.xlsx"]
            var items: [ShelfItem] = []
            for name in names {
                let url = dir.appendingPathComponent(name)
                if !FileManager.default.fileExists(atPath: url.path) {
                    FileManager.default.createFile(atPath: url.path, contents: Data())
                }
                items.append(ShelfItem(path: url.path))
            }
            state.shelf.items = items
        }
        // 演示曲目(渲染证据:原版 promoshot 用蓝渐变占位封面 + 固定曲目)
        state.music.snapshot = NowPlayingSnapshot(bundle: "com.tencent.QQMusic", app: "QQ音乐",
                                                  playing: true, title: "晚风信箱",
                                                  artist: "城市漫游者", album: "夜行车",
                                                  duration: 227, elapsed: 96)
        // 渲染尺寸对齐原版 promoshot(720×1280@2x = 360×640pt);expand 已发生过,重设几何
        state.settings.panelWidth = 360
        state.settings.panelHeight = 640
        sidebar.applyGeometry(animated: false)

        // 渲染期把窗口 appearance 跟着主题切,深色变体才画得对
        func apply(_ job: (file: String, tab: PanelTab, dark: Bool)) {
            // 同时固定模式:避免"跟随系统"的同步逻辑在渲染期改写生效主题
            state.settings.themeMode = job.dark ? .dark : .light
            state.settings.themeIsDark = job.dark
            state.settings.tab = job.tab
            sidebar.panel.appearance = NSAppearance(named: job.dark ? .darkAqua : .aqua)
        }

        func step(_ idx: Int) {
            guard idx < jobs.count else {
                state.settings = savedSettings   // persist 在 promoshot 模式已被抑制
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { NSApp.terminate(nil) }
                return
            }
            apply(jobs[idx])
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
                        let url = URL(fileURLWithPath: outDir).appendingPathComponent(jobs[idx].file)
                        try? png.write(to: url)
                        print("[promoshot] 生成 \(jobs[idx].file) (\(rep.pixelsWide)×\(rep.pixelsHigh))")
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
    // MARK: 主题联动
    // 生效主题(themeIsDark)变化来源:设置页三选切换 / 系统外观切换(跟随系统模式)。
    // SwiftUI 内容颜色由 @Published settings 自动驱动;这里只负责原生窗口外观同步:
    // 设置窗口与菜单栏剪贴板面板(侧边栏面板由 SidebarController 自己的 sink 处理)。
    private func setupThemeSync() {
        themeObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil, queue: .main
        ) { [weak state] note in
            state?.syncEffectiveTheme(notificationUserInfo: note.userInfo)
        }

        state.$settings
            .map(\.themeIsDark)
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] dark in
                self?.settingsWindow?.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            }
            .store(in: &themeCancellables)
    }

    /// 无菜单栏 accessory 应用的输入框需要 Edit 菜单承接 ⌘X/⌘C/⌘V/⌘A 的按键等价物:
    /// 没有它,非激活面板里 SwiftUI TextField 的粘贴/全选会静默失效
    /// (菜单项 target 为 nil,按键等价物经响应链路由到字段编辑器的 cut:/copy:/paste:/selectAll:)
    private func setupEditMenu() {
        let edit = NSMenu(title: "编辑")
        edit.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "拷贝", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let editItem = NSMenuItem()
        editItem.title = "编辑"
        editItem.submenu = edit
        let main = NSMenu(title: "主菜单")
        main.addItem(editItem)
        NSApp.mainMenu = main
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = Self.sidebarTemplateIcon()
        item.button?.image?.isTemplate = true
        item.button?.toolTip = "SideDock"

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
        // 设置窗口外观跟随面板主题
        settingsWindow?.appearance = NSAppearance(named: state.settings.themeIsDark ? .darkAqua : .aqua)
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

    /// 菜单栏图标(模板图:系统只取 alpha 通道后按菜单栏深浅着色,颜色信息被忽略)。
    /// 旧实现用白色画把手 —— 白色在模板图里同样是不透明像素,整个图标糊成一块实心圆角块;
    /// 现在面板与把手分两块绘制,中间留 1.5pt 透明缝,图案才出得来。
    /// 各边落在整/半像素上,1x 显示器上缝隙与把手也清晰(实测 1x 菜单栏渲染)。
    static func sidebarTemplateIcon() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.black.setFill()
            // 面板(左)
            NSBezierPath(roundedRect: NSRect(x: 3, y: 3, width: 7.5, height: 12),
                         xRadius: 2.5, yRadius: 2.5).fill()
            // 把手(右)
            NSBezierPath(roundedRect: NSRect(x: 12, y: 3, width: 3, height: 12),
                         xRadius: 1.5, yRadius: 1.5).fill()
            return true
        }
        image.isTemplate = true
        return image
    }
}
