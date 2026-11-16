// ClipboardBar.swift — 顶部菜单栏剪贴板(独立入口)
// 状态栏图标 + 悬浮面板,复用与"暂存 → 剪贴板"同一份 ClipboardStore 与
// MaccyClipboardList(搜索/固定区/来源图标/键盘导航/回写+自动粘贴)。
// 外观随主题:由 AppDelegate 在设置变化时推送 applyAppearance()。
import AppKit
import SwiftUI

// MARK: - 面板窗口(canBecomeKey:搜索框需要键焦点,又不激活整个应用)

final class ClipboardPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init(contentRect: NSRect) {
        super.init(contentRect: contentRect,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        isMovable = false
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        hasShadow = true
        isReleasedWhenClosed = false
    }
}

// MARK: - 控制器

final class ClipboardBarController: NSObject {
    private let state: AppState
    private var statusItem: NSStatusItem?
    private var panel: ClipboardPanel?
    private var outsideMonitors: [Any] = []

    static let panelSize = NSSize(width: 360, height: 470)

    init(state: AppState) {
        self.state = state
    }

    /// 设置开关入口(菜单栏显示/隐藏)
    func setEnabled(_ on: Bool) {
        on ? install() : uninstall()
    }

    /// 主题切换时同步面板外观(AppDelegate 推送)
    func applyAppearance() {
        panel?.appearance = NSAppearance(named: state.settings.themeIsDark ? .darkAqua : .aqua)
    }

    private func install() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "doc.on.clipboard",
                                   accessibilityDescription: "剪贴板")?
                .withSymbolConfiguration(.init(pointSize: 14, weight: .medium))
            button.target = self
            button.action = #selector(togglePanel)
            button.toolTip = "剪贴板历史"
        }
        statusItem = item
    }

    private func uninstall() {
        hidePanel()
        if let item = statusItem { NSStatusBar.system.removeStatusItem(item) }
        statusItem = nil
    }

    @objc private func togglePanel() {
        panel != nil ? hidePanel() : showPanel()
    }

    private func showPanel() {
        guard panel == nil, let button = statusItem?.button else { return }
        let p = ClipboardPanel(contentRect: NSRect(origin: .zero, size: Self.panelSize))
        let hosting = NSHostingController(rootView: ClipboardPopover(state: state) { [weak self] in
            self?.hidePanel()
        })
        hosting.sizingOptions = []
        p.contentViewController = hosting
        applyAppearance()

        // 定位:状态图标正下方水平居中,夹在可视区内
        if let win = button.window, let screen = win.screen {
            let iconFrame = win.convertToScreen(button.frame)
            let vis = screen.visibleFrame
            let x = max(vis.minX + 8,
                        min(iconFrame.midX - Self.panelSize.width / 2,
                            vis.maxX - Self.panelSize.width - 8))
            p.setFrameTopLeftPoint(NSPoint(x: x, y: iconFrame.minY - 6))
        }
        p.orderFrontRegardless()
        p.makeKey()
        panel = p
        state.ui.clipPopoverVisible = true

        // 点击面板外部关闭(全局监听其它应用;本地监听本应用其它窗口)。
        // 注意必须放行"状态栏图标本身"的点击,否则它的 toggle 动作会在
        // 监听器把面板关掉之后又重新打开,图标就再也关不上了。
        outsideMonitors.append(
            NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                guard let self else { return }
                if let frame = self.statusButtonScreenFrame(), frame.contains(NSEvent.mouseLocation) { return }
                self.hidePanel()
            }
        )
        outsideMonitors.append(
            NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] ev in
                guard let self else { return ev }
                if ev.window === self.panel { return ev }               // 面板内正常交互
                if ev.window === self.statusItem?.button?.window { return ev }  // 图标点击交给 action
                self.hidePanel()
                return ev
            }
        )
    }

    /// 状态栏图标在屏幕上的 frame(用于全局监听里排除图标自身的点击)
    private func statusButtonScreenFrame() -> NSRect? {
        guard let button = statusItem?.button, let win = button.window else { return nil }
        return win.convertToScreen(button.frame)
    }

    func hidePanel() {
        guard panel != nil else { return }
        outsideMonitors.forEach { NSEvent.removeMonitor($0) }
        outsideMonitors.removeAll()
        panel?.orderOut(nil)
        panel = nil
        state.ui.clipPopoverVisible = false
    }
}

// MARK: - 面板内容(标题行 + Maccy 式列表)

struct ClipboardPopover: View {
    @ObservedObject var state: AppState
    let onClose: () -> Void

    private var theme: ThemeColors { Theme.colors(dark: state.settings.themeIsDark) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "doc.on.clipboard")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.accent)
                Text("剪贴板").font(.system(size: 14, weight: .semibold)).foregroundStyle(theme.text)
                Spacer()
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(theme.text3)
                        .padding(5)
                        .background(Circle().fill(theme.pill))
                }
                .buttonStyle(.plain)
                .help("关闭")
            }
            ScrollView {
                MaccyClipboardList(state: state)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(theme.bg)
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(theme.border, lineWidth: 1))
                .shadow(color: .black.opacity(state.settings.themeIsDark ? 0.45 : 0.18), radius: 14, y: 6)
        )
    }
}
