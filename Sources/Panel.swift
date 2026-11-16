// Panel.swift — 侧边栏窗体、把手与面板骨架
// 运行时观测证据(CGWindowList):
//   把手独立 12×96pt 贴右缘(window level 3 = floating);
//   展开面板 473×519 与把手右缘对齐、垂直以把手中心居中(把手中心=面板中心);
//   把手位于面板右缘之上(2498..2510 嵌于面板 x 范围内)。
// 渲染证据:面板为圆角卡片,头部 = SD 徽标 + 星期/日期 + 齿轮/图钉/箭头;
//   5 个胶囊 Tab(待办/笔记/下载/暂存/密码)带数字徽章;底部常驻音乐卡片。
import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

// MARK: - NSPanel 子类

final class SidebarPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init(contentRect: NSRect) {
        super.init(contentRect: contentRect,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .floating   // 观测:layer=3
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        isMovable = false
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        hasShadow = false   // 圆角卡片自带投影
        isReleasedWhenClosed = false
        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
    }
}

// MARK: - 控制器

final class SidebarController: ObservableObject {
    let state: AppState
    let panel: SidebarPanel
    @Published private(set) var isExpanded = false

    private var hoverTimer: Timer?
    private var exitCollapseTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    static let handleWidth: CGFloat = 12     // 观测:12pt
    static let handleHeight: CGFloat = 96    // 观测:96pt
    static let minPanelWidth: CGFloat = 360
    static let maxPanelWidth: CGFloat = 720
    static let minPanelHeight: CGFloat = 360
    static let maxPanelHeight: CGFloat = 1024

    init(state: AppState) {
        self.state = state
        panel = SidebarPanel(contentRect: Self.collapsedFrame(settings: state.settings))
        let hosting = NSHostingController(rootView: PanelRootView(state: state, controller: self))
        hosting.sizingOptions = []
        panel.contentViewController = hosting

        state.$settings
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.applyThemeIfNeeded() }
            .store(in: &cancellables)
        NotificationCenter.default.addObserver(
            forName: .sideDockGeometryReset, object: nil, queue: .main
        ) { [weak self] _ in
            self?.applyGeometry(animated: true)
        }
        applyThemeIfNeeded()
        applyGeometry(animated: false)
    }

    func show() { panel.orderFrontRegardless() }

    // MARK: 几何(观测:把手中心决定一切,面板垂直居中于把手)

    private static func visibleFrame() -> NSRect {
        NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
    }

    private static func clampedCenterY(_ raw: Double, height: CGFloat) -> CGFloat {
        let vis = visibleFrame()
        return min(max(raw, vis.minY + height / 2 + 4), vis.maxY - height / 2 - 4)
    }

    static func collapsedFrame(settings: Settings) -> NSRect {
        let vis = visibleFrame()
        let cy = clampedCenterY(settings.handleCenterY, height: handleHeight)
        return NSRect(x: vis.maxX - handleWidth,
                      y: cy - handleHeight / 2,
                      width: handleWidth, height: handleHeight)
    }

    static func expandedFrame(settings: Settings) -> NSRect {
        let vis = visibleFrame()
        let w = min(max(settings.panelWidth, minPanelWidth), maxPanelWidth)
        let h = min(max(settings.panelHeight, minPanelHeight), maxPanelHeight)
        let cy = clampedCenterY(settings.handleCenterY, height: h)
        return NSRect(x: vis.maxX - w, y: cy - h / 2, width: w, height: h)
    }

    func applyGeometry(animated: Bool) {
        let frame = isExpanded ? Self.expandedFrame(settings: state.settings)
                               : Self.collapsedFrame(settings: state.settings)
        panel.setFrame(frame, display: true, animate: animated)
    }

    private var appliedDark: Bool?
    private func applyThemeIfNeeded() {
        let dark = state.settings.themeIsDark
        guard appliedDark != dark else { return }
        appliedDark = dark
        panel.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    }

    // MARK: 展开 / 收起

    func expand() {
        guard !isExpanded else { return }
        isExpanded = true
        cancelHoverTimer()
        applyGeometry(animated: true)
    }

    func collapse() {
        guard isExpanded else { return }
        isExpanded = false
        cancelExitCollapse()
        applyGeometry(animated: true)
    }

    func toggleExpanded() { isExpanded ? collapse() : expand() }

    // MARK: 悬停逻辑(证据: 鼠标在把手上停留片刻即展开 / pendingExitCollapse)

    func handleHoverChanged(_ entered: Bool) {
        guard !isExpanded else { return }
        if entered, state.settings.autoExpand {
            cancelHoverTimer()
            hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: false) { [weak self] _ in
                self?.expand()
            }
        } else {
            cancelHoverTimer()
        }
    }

    private func cancelHoverTimer() { hoverTimer?.invalidate(); hoverTimer = nil }

    /// 展开后鼠标移出面板 → 延迟收起(常驻模式下不收起)
    func panelHoverChanged(_ entered: Bool) {
        guard isExpanded, state.settings.autoExpand, !state.settings.pinned else { return }
        cancelExitCollapse()
        if !entered {
            exitCollapseTimer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: false) { [weak self] _ in
                guard let self, !self.state.settings.pinned else { return }
                self.collapse()
            }
        }
    }

    private func cancelExitCollapse() { exitCollapseTimer?.invalidate(); exitCollapseTimer = nil }

    // MARK: 位置与尺寸(证据: 上下拖动把手调整位置 / 拖边缘角调整大小)

    func dragHandleBy(dy: CGFloat) {
        state.settings.handleCenterY += dy
        applyGeometry(animated: false)
    }

    func resizeBy(dWidth: CGFloat, dHeight: CGFloat) {
        var s = state.settings
        s.panelWidth = min(max(s.panelWidth + dWidth, Self.minPanelWidth), Self.maxPanelWidth)
        s.panelHeight = min(max(s.panelHeight + dHeight, Self.minPanelHeight), Self.maxPanelHeight)
        state.settings = s
        applyGeometry(animated: false)
    }

    func resizeWidthBy(_ d: CGFloat) { resizeBy(dWidth: d, dHeight: 0) }
    func resizeHeightBy(_ d: CGFloat) { resizeBy(dWidth: 0, dHeight: d) }
}

