// AppState.swift — 全局状态与持久化
// 运行时观测证据(defaults read local.sidedock.SideDock):
//   panelWidth=472.6 / panelHeight=518.8 / panelOriginX/Y / panelTopGap / pinned=1
// 把手几何证据(CGWindowList):12×96pt 贴右缘,展开面板 473×519 与把手
// 右缘对齐、垂直以把手中心居中,window level=3(floating)
import AppKit
import Combine
import Foundation
import ServiceManagement
import SwiftUI

enum DataDir {
    // 证据: SIDEDOCK_DATA_DIR 环境变量可覆盖
    static let url: URL = {
        if let override = ProcessInfo.processInfo.environment["SIDEDOCK_DATA_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: (override as NSString).expandingTildeInPath)
        }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = support.appendingPathComponent("SideDock", isDirectory: true)
        // 更名迁移:旧数据目录一次性拷入(目标已存在则跳过)
        // (旧名拆开拼接,避免与批量重命名冲突)
        let legacy = support.appendingPathComponent("SideDock" + "Re", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path),
           FileManager.default.fileExists(atPath: legacy.path) {
            try? FileManager.default.copyItem(at: legacy, to: dir)
        }
        return dir
    }()

    static func ensure() {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    static func file(_ name: String) -> URL { ensure(); return url.appendingPathComponent(name) }
}

struct Hotkey: Codable, Equatable {
    var keyCode: UInt16
    var modifiers: UInt // NSEvent.ModifierFlags.rawValue

    var display: String {
        let flags = NSEvent.ModifierFlags(rawValue: modifiers)
        var parts: [String] = []
        if flags.contains(.command) { parts.append("⌘") }
        if flags.contains(.option) { parts.append("⌥") }
        if flags.contains(.control) { parts.append("⌃") }
        if flags.contains(.shift) { parts.append("⇧") }
        parts.append(Self.keyString(keyCode))
        return parts.joined()
    }

    func matches(_ event: NSEvent) -> Bool {
        let wanted = NSEvent.ModifierFlags(rawValue: modifiers)
            .intersection([.command, .option, .control, .shift])
        let got = event.modifierFlags.intersection([.command, .option, .control, .shift])
        return event.keyCode == keyCode && wanted == got
    }

    static func keyString(_ keyCode: UInt16) -> String {
        let map: [UInt16: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
            11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 18: "1", 19: "2",
            20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8",
            29: "0", 30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 36: "↩", 37: "L",
            38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/", 45: "N", 46: "M",
            47: ".", 48: "⇥", 49: "Space", 50: "`", 51: "⌫", 53: "Esc", 55: "⌘", 56: "⇧",
            57: "⇪", 58: "⌥", 59: "⌃", 60: "⇧", 61: "⌥", 62: "⌃", 63: "Fn",
            122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7",
            100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
            123: "←", 124: "→", 125: "↓", 126: "↑",
        ]
        return map[keyCode] ?? "#\(keyCode)"
    }
}

// 面板分类(渲染证据:5 个胶囊 Tab,顺序 待办/笔记/下载/暂存/密码;
// 剪贴板为用户要求新增的第 6 个 Tab,排在密码之后,不再内嵌于暂存)
enum PanelTab: String, Codable, CaseIterable, Identifiable {
    case todo, notes, downloads, shelf, passwords, clipboard
    var id: String { rawValue }

    var title: String {
        switch self {
        case .todo: return "待办"
        case .notes: return "笔记"
        case .downloads: return "下载"
        case .shelf: return "暂存"
        case .passwords: return "密码"
        case .clipboard: return "剪贴板"
        }
    }

    var symbol: String {
        switch self {
        case .todo: return "checklist"
        case .notes: return "note.text"
        case .downloads: return "arrow.down.circle"
        case .shelf: return "tray.and.arrow.down"
        case .passwords: return "key"
        case .clipboard: return "doc.on.clipboard"
        }
    }
}

// 主题模式:跟随系统 / 浅色 / 深色(themeIsDark 是"当前生效值",视图统一读它)
enum ThemeMode: String, Codable, CaseIterable {
    case system, light, dark
    var title: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }
}

struct Settings: Codable {
    var panelWidth: Double = 472
    var panelHeight: Double = 519
    var handleCenterY: Double = 860   // 把手中心在屏幕上的纵向位置(观测默认约屏高 60%)
    var backgroundOpacity: Double = 1.0
    var themeIsDark: Bool = false     // 当前生效主题(由 themeMode 解析;视图统一读这里)
    var themeMode: ThemeMode = .system  // 默认跟随系统
    var clipboardInMenuBar: Bool = true // 菜单栏剪贴板独立入口
    var autoExpand: Bool = true       // 悬停自动展开
    var pinned: Bool = true           // 观测默认 pinned=1
    var clickOutsideKeepsOpen: Bool = false
    var shelfBarVisible: Bool = false
    var hotkey: Hotkey? = nil
    var tab: PanelTab = .todo
    var shelfBarFrame: NSRect = NSRect(x: 200, y: 400, width: 260, height: 56)
    var autoPaste: Bool? = true       // Maccy 行为:选中历史项后自动粘贴到前台应用

