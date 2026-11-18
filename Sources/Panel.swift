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
        isMovable = true
        isMovableByWindowBackground = true   // 点击空白拖动移动窗口(控件/列表照常交互)
        hidesOnDeactivate = false
        hasShadow = false   // 圆角卡片自带投影
        isReleasedWhenClosed = false
        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
    }
}

// MARK: - 面板宿主视图(原生文件拖放)

/// 拖放目的地挂在宿主视图层(AppKit 沿 superview 链向上找注册视图,宿主是
/// 所有 SwiftUI 内容的祖先);直读拖拽剪贴板,多文件一次全收。
final class SideDockHostingView: NSHostingView<PanelRootView> {
    var acceptsFileDrop: () -> Bool = { false }   // 仅暂存页接收
    var onFilesDropped: (([URL]) -> Void)?
    var onDropTargeted: ((Bool) -> Void)?
    // 边缘/角缩放:命中 6pt 边带时由宿主接管鼠标(AppKit 沿 superview 链向上找
    // 命中视图,宿主是 SwiftUI 内容的祖先,边带覆盖面板全部四边四角)
    var isExpandedCheck: () -> Bool = { true }
    var onGeometryChanged: ((NSRect) -> Void)?
    var onInteraction: ((Bool) -> Void)?   // 缩放进行中(挂起悬停自动收起)

    static let band: CGFloat = 6

    struct ResizeDirs: OptionSet {
        let rawValue: UInt8
        static let left = ResizeDirs(rawValue: 1 << 0)
        static let right = ResizeDirs(rawValue: 1 << 1)
        static let top = ResizeDirs(rawValue: 1 << 2)
        static let bottom = ResizeDirs(rawValue: 1 << 3)
    }
    private var resizeDirs: ResizeDirs = []
    private var resizeStart: (loc: NSPoint, frame: NSRect)?