// MARK: - 根视图(把手在右侧,内容卡片在左)

struct PanelRootView: View {
    @ObservedObject var state: AppState
    @ObservedObject var controller: SidebarController

    var body: some View {
        HStack(spacing: 0) {
            if controller.isExpanded {
                PanelBody(state: state, controller: controller)
                    .transition(.opacity)
            }
            Spacer(minLength: 0)
            HandleColumn(controller: controller, state: state)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        .animation(.easeInOut(duration: 0.22), value: controller.isExpanded)
    }
}

// MARK: - 把手(观测:12pt 宽、96pt 高圆角竖条、握点、贴面板右缘)

struct HandleColumn: View {
    @ObservedObject var controller: SidebarController
    @ObservedObject var state: AppState

    private var theme: ThemeColors { Theme.colors(dark: state.settings.themeIsDark) }

    var body: some View {
        VStack(spacing: 5) {
            ForEach(0..<6, id: \.self) { _ in
                Circle()
                    .fill(state.ui.handleHovering ? theme.text.opacity(0.85) : theme.text.opacity(0.45))
                    .frame(width: 3, height: 3)
            }
        }
        .frame(width: SidebarController.handleWidth, height: SidebarController.handleHeight)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(state.ui.handleDropTargeted
                      ? theme.accent.opacity(0.75)
                      : (state.ui.handleHovering ? theme.bar : theme.bg.opacity(0.85)))
                .shadow(color: .black.opacity(0.35), radius: 4, x: -1, y: 1)
        )
        .contentShape(Rectangle())
        .onHover { entered in
            state.ui.handleHovering = entered
            controller.handleHoverChanged(entered)
        }
        .onTapGesture { controller.toggleExpanded() }
        .gesture(
            DragGesture(minimumDistance: 4)
                .onChanged { value in controller.dragHandleBy(dy: value.translation.height) }
        )
        .onDrop(of: [.fileURL], isTargeted: state.uiBind(\.handleDropTargeted)) { providers in
            for p in providers {
                _ = p.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    DispatchQueue.main.async { state.shelf.add(url) }
                }
            }
            return true
        }
        .help("点击 / 悬停展开 · 上下拖动调整位置")
    }
}

// MARK: - 面板主体(渲染证据:圆角卡片 = 头部 + Tab 栏 + 内容 + 底部音乐卡)

struct PanelBody: View {
    @ObservedObject var state: AppState
    @ObservedObject var controller: SidebarController

    private var theme: ThemeColors { Theme.colors(dark: state.settings.themeIsDark) }

    var body: some View {
        VStack(spacing: 12) {
            PanelHeader(state: state, controller: controller)
            PanelTabBar(state: state)
            PanelContent(state: state)
                .frame(maxHeight: .infinity)
            MusicCard(state: state)
        }
        .padding(14)
        .padding(.trailing, 5)   // 与右缘把手留出间距
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(theme.bg)
                .shadow(color: .black.opacity(0.28), radius: 18, x: -3, y: 4)
        )
        .overlay(alignment: .leading) { ResizeEdge(axis: .width, controller: controller) }
        .overlay(alignment: .bottom) { ResizeEdge(axis: .height, controller: controller) }
        .overlay(alignment: .bottomLeading) { ResizeCorner(controller: controller) }
        .padding(.trailing, 0)
    }
}

