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

// MARK: - 真实取景模糊(NSVisualEffectView)
// 面板为透明 NSPanel(backgroundColor = .clear),behindWindow 模糊即真实毛玻璃透出桌面

struct VisualEffectBackground: NSViewRepresentable {
    let dark: Bool

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.state = .active
        view.isEmphasized = false
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        // 浅色 .sidebar / 深色 .hudWindow:对应设计稿 blur 28(sat 180%)与 blur 30(sat 150%)的观感
        view.material = dark ? .hudWindow : .sidebar
    }
}

// MARK: - 玻璃面板背景(材质 + tint + 顶部内侧高光 + 发丝描边 + 双层投影)

struct GlassPanelBackground: View {
    let theme: ThemeColors
    let opacityScale: Double   // 设置里的 backgroundOpacity,乘在 tint 上
    var cornerRadius: CGFloat = 20

    var body: some View {
        ZStack {
            VisualEffectBackground(dark: theme.isDark)
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(theme.bg.opacity(opacityScale))
            // 顶部内侧高光(luminous edge)
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(LinearGradient(colors: [theme.panelHighlight, Color.clear],
                                     startPoint: .top, endPoint: .center))
                .allowsHitTesting(false)
        }
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius)
                .strokeBorder(theme.panelBorderOut, lineWidth: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius)
                .strokeBorder(theme.border, lineWidth: 1)
                .padding(0.5)
        )
        // 双层投影:环境影 + 接触影
        .shadow(color: .black.opacity(theme.isDark ? 0.60 : 0.38), radius: 28, x: -6, y: 14)
        .shadow(color: .black.opacity(theme.isDark ? 0.32 : 0.12), radius: 10, x: -2, y: 4)
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
// 玻璃化:材质底 + 半透明填充 + 发丝描边;悬停提亮 / 拖放目标品牌蓝

struct HandleColumn: View {
    @ObservedObject var controller: SidebarController
    @ObservedObject var state: AppState

    private var theme: ThemeColors { Theme.colors(dark: state.settings.themeIsDark) }

    private var fill: Color {
        if state.ui.handleDropTargeted { return theme.accent.opacity(0.78) }
        if state.ui.handleHovering { return Color.white.opacity(theme.isDark ? 0.18 : 0.62) }
        return Color.white.opacity(theme.isDark ? 0.10 : 0.44)
    }

    private var dotColor: Color {
        if state.ui.handleDropTargeted { return .white }
        return theme.isDark ? Color.white.opacity(0.55) : Color(hex: 0x1C202C, alpha: 0.48)
    }

    var body: some View {
        VStack(spacing: 4.5) {
            ForEach(0..<6, id: \.self) { _ in
                Circle().fill(dotColor).frame(width: 3, height: 3)
            }
        }
        .frame(width: SidebarController.handleWidth, height: SidebarController.handleHeight)
        .background(
            ZStack {
                VisualEffectBackground(dark: theme.isDark)
                RoundedRectangle(cornerRadius: 6).fill(fill)
                RoundedRectangle(cornerRadius: 6)
                    .fill(LinearGradient(colors: [Color.white.opacity(0.28), .clear],
                                         startPoint: .top, endPoint: .center))
                    .allowsHitTesting(false)
            }
            .overlay(RoundedRectangle(cornerRadius: 6)
                .strokeBorder(theme.isDark ? Color.white.opacity(0.14) : Color.white.opacity(0.55)))
            .shadow(color: .black.opacity(theme.isDark ? 0.40 : 0.22), radius: 6, x: -1, y: 2)
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

// MARK: - 面板主体(玻璃卡片 = 头部 + Tab 栏 + 内容 + 底部音乐卡)

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
            GlassPanelBackground(theme: theme,
                                 opacityScale: state.settings.backgroundOpacity)
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
            headerButton("gearshape", active: false, help: "设置") {
                NotificationCenter.default.post(name: .sideDockOpenSettings, object: nil)
            }
            headerButton(state.settings.pinned ? "pin.fill" : "pin",
                         active: state.settings.pinned,
                         help: state.settings.pinned ? "常驻模式(已固定,不自动收起)" : "点击固定面板") {
                state.settings.pinned.toggle()
            }
            headerButton("chevron.right", active: false, help: "收起侧边栏") {
                controller.collapse()
            }
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 5)
                .onChanged { v in controller.dragHandleBy(dy: v.translation.height) }
        )
    }

    /// 玻璃圆形图标钮(30×30,激活态品牌蓝玻璃)
    @ViewBuilder
    private func headerButton(_ symbol: String, active: Bool, help: String,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: active ? .semibold : .medium))
                .foregroundStyle(active ? theme.accent : theme.text2)
                .frame(width: 30, height: 30)
                .background(
                    Capsule().fill(active ? theme.accentSoft : theme.card)
                        .shadow(color: .black.opacity(theme.isDark ? 0.18 : 0.06), radius: 2, y: 1)
                )
                .overlay(Capsule().strokeBorder(active ? Color.clear : theme.border))
        }
        .buttonStyle(.plain)
        .help(help)
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

// SD 徽标(蓝渐变圆角方块 + 内顶高光 + 品牌蓝投影)
struct SDLogo: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 11)
                .fill(LinearGradient(colors: [Color(hex: 0x4A9EFF), Color(hex: 0x2F7BFF)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .shadow(color: Color(hex: 0x2F7BFF, alpha: 0.35), radius: 8, x: 0, y: 3)
            RoundedRectangle(cornerRadius: 11)
                .fill(LinearGradient(colors: [Color.white.opacity(0.30), Color.clear],
                                     startPoint: .top, endPoint: .center))
                .allowsHitTesting(false)
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
        .background(
            Capsule().fill(theme.bar)
                .shadow(color: .black.opacity(theme.isDark ? 0.15 : 0.04), radius: 2, y: 1)
        )
        .overlay(Capsule().strokeBorder(theme.border))
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
                        .monospacedDigit()
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(Capsule().fill(selected ? Color.white.opacity(0.25) : theme.accentSoft))
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
            // 选中胶囊:品牌蓝投影(设计稿 0 3 8 rgba(47,110,255,0.35))
            .shadow(color: selected ? theme.accent.opacity(theme.isDark ? 0.45 : 0.35) : .clear,
                    radius: selected ? 8 : 0, x: 0, y: selected ? 3 : 0)
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
                    let progress = max(0, min(1, snap.elapsed / max(snap.duration, 0.1)))
                    ZStack(alignment: .leading) {
                        Capsule().fill(theme.bar)
                        Capsule().fill(LinearGradient(colors: [theme.accent, Color(hex: 0x22D3EE)],
                                                      startPoint: .leading, endPoint: .trailing))
                            .frame(width: progress * geo.size.width)
                        // 玻璃滑块(8pt 白点)
                        Circle()
                            .fill(Color.white)
                            .frame(width: 8, height: 8)
                            .shadow(color: .black.opacity(0.30), radius: 2, y: 1)
                            .offset(x: progress * geo.size.width - 4)
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
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 16).fill(theme.card)
                RoundedRectangle(cornerRadius: 16)
                    .fill(LinearGradient(colors: [Color.white.opacity(theme.isDark ? 0.08 : 0.30), Color.clear],
                                         startPoint: .top, endPoint: .center))
                    .allowsHitTesting(false)
            }
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(theme.border))
            .shadow(color: .black.opacity(theme.isDark ? 0.18 : 0.07), radius: 4, y: 2)
        )
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