    required init(rootView: PanelRootView) {
        super.init(rootView: rootView)
        registerForDraggedTypes([.fileURL])
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .cursorUpdate, .activeAlways, .inVisibleRect],
            owner: self))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: 边缘/角命中

    /// 面板卡片可见矩形(本视图坐标)。窗口 frame 与卡片不重合:卡片四周有
    /// 14pt 内边距,右侧另有 12pt 把手列 + 5pt 间距 —— 缩放边带必须贴卡片
    /// 的边和角,否则右侧两角落在把手上、左侧两角落在透明 padding,全点不中。
    var cardFrame: (() -> CGRect)? = nil

    private func resizeDirs(atPoint p: NSPoint) -> ResizeDirs {
        guard let card = cardFrame?() ?? nil else { return [] }
        let dLeft = p.x - card.minX
        let dRight = card.maxX - p.x
        let dTop = isFlipped ? p.y - card.minY : card.maxY - p.y
        let dBottom = isFlipped ? card.maxY - p.y : p.y - card.minY
        let B = Self.band
        var dirs: ResizeDirs = []
        if dLeft >= 0, dLeft <= B { dirs.insert(.left) }
        if dRight >= 0, dRight <= B { dirs.insert(.right) }
        if dTop >= 0, dTop <= B { dirs.insert(.top) }
        if dBottom >= 0, dBottom <= B { dirs.insert(.bottom) }
        return dirs
    }

    private func dirsAtWindowLocation(_ loc: NSPoint) -> ResizeDirs {
        resizeDirs(atPoint: convert(loc, from: nil))
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // 收起态(12×96 把手)不接管:把手按钮照常工作
        guard isExpandedCheck() else { return super.hitTest(point) }
        let p = superview.map { convert(point, from: $0) } ?? point
        return resizeDirs(atPoint: p).isEmpty ? super.hitTest(point) : self
    }

    override func cursorUpdate(with event: NSEvent) {
        let dirs = dirsAtWindowLocation(event.locationInWindow)
        // macOS 未公开对角缩放光标,四角用十字光标代替
        let cursor: NSCursor?
        switch (dirs.contains(.left), dirs.contains(.right), dirs.contains(.top), dirs.contains(.bottom)) {
        case (true, false, true, false), (false, true, false, true),
             (false, true, true, false), (true, false, false, true): cursor = NSCursor.crosshair
        case (true, false, false, false), (false, true, false, false): cursor = NSCursor.resizeLeftRight
        case (false, false, true, false), (false, false, false, true): cursor = NSCursor.resizeUpDown
        default: cursor = nil
        }
        if let cursor { cursor.set() } else { super.cursorUpdate(with: event) }
    }

    // MARK: 缩放拖拽(窗口基础坐标,y 向上)

    override func mouseDown(with event: NSEvent) {
        let dirs = dirsAtWindowLocation(event.locationInWindow)
        guard !dirs.isEmpty, let win = window else { return super.mouseDown(with: event) }
        resizeDirs = dirs
        resizeStart = (event.locationInWindow, win.frame)
        onInteraction?(true)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = resizeStart, let win = window, !resizeDirs.isEmpty else {
            return super.mouseDragged(with: event)
        }
        let dx = event.locationInWindow.x - start.loc.x
        let dy = event.locationInWindow.y - start.loc.y
        var f = start.frame
        let clampedW = { Swift.min(Swift.max($0, SidebarController.minPanelWidth), SidebarController.maxPanelWidth) }
        let clampedH = { Swift.min(Swift.max($0, SidebarController.minPanelHeight), SidebarController.maxPanelHeight) }
        if resizeDirs.contains(.left) {
            let w = clampedW(start.frame.width - dx)
            f.origin.x = start.frame.maxX - w
            f.size.width = w
        }
        if resizeDirs.contains(.right) {
            f.size.width = clampedW(start.frame.width + dx)
        }
        if resizeDirs.contains(.top) {
            f.size.height = clampedH(start.frame.height + dy)
        }
        if resizeDirs.contains(.bottom) {
            let h = clampedH(start.frame.height - dy)
            f.origin.y = start.frame.maxY - h
            f.size.height = h
        }
        // 夹回可见区域,避免拖出屏幕够不着
        let vis = SidebarController.visibleFrame()
        f.origin.x = Swift.min(Swift.max(f.origin.x, vis.minX - f.width + 12), vis.maxX - 12)
        f.origin.y = Swift.min(Swift.max(f.origin.y, vis.minY - f.height + 12), vis.maxY - 12)
        win.setFrame(f, display: true, animate: false)
    }

    override func mouseUp(with event: NSEvent) {
        if !resizeDirs.isEmpty, let win = window {
            onGeometryChanged?(win.frame)
            resizeDirs = []
            resizeStart = nil
            onInteraction?(false)
            return
        }
        super.mouseUp(with: event)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let types = sender.draggingPasteboard.types?.map(\.rawValue) ?? []
        let ok = acceptsFileDrop() && hasFileURL(sender)
        NSLog("[drop] entered types=[%@] accepts=%@", types.joined(separator: ","), ok ? "Y" : "N")
        guard ok else { return [] }
        onDropTargeted?(true)
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard acceptsFileDrop(), hasFileURL(sender) else { return [] }
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        onDropTargeted?(false)
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        onDropTargeted?(false)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        onDropTargeted?(false)
        guard acceptsFileDrop() else { return false }
        let pb = sender.draggingPasteboard
        let types = pb.types?.map(\.rawValue) ?? []
        let items = pb.pasteboardItems?.count ?? 0
        var urls = pb.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        // 兜底:Finder 多文件一定写 NSFilenamesPboardType(Apple 文件列表,一次全量);
        // NSURL 读取在某些拖拽源上会少读,以文件列表为准
        let fileList = pb.propertyList(forType: NSPasteboard.PasteboardType("NSFilenamesPboardType"))
            as? [String] ?? []
        if urls.count < fileList.count {
            urls = fileList.map { URL(fileURLWithPath: $0) }
        }
        NSLog("[drop] perform types=[%@] items=%d filelist=%d nsurls=%d final=%d",
              types.joined(separator: ","), items, fileList.count, urls.count,
              urls.count)
        for u in urls { NSLog("[drop]   -> %@", u.path) }
        guard !urls.isEmpty else { return false }
        onFilesDropped?(urls)
        return true
    }

    private func hasFileURL(_ sender: NSDraggingInfo) -> Bool {
        sender.draggingPasteboard.types?.contains(.fileURL) ?? false
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
        // 用自定义宿主视图(而非 NSHostingController)以便在祖先层注册原生文件拖放:
        // AppKit 拖放目的地查找是"命中视图 → 沿 superview 链向上找注册视图",
        // 挂在宿主层才能覆盖暂存页任意位置(含已有文件的网格),且直读拖拽
        // 剪贴板可一次拿到全部文件 URL(SwiftUI onDrop/NSItemProvider 在 macOS
        // 多文件时只回调首个 provider,旧实现还只挂在空状态上)
        let hostingView = SideDockHostingView(rootView: PanelRootView(state: state, controller: self))
        hostingView.acceptsFileDrop = { [weak self] in self?.state.settings.tab == .shelf }
        hostingView.onFilesDropped = { [weak self] urls in self?.state.shelf.add(urls) }
        hostingView.onDropTargeted = { [weak self] targeted in
            guard let self else { return }
            self.state.ui.shelfDropTargeted = targeted && self.state.settings.tab == .shelf
        }
        hostingView.isExpandedCheck = { [weak self] in self?.isExpanded ?? false }
        hostingView.onGeometryChanged = { [weak self] frame in self?.persistGeometry(frame) }
        hostingView.onInteraction = { [weak self] on in self?.setInteracting(on) }
        // 卡片可见矩形:左/上/下 14pt 内边距 + 右侧 12pt 把手列 + 5pt 间距(与 PanelBody 布局一致)
        hostingView.cardFrame = { [weak hostingView] in
            guard let v = hostingView, !v.bounds.isEmpty else { return .zero }
            let b = v.bounds
            return NSRect(x: b.minX + 14, y: b.minY + 14,
                          width: b.width - 14 - 17, height: b.height - 28)
        }
        panel.contentView = hostingView

        // 拖动空白移动窗口(isMovableByWindowBackground)后持久化原点
        NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification, object: panel, queue: .main
        ) { [weak self] _ in
            guard let self, self.isExpanded else { return }
            var s = self.state.settings
            s.panelOriginX = Double(self.panel.frame.origin.x)
            s.panelOriginY = Double(self.panel.frame.origin.y)
            self.state.settings = s
        }

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

    static func visibleFrame() -> NSRect {
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
        // 用户拖动/缩放过(panelOriginX/Y) → 按存储原点自由定位;否则停靠右缘
        if let x = settings.panelOriginX, let y = settings.panelOriginY {
            let cx = min(max(x, vis.minX - w + 12), max(vis.minX, vis.maxX - 12))
            let cy = min(max(y, vis.minY - h + 12), max(vis.minY, vis.maxY - 12))
            return NSRect(x: cx, y: cy, width: w, height: h)
        }
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

    /// 缩放结束(宿主视图 mouseUp)后落盘尺寸与原点
    private func persistGeometry(_ frame: NSRect) {
        guard isExpanded else { return }
        var s = state.settings
        s.panelWidth = Double(frame.width)
        s.panelHeight = Double(frame.height)
        s.panelOriginX = Double(frame.origin.x)
        s.panelOriginY = Double(frame.origin.y)
        state.settings = s
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

    /// 展开后鼠标移出面板 → 延迟收起(常驻模式下不收起)。
    /// 拖拽缩放/移动窗口期间必须挂起:边缘拖动时光标会瞬间"出面板",
    /// 不挂起会 1.2s 后把面板打回把手(用户实测"角上不能缩放/挪不动"的根因)
    func panelHoverChanged(_ entered: Bool) {
        if isUserInteracting {
            cancelExitCollapse()
            return
        }
        guard isExpanded, state.settings.autoExpand, !state.settings.pinned else { return }
        cancelExitCollapse()
        if !entered {
            exitCollapseTimer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: false) { [weak self] _ in
                guard let self, !self.state.settings.pinned, !self.isUserInteracting else { return }
                self.collapse()
            }
        }
    }

    private func cancelExitCollapse() { exitCollapseTimer?.invalidate(); exitCollapseTimer = nil }

    // MARK: 位置与尺寸

    /// 收起态把手:上下拖动调位置(沿右缘)
    func dragHandleBy(dy: CGFloat) {
        state.settings.handleCenterY += dy
        applyGeometry(animated: false)
    }

    // MARK: 自由移动窗口(头部拖动 / 展开态把手拖动)

    /// 拖拽窗口进行中(悬停自动收起挂起)
    var isUserInteracting = false
    private var windowDragStart: (mouse: NSPoint, origin: NSPoint)?

    func beginWindowDrag() {
        guard windowDragStart == nil else { return }
        isUserInteracting = true
        cancelExitCollapse()
        windowDragStart = (NSEvent.mouseLocation, panel.frame.origin)
    }

    func windowDragStep() {
        guard let s = windowDragStart else { return }
        let m = NSEvent.mouseLocation
        panel.setFrameOrigin(NSPoint(x: s.origin.x + (m.x - s.mouse.x),
                                     y: s.origin.y + (m.y - s.mouse.y)))
    }

    func endWindowDrag() {
        guard windowDragStart != nil else { return }
        windowDragStart = nil
        isUserInteracting = false
        var s = state.settings
        s.panelOriginX = Double(panel.frame.origin.x)
        s.panelOriginY = Double(panel.frame.origin.y)
        state.settings = s
    }

    /// 宿主视图缩放边带的交互起止(同样挂起自动收起)
    func setInteracting(_ on: Bool) {
        isUserInteracting = on
        if on { cancelExitCollapse() }
    }
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
                .onChanged { v in
                    if controller.isExpanded {
                        // 展开态拖把手 = 自由移动整个窗口(与头部拖动一致)
                        controller.beginWindowDrag()
                        controller.windowDragStep()
                    } else {
                        controller.dragHandleBy(dy: v.translation.height)
                    }
                }
                .onEnded { _ in controller.endWindowDrag() }
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
        VStack(alignment: .leading, spacing: 12) {
            PanelHeader(state: state, controller: controller)
            PanelTabBar(state: state)
            PanelContent(state: state)
                .frame(maxWidth: .infinity)
                .frame(maxHeight: .infinity)
            MusicCard(state: state)
        }
        .padding(14)
        .padding(.trailing, 5)   // 与右缘把手留出间距
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(theme.bg)
                .shadow(color: .black.opacity(0.28), radius: 18, x: -3, y: 4)
        )
        // 边缘/角缩放已由宿主视图(SideDockHostingView)的 8 向边带统一处理,
        // 旧 SwiftUI ResizeEdge/ResizeCorner 覆盖条与边带抢事件且角部数学不对,移除
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
                .frame(width: 34, height: 34)
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
        // 头部即拖动条:按住拖动把窗口移到任意位置(按钮点击不受影响,
        // 拖动需 5pt 位移才触发);旧的"沿右缘上下移动"手势改为自由移动
        .gesture(
            DragGesture(minimumDistance: 5)
                .onChanged { _ in
                    controller.beginWindowDrag()
                    controller.windowDragStep()
                }
                .onEnded { _ in controller.endWindowDrag() }
        )
        .help("按住拖动移动面板")
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
            RoundedRectangle(cornerRadius: 9)
                .fill(LinearGradient(colors: [Color(hex: 0x4A9EFF), Color(hex: 0x2F7BFF)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            Text("SD").font(.system(size: 12, weight: .heavy, design: .rounded)).foregroundStyle(.white)
        }
    }
}