// MARK: 头部(渲染证据:SD 徽标 + 星期/日期 + 齿轮/图钉/箭头)

struct PanelHeader: View {
    @ObservedObject var state: AppState
    @ObservedObject var controller: SidebarController

    private var theme: ThemeColors { Theme.colors(dark: state.settings.themeIsDark) }

    var body: some View {
        HStack(spacing: 10) {
            SDLogo()
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 1) {
                Text(weekdayText).font(.system(size: 12)).foregroundStyle(theme.text2)
                Text(dateText).font(.system(size: 20, weight: .bold)).foregroundStyle(theme.text)
            }
            Spacer(minLength: 0)
            Button {
                NotificationCenter.default.post(name: .sideDockOpenSettings, object: nil)
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 15))
                    .foregroundStyle(theme.text2)
            }
            .buttonStyle(.plain)
            .help("设置")
            Button {
                state.settings.pinned.toggle()
            } label: {
                Image(systemName: state.settings.pinned ? "pin.fill" : "pin")
                    .font(.system(size: 15))
                    .foregroundStyle(state.settings.pinned ? theme.text : theme.text2)
            }
            .buttonStyle(.plain)
            .help(state.settings.pinned ? "常驻模式(已固定,不自动收起)" : "点击固定面板")
            Button {
                controller.collapse()
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.text2)
            }
            .buttonStyle(.plain)
            .help("收起侧边栏")
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 5)
                .onChanged { v in controller.dragHandleBy(dy: v.translation.height) }
        )
    }

    private var weekdayText: String {
        let f = DateFormatter(); f.locale = Locale(identifier: "zh_CN"); f.dateFormat = "EEEE"
        return f.string(from: Date())
    }

    private var dateText: String {
        let f = DateFormatter(); f.locale = Locale(identifier: "zh_CN"); f.dateFormat = "M月d日"
        return f.string(from: Date())
    }
}

// SD 徽标(渲染证据:蓝渐变圆角方块 + 白色粗体 SD)
struct SDLogo: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(LinearGradient(colors: [Color(hex: 0x4A9EFF), Color(hex: 0x2F7BFF)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            Text("SD").font(.system(size: 15, weight: .heavy, design: .rounded)).foregroundStyle(.white)
        }
    }
}

// MARK: Tab 栏(渲染证据:胶囊容器,5 个 Tab,选中蓝渐变胶囊白字,带数字徽章)

struct PanelTabBar: View {
    @ObservedObject var state: AppState

    private var theme: ThemeColors { Theme.colors(dark: state.settings.themeIsDark) }

    var body: some View {
        HStack(spacing: 2) {
            tabButton(.todo, badge: pendingTodoCount)
            tabButton(.notes, badge: nil)
            tabButton(.downloads, badge: nil)
            tabButton(.shelf, badge: state.shelf.items.count)
            tabButton(.passwords, badge: state.vault.entries.count)
        }
        .padding(3)
        .background(Capsule().fill(theme.bar))
    }

    private var pendingTodoCount: Int {
        state.todos.items.filter { !$0.done }.count
    }

