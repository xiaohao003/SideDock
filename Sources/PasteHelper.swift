// PasteHelper.swift — Maccy 式"选中即粘贴"与来源应用图标
// Maccy 行为证据(REA 逆向 2.8.0):选择历史项后回写剪贴板并向原前台应用
// 模拟 ⌘V(需辅助功能授权);每行显示来源应用图标(defaults 键 appIcon,
// 类 ApplicationImage/ApplicationImageCache)。
import AppKit
import ApplicationServices

/// 模拟 ⌘V 粘贴到当前前台应用(面板是 nonactivatingPanel,前台应用保持不变)
enum AutoPaste {
    static var isTrusted: Bool {
        AXIsProcessTrustedWithOptions([
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false,
        ] as CFDictionary)
    }

    /// 弹出系统"辅助功能"授权引导(每次运行最多弹一次系统对话框)
    static func promptForTrust() {
        _ = AXIsProcessTrustedWithOptions([
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true,
        ] as CFDictionary)
    }

    private static let vKey: CGKeyCode = 9   // kVK_ANSI_V

    static func pasteToFrontmost() {
        guard isTrusted, let src = CGEventSource(stateID: .hidSystemState) else { return }
        let down = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: true)
        down?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        usleep(25_000)
        let up = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: false)
        up?.flags = .maskCommand
        up?.post(tap: .cghidEventTap)
    }
}

/// 来源应用图标缓存(Maccy: ApplicationImageCache)
enum AppIconCache {
    private static var cache: [String: NSImage] = [:]

    static func icon(forBundle bundle: String?) -> NSImage? {
        guard let bundle, !bundle.isEmpty else { return nil }
        if let hit = cache[bundle] { return hit }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) else {
            return nil
        }
        let img = NSWorkspace.shared.icon(forFile: url.path)
        cache[bundle] = img
        return img
    }
}