    var autoPasteEnabled: Bool { autoPaste ?? true }

    // 自定义解码:缺字段回退默认值,避免新增设置项导致旧配置整体重置
    private enum CodingKeys: String, CodingKey {
        case panelWidth, panelHeight, handleCenterY, backgroundOpacity, themeIsDark, themeMode
        case autoExpand, pinned, clickOutsideKeepsOpen, shelfBarVisible, clipboardInMenuBar
        case hotkey, tab, shelfBarFrame, autoPaste
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        panelWidth = try c.decodeIfPresent(Double.self, forKey: .panelWidth) ?? 472
        panelHeight = try c.decodeIfPresent(Double.self, forKey: .panelHeight) ?? 519
        handleCenterY = try c.decodeIfPresent(Double.self, forKey: .handleCenterY) ?? 860
        backgroundOpacity = try c.decodeIfPresent(Double.self, forKey: .backgroundOpacity) ?? 1.0
        themeIsDark = try c.decodeIfPresent(Bool.self, forKey: .themeIsDark) ?? false
        // 旧配置无 themeMode:从原 themeIsDark 推导,不丢用户选择
        themeMode = try c.decodeIfPresent(ThemeMode.self, forKey: .themeMode)
            ?? (themeIsDark ? .dark : .light)
        autoExpand = try c.decodeIfPresent(Bool.self, forKey: .autoExpand) ?? true
        pinned = try c.decodeIfPresent(Bool.self, forKey: .pinned) ?? true
        clickOutsideKeepsOpen = try c.decodeIfPresent(Bool.self, forKey: .clickOutsideKeepsOpen) ?? false
        shelfBarVisible = try c.decodeIfPresent(Bool.self, forKey: .shelfBarVisible) ?? false
        clipboardInMenuBar = try c.decodeIfPresent(Bool.self, forKey: .clipboardInMenuBar) ?? true
        hotkey = try c.decodeIfPresent(Hotkey.self, forKey: .hotkey)
        tab = try c.decodeIfPresent(PanelTab.self, forKey: .tab) ?? .todo
        shelfBarFrame = try c.decodeIfPresent(NSRect.self, forKey: .shelfBarFrame)
            ?? NSRect(x: 200, y: 400, width: 260, height: 56)
        autoPaste = try c.decodeIfPresent(Bool.self, forKey: .autoPaste) ?? true
    }

    /// 系统当前是否深色外观
    /// accessory 应用上 NSApp.effectiveAppearance 可能滞后/失真,以系统全局 defaults 为准;
    /// "Auto"(自动切换)时 defaults 反映不了当下值,退回 effectiveAppearance。
    static func systemIsDark() -> Bool {
        let style = (UserDefaults.standard.string(forKey: "AppleInterfaceStyle") ?? "").lowercased()
        if style == "auto" {
            return NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        }
        if !style.isEmpty { return style.contains("dark") }
        return NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    /// 跟随系统模式下,把生效主题同步为系统外观
    /// notificationUserInfo:AppleInterfaceThemeChangedNotification 的 userInfo(含权威值)
    mutating func syncEffectiveTheme(notificationUserInfo: [AnyHashable: Any]? = nil) {
        guard themeMode == .system else { return }
        let dark: Bool
        if let style = notificationUserInfo?["AppleInterfaceTheme"] as? String,
           style == "Dark" || style == "Light" {
            dark = (style == "Dark")
        } else {
            dark = Self.systemIsDark()
        }
        if themeIsDark != dark { themeIsDark = dark }
    }
}

// 瞬时 UI 状态(工具链无 SwiftUI 宏插件,集中放常驻 ObservableObject)
final class UIState: ObservableObject {
    // 把手 / 拖放
    @Published var handleHovering = false
    @Published var handleDropTargeted = false
    @Published var shelfDropTargeted = false
    // 下载:分段(最近/全部)+ 搜索
    @Published var downloadsAll = false
    @Published var downloadsSearch = ""
    // 笔记 / 密码:内联新建表单开关
    @Published var notesAdding = false
    @Published var notesDraft = ""
    @Published var vaultAdding = false
    @Published var vaultSite = ""
    @Published var vaultAccount = ""
    @Published var vaultPhone = ""
    @Published var vaultPassword = ""
    @Published var vaultRevealFor: UUID?
    @Published var vaultRevealText: String?
    @Published var vaultToast: String?
    @Published var vaultEditingFor: UUID?
    @Published var vaultEditPassword = ""
    // 待办:到期预设 + 分组筛选 + 输入
    @Published var todoDraft = ""
    @Published var todoPreset: Int = 1   // 1 今日(默认,渲染证据) 2 明日 3 一周
    @Published var todoFilter: Int = 1   // 0 全部 1 今日 2 明日 3 一周 4 历史(已完成)
    @Published var todoHover: [UUID: Bool] = [:]   // 行悬停态(悬停才显示删除按钮)
    @Published var notesHover: [UUID: Bool] = [:]  // 笔记卡悬停态(同上)
    // 剪贴板(Maccy 式交互状态)
    @Published var clipboardCopiedID: UUID?
    @Published var clipSearch = ""
    @Published var clipSelectedIndex: Int?
    @Published var clipToast: String?
    @Published var clipHover: [UUID: Bool] = [:]
    @Published var clipPopoverVisible = false   // 菜单栏剪贴板弹窗是否打开
    // 设置
    @Published var launchAtLoginMirror = SMAppService.mainApp.status == .enabled
    @Published var hotkeyRecording = false
    var hotkeyMonitor: Any?
    var clipKeyMonitor: Any?
}

final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var settings: Settings {
        didSet { persistSettings() }
    }