    @ViewBuilder
    private func tabButton(_ tab: PanelTab, badge: Int?) -> some View {
        let selected = state.settings.tab == tab
        Button {
            state.settings.tab = tab
        } label: {
            HStack(spacing: 3) {
                Image(systemName: tab.symbol).font(.system(size: 10, weight: .medium))
                Text(tab.title).font(.system(size: 11, weight: selected ? .semibold : .regular))
                if let badge, badge > 0 {
                    Text("\(badge)")
                        .font(.system(size: 9, weight: .semibold))
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(Capsule().fill(selected ? Color.white.opacity(0.25) : theme.accent.opacity(0.15)))
                        .foregroundStyle(selected ? .white : theme.accent)
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(
                Capsule().fill(selected
                               ? AnyShapeStyle(LinearGradient(colors: [theme.accent, theme.accent2],
                                                              startPoint: .top, endPoint: .bottom))
                               : AnyShapeStyle(Color.clear))
            )
            .foregroundStyle(selected ? .white : theme.text2)
        }
        .buttonStyle(.plain)
    }
}

// MARK: 底部音乐卡片(渲染证据:封面+三行文字+进度条+时间+居中三键)

struct MusicCard: View {
    @ObservedObject var state: AppState
    @ObservedObject private var music = AppState.shared.music

    private var theme: ThemeColors { Theme.colors(dark: state.settings.themeIsDark) }

    var body: some View {
        VStack(spacing: 8) {
            if let snap = music.snapshot, !snap.title.isEmpty {
                HStack(spacing: 12) {
                    Group {
                        if let art = music.artwork {
                            Image(nsImage: art).resizable().aspectRatio(contentMode: .fill)
                        } else {
                            ZStack {
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(LinearGradient(colors: [Color(hex: 0x4A9EFF), Color(hex: 0x2F7BFF)],
                                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                                Image(systemName: "music.note").foregroundStyle(.white).font(.system(size: 18))
                            }
                        }
                    }
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                    VStack(alignment: .leading, spacing: 1) {
                        Text(snap.title).font(.system(size: 14, weight: .semibold)).foregroundStyle(theme.text)
                            .lineLimit(1)
                        Text([snap.artist, snap.album].filter { !$0.isEmpty }.joined(separator: " — "))
                            .font(.system(size: 11)).foregroundStyle(theme.text2).lineLimit(1)
                        Text(snap.app).font(.system(size: 10)).foregroundStyle(theme.text3)
                    }
                    Spacer(minLength: 0)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(theme.border)
                        Capsule().fill(LinearGradient(colors: [theme.accent, Color(hex: 0x22D3EE)],
                                                      startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(0, min(1, snap.elapsed / max(snap.duration, 0.1))) * geo.size.width)
                    }
                }
                .frame(height: 4)
                HStack {
                    Text(timeString(snap.elapsed)).font(.system(size: 10)).foregroundStyle(theme.text3)
                    Spacer()
                    Text("-" + timeString(max(0, snap.duration - snap.elapsed)))
                        .font(.system(size: 10)).foregroundStyle(theme.text3)
                }
                HStack(spacing: 44) {
                    Button { music.send(.previous) } label: {
                        Image(systemName: "backward.end.fill").font(.system(size: 14)).foregroundStyle(theme.text)
                    }
                    Button { music.send(.toggle) } label: {
                        Image(systemName: snap.playing ? "pause.fill" : "play.fill")
                            .font(.system(size: 20)).foregroundStyle(theme.text)
                    }
                    Button { music.send(.next) } label: {
                        Image(systemName: "forward.end.fill").font(.system(size: 14)).foregroundStyle(theme.text)
                    }
                }
                .buttonStyle(.plain)
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "music.note").font(.system(size: 12)).foregroundStyle(theme.text3)
                    Text("在任意播放器开始播放即可显示")
                        .font(.system(size: 11)).foregroundStyle(theme.text3)
                    Spacer()
                    Button { music.openPlayingApp() } label: {
                        Image(systemName: "arrow.up.forward.app").font(.system(size: 12))
                            .foregroundStyle(theme.text3)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16).fill(theme.card))
        .onAppear { music.startWatch() }
    }

    private func timeString(_ t: Double) -> String {
        guard t.isFinite, t > 0 else { return "0:00" }
        return String(format: "%d:%02d", Int(t) / 60, Int(t) % 60)
    }
}

// MARK: - 边缘拖拽调整大小(证据: resizeStartWidth/Height + 光标)

enum ResizeAxis { case width, height }

struct ResizeEdge: View {
    let axis: ResizeAxis
    @ObservedObject var controller: SidebarController

    var body: some View {
        Group {
            if axis == .width { Color.clear.frame(width: 7) } else { Color.clear.frame(height: 7) }
        }
        .contentShape(Rectangle())
        .onHover { inside in
            if inside {
                if axis == .width { NSCursor.resizeLeftRight.push() } else { NSCursor.resizeUpDown.push() }
            } else { NSCursor.pop() }
        }
        .gesture(
            DragGesture(minimumDistance: 2)
                .onChanged { v in
                    if axis == .width { controller.resizeWidthBy(-v.translation.width) }
                    else { controller.resizeHeightBy(v.translation.height) }
                }
        )
    }
}

struct ResizeCorner: View {
    @ObservedObject var controller: SidebarController

    var body: some View {
        Circle().fill(Color.primary.opacity(0.10)).frame(width: 10, height: 10)
            .frame(width: 16, height: 16)
            .contentShape(Rectangle())
            .onHover { inside in
                if inside { NSCursor.closedHand.push() } else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { v in
                        controller.resizeBy(dWidth: -v.translation.width, dHeight: v.translation.height)
                    }
            )
    }
}

extension Notification.Name {
    static let sideDockGeometryReset = Notification.Name("sideDockGeometryReset")
    static let sideDockOpenSettings = Notification.Name("sideDockOpenSettings")
}