// MARK: Tab 栏(渲染证据:5 个独立胶囊左对齐排列,选中蓝→青渐变胶囊白字,
// 未选中灰底胶囊深色文字;待办/暂存/密码带白底蓝字数字徽章)

struct PanelTabBar: View {
    @ObservedObject var state: AppState

    private var theme: ThemeColors { Theme.colors(dark: state.settings.themeIsDark) }

    var body: some View {
        // 6 个 Tab:默认 472pt 宽度下正好放下;更窄(最小 360)时横向滚动兜底,
        // 选中项自动滚入可视区
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    tabButton(.todo, badge: pendingTodoCount)
                    tabButton(.notes, badge: nil)
                    tabButton(.downloads, badge: nil)
                    tabButton(.shelf, badge: state.shelf.items.count)
                    tabButton(.passwords, badge: state.vault.entries.count)
                    tabButton(.clipboard, badge: state.clipboard.entries.count)
                }
            }
            .onChange(of: state.settings.tab) { tab in
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(tab, anchor: .center) }
            }
        }
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
                    .lineLimit(1).fixedSize()
                if let badge, badge > 0 {
                    Text("\(badge)")
                        .font(.system(size: 8, weight: .bold))
                        .frame(width: 13, height: 13)
                        .background(Circle().fill(Color.white.opacity(0.92)))
                        .foregroundStyle(theme.accent)
                }
            }
            .fixedSize()
            .padding(.horizontal, 8).padding(.vertical, 4)
            .id(tab)
            .background(
                Capsule().fill(selected
                               ? AnyShapeStyle(LinearGradient(colors: [theme.accent, theme.accent2],
                                                              startPoint: .leading, endPoint: .trailing))
                               : AnyShapeStyle(theme.pill))
            )
            .shadow(color: selected ? theme.accent2.opacity(0.35) : .clear, radius: 4, y: 2)
            .foregroundStyle(selected ? .white : theme.text)
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
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(LinearGradient(colors: [Color(hex: 0x4A9EFF), Color(hex: 0x2F7BFF)],
                                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                                Image(systemName: "music.note").foregroundStyle(.white).font(.system(size: 20))
                            }
                        }
                    }
                    .frame(width: 52, height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(snap.title).font(.system(size: 15, weight: .semibold)).foregroundStyle(theme.text)
                            .lineLimit(1)
                        Text([snap.artist, snap.album].filter { !$0.isEmpty }.joined(separator: " — "))
                            .font(.system(size: 12)).foregroundStyle(theme.text2).lineLimit(1)
                        Text(snap.app).font(.system(size: 11)).foregroundStyle(theme.text3)
                    }
                    Spacer(minLength: 0)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.10))
                        Capsule().fill(LinearGradient(colors: [theme.accent, theme.accent2],
                                                      startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(0, min(1, snap.elapsed / max(snap.duration, 0.1))) * geo.size.width)
                    }
                }
                .frame(height: 4)
                HStack {
                    Text(timeString(snap.elapsed)).font(.system(size: 10)).foregroundStyle(theme.text3)
                    Spacer()
                    // 渲染证据:右侧时间 = 曲目总时长(无负号)
                    Text(timeString(max(0, snap.duration))).font(.system(size: 10)).foregroundStyle(theme.text3)
                }
                HStack(spacing: 56) {
                    Button { music.send(.previous) } label: {
                        Image(systemName: "backward.fill").font(.system(size: 16)).foregroundStyle(theme.text)
                    }
                    Button { music.send(.toggle) } label: {
                        Image(systemName: snap.playing ? "pause.fill" : "play.fill")
                            .font(.system(size: 20)).foregroundStyle(theme.text)
                    }
                    Button { music.send(.next) } label: {
                        Image(systemName: "forward.fill").font(.system(size: 16)).foregroundStyle(theme.text)
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

// MARK: - 边缘拖拽调整大小(由宿主视图边带处理,见 SideDockHostingView)

extension Notification.Name {
    static let sideDockGeometryReset = Notification.Name("sideDockGeometryReset")
    static let sideDockOpenSettings = Notification.Name("sideDockOpenSettings")
}