    let ui = UIState()

    let notes = NotesStore()
    let todos = TodoStore()
    let shelf = ShelfStore()
    let vault = VaultStore()
    let clipboard = ClipboardStore()
    let downloads = DownloadsStore()
    let music = MusicController()

    private let defaults = UserDefaults.standard
    private static let settingsKey = "settings"

    init() {
        DataDir.ensure()
        if let data = UserDefaults.standard.data(forKey: Self.settingsKey),
           let s = try? JSONDecoder().decode(Settings.self, from: data) {
            settings = s
        } else {
            settings = Settings()
            if settings.handleCenterY == 860,
               let vis = NSScreen.main?.visibleFrame {
                // 首次运行:把手默认放在屏幕纵向 60% 处(观测值)
                settings.handleCenterY = vis.midY + vis.height * 0.1
            }
        }
        settings.syncEffectiveTheme()
    }

    /// 设置页选主题:同时落模式与生效值(跟随系统则立即按当前系统外观解析)
    func applyThemeMode(_ mode: ThemeMode) {
        var s = settings
        s.themeMode = mode
        s.themeIsDark = (mode == .system) ? Settings.systemIsDark() : (mode == .dark)
        settings = s
    }

    /// 系统外观切换通知 → 跟随系统模式同步
    func syncEffectiveTheme(notificationUserInfo: [AnyHashable: Any]? = nil) {
        var s = settings
        let before = s.themeIsDark
        s.syncEffectiveTheme(notificationUserInfo: notificationUserInfo)
        if s.themeIsDark != before { settings = s }
    }

    func persistSettings() {
        // promoshot 渲染模式不落盘:与正式实例共用 defaults 域,避免渲染期改写用户设置
        if ProcessInfo.processInfo.environment["SIDEDOCK_PROMOSHOT"] != nil { return }
        if let data = try? JSONEncoder().encode(settings) {
            defaults.set(data, forKey: Self.settingsKey)
        }
    }

    func resetPanelGeometry() {
        var s = settings
        s.panelWidth = 472; s.panelHeight = 519
        if let vis = NSScreen.main?.visibleFrame { s.handleCenterY = vis.midY + vis.height * 0.1 }
        settings = s
    }

    /// 便捷绑定(替代 @State + $value)
    func uiBind<Value>(_ keyPath: ReferenceWritableKeyPath<UIState, Value>) -> Binding<Value> {
        Binding(get: { self.ui[keyPath: keyPath] }, set: { self.ui[keyPath: keyPath] = $0 })
    }
}

// MARK: - 主题(渲染图取色)

struct ThemeColors {
    let bg: Color          // 面板卡片底
    let card: Color        // 内容卡片
    let bar: Color         // Tab 容器底
    let pill: Color        // 未选中胶囊
    let text: Color
    let text2: Color
    let text3: Color
    let accent: Color
    let accent2: Color
    let danger: Color
    let border: Color
}

enum Theme {
    // 色值取自原版 --promoshot 渲染图逐点取样(见 /tmp 对比记录):
    // 浅色 bg #F7F7F7 卡 #ECECEC chip #DCDCDC 选中渐变 #63A3FC→#32BFF1
    // 深色 bg #1C1C1F 卡 #262629 chip #363639
    static func colors(dark: Bool) -> ThemeColors {
        dark
        ? ThemeColors(
            bg: Color(hex: 0x1C1C1F), card: Color(hex: 0x262629), bar: Color(hex: 0x262629),
            pill: Color(hex: 0x363639), text: Color(hex: 0xE8E8EA), text2: Color(hex: 0x9A9AA0),
            text3: Color(hex: 0x6E6E74), accent: Color(hex: 0x4A8DFF), accent2: Color(hex: 0x32BFF1),
            danger: Color(hex: 0xE5534B), border: Color(hex: 0x3A3A3E))
        : ThemeColors(
            bg: Color(hex: 0xF7F7F8), card: Color(hex: 0xECECEC), bar: Color(hex: 0xECECEC),
            pill: Color(hex: 0xDCDCDC), text: Color(hex: 0x1C1C1E), text2: Color(hex: 0x6B6E75),
            text3: Color(hex: 0x9CA3AF), accent: Color(hex: 0x3B82F6), accent2: Color(hex: 0x32BFF1),
            danger: Color(hex: 0xE5484D), border: Color(hex: 0xE0E0E4))
    }
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: alpha)
    }
}
