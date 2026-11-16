// Views.swift — 五个面板内容(布局按原版 promoshot 渲染图还原)
// 注:命令行工具链无 SwiftUI 宏插件,瞬时状态统一存于 AppState.ui(UIState)。
import AppKit
import LocalAuthentication
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

// MARK: - 内容路由

struct PanelContent: View {
    @ObservedObject var state: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                switch state.settings.tab {
                case .todo: TodoTab(state: state)
                case .notes: NotesTab(state: state)
                case .downloads: DownloadsTab(state: state)
                case .shelf: ShelfTab(state: state)
                case .passwords: PasswordsTab(state: state)
                case .clipboard: MaccyClipboardList(state: state)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - 通用小组件

struct CountRow<Actions: View>: View {
    let title: String
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        HStack {
            Text(title).font(.system(size: 12)).foregroundStyle(Theme.colors(dark: AppState.shared.settings.themeIsDark).text2)
            Spacer()
            actions()
        }
    }
}

struct ActionLink: View {
    let title: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(color)
        }
        .buttonStyle(.plain)
    }
}

/// 蓝渐变胶囊按钮(渲染证据:笔记"+ 新建"、密码"+ 添加"都是实心胶囊白字)
struct PillButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        let theme = Theme.colors(dark: AppState.shared.settings.themeIsDark)
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                .padding(.horizontal, 14).padding(.vertical, 6)
                .background(Capsule().fill(LinearGradient(colors: [theme.accent, theme.accent2],
                                                          startPoint: .leading, endPoint: .trailing)))
                .shadow(color: theme.accent2.opacity(0.32), radius: 3, y: 1)
        }
        .buttonStyle(.plain)
    }
}

/// 分段控件(渲染证据:紧凑灰底圆角容器,左对齐;白底描边选中段,不横向铺满)
/// 颜色全部走主题 token:之前用 Color.primary/Color.white 这类动态系统色,
/// 深色窗口外观下会白字配白底直接隐形。
struct SegmentedBar: View {
    let options: [String]
    let selection: Int
    let onChange: (Int) -> Void

    private var theme: ThemeColors { Theme.colors(dark: AppState.shared.settings.themeIsDark) }
    // 渲染证据:浅色下选中段是白底描边;深色下用浅灰底,避免系统动态色白字白底
    private var dark: Bool { AppState.shared.settings.themeIsDark }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options.indices, id: \.self) { i in
                Button {
                    onChange(i)
                } label: {
                    Text(options[i])
                        .font(.system(size: 12, weight: i == selection ? .semibold : .regular))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(i == selection
                                      ? AnyShapeStyle(dark ? Color(hex: 0x3A3A3E) : Color.white)
                                      : AnyShapeStyle(Color.clear))
                                .overlay(RoundedRectangle(cornerRadius: 6)
                                    .stroke(i == selection
                                            ? (dark ? Color(hex: 0x4A4A4E) : Color(hex: 0xD6D6DA))
                                            : .clear, lineWidth: 1))
                                .shadow(color: .black.opacity(i == selection ? 0.08 : 0), radius: 2, y: 1)
                        )
                        .foregroundStyle(i == selection ? theme.text : theme.text2)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 8).fill(dark ? Color(hex: 0x262629) : Color(hex: 0xE4E4E7)))
    }
}

// MARK: - 待办(渲染证据:输入卡+蓝圆加号 / 到期胶囊 / 分组计数胶囊 / 圆形勾选行 + 逾期/提醒角标)

struct TodoTab: View {
    @ObservedObject var state: AppState
    @ObservedObject private var store = AppState.shared.todos

    private var theme: ThemeColors { Theme.colors(dark: state.settings.themeIsDark) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 输入卡(渲染证据:输入行 + 到期胶囊行同处一张灰卡内)
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    // nonactivatingPanel 上 onTapGesture 首点会被吞,统一用 Button
                    Button {
                        add()
                    } label: {
                        Circle()
                            .fill(LinearGradient(colors: [theme.accent, theme.accent2],
                                                 startPoint: .top, endPoint: .bottom))
                            .frame(width: 24, height: 24)
                            .overlay(Image(systemName: "plus").font(.system(size: 12, weight: .bold)).foregroundStyle(.white))
                    }
                    .buttonStyle(.plain)
                    .help("添加(回车亦可)")
                    TextField("添加待办，回车保存", text: state.uiBind(\.todoDraft))
                        .font(.system(size: 13))
                        .textFieldStyle(.plain)
                        .onSubmit(add)
                }
                // 到期预设(渲染证据:卡内一行"到期:" + 今日/明日/一周/历史,默认选中今日)
                HStack(spacing: 6) {
                    Text("到期：").font(.system(size: 12)).foregroundStyle(theme.text2)
                    presetPill("今日", 1)
                    presetPill("明日", 2)
                    presetPill("一周", 3)
                    presetPill("历史", 4)   // 跳到历史分组
                    Spacer()
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 12).fill(theme.card))

            // 分组筛选(渲染证据:今日/明日/一周/历史 四枚带计数胶囊,无"全部")
            HStack(spacing: 6) {
                groupPill("今日", 1, store.count(for: 1))
                groupPill("明日", 2, store.count(for: 2))
                groupPill("一周", 3, store.count(for: 3))
                groupPill("历史", 4, store.count(for: 4))
                Spacer()
            }

            let items = filtered
            if items.isEmpty {
                Text("暂无待办").font(.system(size: 12)).foregroundStyle(theme.text3)
                    .frame(maxWidth: .infinity).padding(.vertical, 18)
            }
            // 渲染证据:行间距比卡片间距更紧
            VStack(alignment: .leading, spacing: 6) {
                ForEach(items) { item in
                    todoRow(item)
                }
            }
        }
        .onAppear { store.requestAuthorization() }
    }

    private var filtered: [TodoItem] {
        store.items.filter { store.matches($0, filter: state.ui.todoFilter) }
    }

    @ViewBuilder
    private func presetPill(_ title: String, _ idx: Int) -> some View {
        let on = idx != 4 && state.ui.todoPreset == idx
        Button {
            if idx == 4 { state.ui.todoFilter = 4 }   // 历史:跳到历史分组
            else { state.ui.todoPreset = idx }
        } label: {
            Text(title)
                .font(.system(size: 11, weight: on ? .semibold : .regular))
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Capsule().fill(on
                    ? AnyShapeStyle(LinearGradient(colors: [theme.accent, theme.accent2], startPoint: .leading, endPoint: .trailing))
                    : AnyShapeStyle(theme.pill)))
                .foregroundStyle(on ? .white : theme.text)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func groupPill(_ title: String, _ idx: Int, _ count: Int) -> some View {
        let on = state.ui.todoFilter == idx
        Button {
            state.ui.todoFilter = idx
        } label: {
            // 渲染证据:计数是普通文字,不是小胶囊
            HStack(spacing: 3) {
                Text(title).font(.system(size: 11, weight: on ? .semibold : .regular))
                Text("\(count)").font(.system(size: 10, weight: .semibold))
            }
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(Capsule().fill(on
                ? AnyShapeStyle(LinearGradient(colors: [theme.accent, theme.accent2], startPoint: .leading, endPoint: .trailing))
                : AnyShapeStyle(theme.pill)))
            .foregroundStyle(on ? .white : theme.text)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func todoRow(_ item: TodoItem) -> some View {
        let hovering = state.ui.todoHover[item.id] ?? false
        HStack(spacing: 10) {
            Button {
                store.toggle(item.id)
            } label: {
                Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 17))
                    .foregroundStyle(item.done ? theme.accent : theme.text3)
            }
            .buttonStyle(.plain)

            Text(item.title)
                .font(.system(size: 14, weight: .medium))
                .strikethrough(item.done)
                .foregroundStyle(item.done ? theme.text3 : theme.text)

            Spacer()

            if item.done {
                Button { store.toggle(item.id) } label: {
                    Text("标记为未完成").font(.system(size: 10)).foregroundStyle(theme.text3)
                }
                .buttonStyle(.plain)
            } else if let due = item.due {
                if due < Date() {
                    Text("已逾期").font(.system(size: 11, weight: .medium)).foregroundStyle(theme.danger)
                } else if due < Date().addingTimeInterval(2 * 3600) {
                    // 渲染证据:只对 2 小时内即将到期的行显示铃铛时间
                    HStack(spacing: 2) {
                        Image(systemName: "bell.fill").font(.system(size: 9))
                        Text(due.formatted(date: .omitted, time: .shortened)).font(.system(size: 11))
                    }
                    .foregroundStyle(theme.accent)
                }
            }

            // 渲染证据:行上不常显删除按钮,悬停才出现
            if hovering {
                Button {
                    store.items.removeAll { $0.id == item.id }
                } label: {
                    Image(systemName: "xmark").font(.system(size: 9)).foregroundStyle(theme.text3.opacity(0.7))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 12).fill(theme.card))
        .contentShape(Rectangle())
        .onHover { state.ui.todoHover[item.id] = $0 }
    }

    private func add() {
        let text = state.ui.todoDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let due = TodoStore.dueDate(forPreset: state.ui.todoPreset)
        let item = TodoItem(title: text, due: due)
        store.add(text, due: due)
        state.ui.todoDraft = ""
        // 新增后跳到新条目所在分组,保证"添加立刻可见"(否则像没加上一样)
        state.ui.todoFilter = store.bucket(of: item)
    }
}

// MARK: - 笔记(渲染证据:"N 张" + 新建胶囊 / 标题+摘要+时间卡片)

struct NotesTab: View {
    @ObservedObject var state: AppState
    @ObservedObject private var store = AppState.shared.notes

    private var theme: ThemeColors { Theme.colors(dark: state.settings.themeIsDark) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CountRow(title: "\(store.notes.count) 张") {
                PillButton(title: "＋ 新建") { state.ui.notesAdding.toggle() }
            }

            if state.ui.notesAdding {
                HStack(spacing: 8) {
                    TextField("回车保存,首行为标题", text: state.uiBind(\.notesDraft))
                        .font(.system(size: 13)).onSubmit(addNote)
                    Button(action: addNote) {
                        Image(systemName: "arrow.up.circle.fill").font(.system(size: 18)).foregroundStyle(theme.accent)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 12).fill(theme.card))
            }

            if store.notes.isEmpty {
                Text("还没有笔记").font(.system(size: 12)).foregroundStyle(theme.text3)
                    .frame(maxWidth: .infinity).padding(.vertical, 18)
            }
            ForEach(store.notes) { note in
                let hovering = state.ui.notesHover[note.id] ?? false
                VStack(alignment: .leading, spacing: 3) {
                    Text(note.text.split(whereSeparator: \.isNewline).first.map(String.init) ?? note.text)
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(theme.text).lineLimit(1)
                    let body = note.text.split(whereSeparator: \.isNewline).dropFirst().joined(separator: " ")
                    if !body.isEmpty {
                        Text(body).font(.system(size: 11)).foregroundStyle(theme.text2).lineLimit(1)
                    }
                    HStack {
                        Text(note.createdAt.formatted(.relative(presentation: .named)))
                            .font(.system(size: 10)).foregroundStyle(theme.text3)
                        Spacer()
                        // 渲染证据:卡片上不常显删除按钮,悬停才出现
                        if hovering {
                            Button { store.notes.removeAll { $0.id == note.id } } label: {
                                Image(systemName: "xmark").font(.system(size: 9)).foregroundStyle(theme.text3.opacity(0.7))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 14).fill(theme.card))
                .contentShape(Rectangle())
                .onHover { state.ui.notesHover[note.id] = $0 }
            }
        }
    }

    private func addNote() {
        let text = state.ui.notesDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        store.notes.insert(Note(text: text), at: 0)
        state.ui.notesDraft = ""
        state.ui.notesAdding = false
    }
}

// MARK: - 下载(渲染证据:最近|全部 分段 + 搜索胶囊 + 文件夹按钮 / 今天、昨天分组行)

struct DownloadsTab: View {
    @ObservedObject var state: AppState
    @ObservedObject private var store = AppState.shared.downloads

    private var theme: ThemeColors { Theme.colors(dark: state.settings.themeIsDark) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                SegmentedBar(options: ["最近", "全部"], selection: state.ui.downloadsAll ? 1 : 0) {
                    state.ui.downloadsAll = ($0 == 1)
                    store.recentOnly = !state.ui.downloadsAll
                    store.refresh()
                }
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(theme.text3)
                    TextField("搜索", text: state.uiBind(\.downloadsSearch))
                        .font(.system(size: 12))
                        .textFieldStyle(.plain)
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Capsule().fill(theme.pill))
                Button {
                    NSWorkspace.shared.open(DownloadsStore.downloadsURL)
                } label: {
                    Image(systemName: "folder").font(.system(size: 13)).foregroundStyle(theme.text2)
                }
                .buttonStyle(.plain).help("打开下载文件夹")
            }

            if store.accessDenied {
                VStack(alignment: .leading, spacing: 6) {
                    Text("无法读取“下载”文件夹").font(.system(size: 12, weight: .semibold))
                    Text("请在 系统设置 → 隐私与安全性 → 文件与文件夹 中允许访问。")
                        .font(.system(size: 11)).foregroundStyle(theme.text2)
                    Button("打开系统设置") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.link).font(.system(size: 11))
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 12).fill(theme.danger.opacity(0.08)))
            } else if shown.isEmpty {
                Text(store.recentOnly ? "最近 3 天没有新下载" : "没有匹配的文件")
                    .font(.system(size: 12)).foregroundStyle(theme.text3)
                    .frame(maxWidth: .infinity).padding(.vertical, 18)
            } else {
                ForEach(grouped.keys.sorted(by: { $0.order < $1.order }), id: \.rawValue) { group in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(group.title).font(.system(size: 11, weight: .medium)).foregroundStyle(theme.text2)
                        ForEach(grouped[group] ?? []) { f in
                            DownloadRow(file: f, state: state, store: store)
                        }
                    }
                }
            }
        }
        .onAppear { store.startWatching() }
    }

    private var shown: [DownloadFile] {
        let q = state.ui.downloadsSearch.lowercased()
        return store.files.filter { q.isEmpty || $0.name.lowercased().contains(q) }
    }

    private var grouped: [DownloadGroup: [DownloadFile]] {
        var out: [DownloadGroup: [DownloadFile]] = [:]
        for f in shown {
            out[DownloadGroup.of(f.date), default: []].append(f)
        }
        return out
    }
}

enum DownloadGroup: String {
    case today = "今天", yesterday = "昨天", week = "本周", earlier = "更早"
    var title: String { rawValue }
    var order: Int {
        switch self {
        case .today: return 0
        case .yesterday: return 1
        case .week: return 2
        case .earlier: return 3
        }
    }
    static func of(_ date: Date) -> DownloadGroup {
        if Calendar.current.isDateInToday(date) { return .today }
        if Calendar.current.isDateInYesterday(date) { return .yesterday }
        if Date().timeIntervalSince(date) < 7 * 86400 { return .week }
        return .earlier
    }
}

struct DownloadRow: View {
    let file: DownloadFile
    @ObservedObject var state: AppState
    @ObservedObject var store: DownloadsStore

    private var theme: ThemeColors { Theme.colors(dark: state.settings.themeIsDark) }

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if let thumb = store.thumbs[file.id] {
                    Image(nsImage: thumb).resizable().aspectRatio(contentMode: .fill)
                } else {
                    Image(nsImage: ThumbnailProvider.shared.icon(for: file.url)).resizable().aspectRatio(contentMode: .fill)
                }
            }
            .frame(width: 40, height: 40)
            .clipShape(RoundedRectangle(cornerRadius: 9))
            .background(RoundedRectangle(cornerRadius: 9).fill(theme.pill))

            VStack(alignment: .leading, spacing: 2) {
                Text(file.name).lineLimit(1).truncationMode(.middle)
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(theme.text)
                HStack(spacing: 5) {
                    if file.isPartial {
                        Text("下载中…").font(.system(size: 10)).foregroundStyle(.orange)
                    }
                    Text(file.size >= 0 ? file.sizeText : "文件夹").font(.system(size: 10)).foregroundStyle(theme.text2)
                    Text("·").font(.system(size: 10)).foregroundStyle(theme.text3)
                    Text(file.date.formatted(.relative(presentation: .named)))
                        .font(.system(size: 10)).foregroundStyle(theme.text2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4).padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { store.open(file) }
        .contextMenu {
            Button("打开") { store.open(file) }
            Button("在 Finder 中显示") { store.reveal(file) }
            Divider()
            Button("移到废纸篓", role: .destructive) { store.trash(file) }
        }
        .draggable(file.url)
        .onAppear { store.loadThumb(for: file) }
    }
}

// MARK: - 暂存(文件货架;剪贴板已抽为独立 Tab,见 MaccyClipboardList)

struct ShelfTab: View {
    @ObservedObject var state: AppState
    @ObservedObject private var store = AppState.shared.shelf

    private var theme: ThemeColors { Theme.colors(dark: state.settings.themeIsDark) }

    var body: some View {
        filesSegment
    }

    // 文件:两列网格(渲染证据:64 图标 + 居中文件名)
    @ViewBuilder
    private var filesSegment: some View {
        VStack(alignment: .leading, spacing: 10) {
            CountRow(title: "\(store.items.count) 个文件") {
                ActionLink(title: "在 Finder 中显示", color: theme.accent) {
                    NSWorkspace.shared.activateFileViewerSelecting(store.items.map(\.url))
                }
                .disabled(store.items.isEmpty)
                ActionLink(title: "清空", color: theme.accent) { store.items.removeAll() }
                .disabled(store.items.isEmpty)
            }

            if store.items.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tray.and.arrow.down").font(.system(size: 24)).foregroundStyle(theme.text3)
                    Text("把文件拖到这里暂存").font(.system(size: 12)).foregroundStyle(theme.text3)
                    Text("暂存只记录文件位置,不会复制文件").font(.system(size: 10)).foregroundStyle(theme.text3.opacity(0.8))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .frame(height: 190)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1.2, dash: [5, 4]))
                        .foregroundStyle(state.ui.shelfDropTargeted ? theme.accent : theme.border)
                )
                .onDrop(of: [.fileURL], isTargeted: state.uiBind(\.shelfDropTargeted)) { providers in
                    for p in providers {
                        _ = p.loadObject(ofClass: URL.self) { url, _ in
                            guard let url else { return }
                            DispatchQueue.main.async { store.add(url) }
                        }
                    }
                    return true
                }
            } else {
                // 渲染证据:360pt 面板下文件网格为 3 列
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8),
                                    GridItem(.flexible(), spacing: 8)],
                          spacing: 8) {
                    ForEach(store.items) { item in
                        VStack(spacing: 6) {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: item.path))
                                .resizable().frame(width: 44, height: 44)
                            Text(item.url.lastPathComponent)
                                .font(.system(size: 11)).foregroundStyle(theme.text)
                                .lineLimit(2, reservesSpace: true)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12).padding(.horizontal, 8)
                        .background(RoundedRectangle(cornerRadius: 14).fill(theme.card))
                        .contentShape(Rectangle())
                        .draggable(item.url)
                        .contextMenu {
                            Button("在 Finder 中显示") {
                                NSWorkspace.shared.activateFileViewerSelecting([item.url])
                            }
                            Divider()
                            Button("从暂存中移除", role: .destructive) { store.remove(item.id) }
                        }
                    }
                }
            }
        }
    }

}

// MARK: - 剪贴板列表(仿 Maccy 2.8.0:搜索 / 固定区+分隔线 / 清除未固定 /
//      来源应用图标 / 键盘导航(↑↓/↩/Esc) / 选中即复制并粘贴到前台应用)

struct MaccyClipboardList: View {
    @ObservedObject var state: AppState
    @ObservedObject private var clips = AppState.shared.clipboard

    private var theme: ThemeColors { Theme.colors(dark: state.settings.themeIsDark) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 搜索(Maccy 占位文案证据:"搜索…";可清除)
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(theme.text3)
                TextField("搜索…", text: state.uiBind(\.clipSearch))
                    .textFieldStyle(.plain).font(.system(size: 12))
                if !state.ui.clipSearch.isEmpty {
                    Button {
                        state.ui.clipSearch = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11)).foregroundStyle(theme.text3)
                    }
                    .buttonStyle(.plain).help("清除搜索")
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Capsule().fill(theme.pill))

            // 标题行(Maccy:清除 = 清未固定;⇧/全部清除是增强)
            HStack(spacing: 8) {
                Text("\(clips.entries.count) 条 · 纯本地保存")
                    .font(.system(size: 11)).foregroundStyle(theme.text2)
                if let toast = state.ui.clipToast {
                    Text(toast).font(.system(size: 11, weight: .medium)).foregroundStyle(theme.accent)
                }
                Spacer(minLength: 0)
                ActionLink(title: "清除", color: theme.accent) { clips.clearUnpinned() }
                    .disabled(!clips.entries.contains(where: { !$0.isPinned }))
                ActionLink(title: "全部清除", color: theme.accent) {
                    clips.clearAll()
                    state.ui.clipSearch = ""
                    state.ui.clipSelectedIndex = nil
                }
                .disabled(clips.entries.isEmpty)
            }

            let rows = clips.visible(query: state.ui.clipSearch)
            if rows.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: state.ui.clipSearch.isEmpty ? "doc.on.clipboard" : "magnifyingglass")
                        .font(.system(size: 24)).foregroundStyle(theme.text3)
                    Text(state.ui.clipSearch.isEmpty ? "剪贴板还是空的" : "没有匹配的复制记录")
                        .font(.system(size: 12)).foregroundStyle(theme.text3)
                    if state.ui.clipSearch.isEmpty {
                        Text("在任何应用里复制文字,都会自动记录到这里")
                            .font(.system(size: 10)).foregroundStyle(theme.text3.opacity(0.8))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .frame(height: 150)
            } else {
                let pinnedCount = rows.filter(\.isPinned).count
                ForEach(rows.indices, id: \.self) { i in
                    if i == pinnedCount && pinnedCount > 0 && pinnedCount < rows.count {
                        Divider().opacity(0.5).padding(.vertical, 2)
                    }
                    clipRow(rows[i], index: i)
                }
            }
        }
        .onAppear { installKeyMonitor() }
        .onDisappear { removeKeyMonitor() }
    }

    // MARK: 行(点击 bug 修复:行主体用 Button,替代此前不可靠的 onTapGesture)
    // Maccy 行 = 来源应用图标 + 单行预览(换行折为空格)+ 固定标;悬浮显示操作;右键菜单

    @ViewBuilder
    private func clipRow(_ e: ClipEntry, index: Int) -> some View {
        let selected = state.ui.clipSelectedIndex == index
        let hovered = state.ui.clipHover[e.id] ?? false
        HStack(spacing: 0) {
            Button { select(e) } label: {
                HStack(spacing: 8) {
                    if e.isImage {
                        // 图片条目:直接显示缩略图(Maccy 同)
                        if let path = e.imagePath, let img = NSImage(contentsOfFile: path) {
                            Image(nsImage: img)
                                .resizable().aspectRatio(contentMode: .fill)
                                .frame(width: 36, height: 22)
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                                .overlay(RoundedRectangle(cornerRadius: 3)
                                    .strokeBorder(theme.border, lineWidth: 0.5))
                        } else {
                            Image(systemName: "photo")
                                .font(.system(size: 12)).foregroundStyle(theme.text3)
                        }
                    } else if let img = AppIconCache.icon(forBundle: e.sourceBundle) {
                        Image(nsImage: img).resizable().frame(width: 16, height: 16)
                    }
                    if !e.isImage {
                        Text(e.text.replacingOccurrences(of: "\n", with: " "))
                            .font(.system(size: 12)).lineLimit(1).truncationMode(.tail)
                            .foregroundStyle(theme.text)
                    }
                    Spacer(minLength: 0)
                    if e.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 9)).foregroundStyle(theme.accent)
                    }
                }
                .padding(.horizontal, 8).padding(.vertical, 7)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
        }
        .background(RoundedRectangle(cornerRadius: 8)
            .fill(selected ? theme.accent.opacity(0.15)
                           : (hovered ? Color.primary.opacity(0.06) : Color.clear)))
        .overlay(alignment: .trailing) {
            HStack(spacing: 2) {
                hoverButton(e.isPinned ? "pin.slash" : "pin",
                            e.isPinned ? "取消固定" : "固定") { clips.togglePin(e.id) }
                hoverButton("trash", "删除") { clips.remove(e.id) }
            }
            .padding(.trailing, 4)
            .opacity(hovered ? 1 : 0)
            .allowsHitTesting(hovered)
        }
        .onHover { state.ui.clipHover[e.id] = $0 }
        .contextMenu {
            Button("复制") { clips.copyBack(e) }
            Button("粘贴到最近应用") { select(e) }
            Divider()
            Button(e.isPinned ? "取消固定" : "固定") { clips.togglePin(e.id) }
            Button("删除", role: .destructive) { clips.remove(e.id) }
        }
        .help(e.text)
    }

    private func hoverButton(_ symbol: String, _ tip: String,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 9)).foregroundStyle(theme.text2)
                .padding(4)
                .background(Circle().fill(theme.bg.opacity(0.92)))
        }
        .buttonStyle(.plain)
        .help(tip)
    }

    // MARK: 选中(Maccy:回写剪贴板 → 按设置向前台应用模拟 ⌘V)

    private func select(_ e: ClipEntry) {
        clips.copyBack(e)
        state.ui.clipSelectedIndex = nil
        if state.settings.autoPasteEnabled {
            if AutoPaste.isTrusted {
                state.ui.clipToast = "已复制并粘贴"
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    AutoPaste.pasteToFrontmost()
                }
            } else {
                AutoPaste.promptForTrust()   // 引导系统设置授权(每次运行至多弹一次)
                state.ui.clipToast = "已复制(自动粘贴需授权辅助功能)"
            }
        } else {
            state.ui.clipToast = "已复制"
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { state.ui.clipToast = nil }
    }

    // MARK: 键盘导航(证据:_selectionIndex / _hoverSelectionWhileKeyboardNavigating)

    private func installKeyMonitor() {
        guard state.ui.clipKeyMonitor == nil else { return }
        state.ui.clipKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { ev in
            let ui = AppState.shared.ui
            guard AppState.shared.settings.tab == .clipboard else { return ev }
            let rows = AppState.shared.clipboard.visible(query: ui.clipSearch)
            guard !rows.isEmpty else { return ev }
            switch ev.keyCode {
            case 125:   // ↓
                ui.clipSelectedIndex = min((ui.clipSelectedIndex ?? -1) + 1, rows.count - 1)
                return nil
            case 126:   // ↑
                ui.clipSelectedIndex = max((ui.clipSelectedIndex ?? rows.count) - 1, 0)
                return nil
            case 36:    // ↩ 选中(无高亮则选第一个,同 Maccy)
                let idx = ui.clipSelectedIndex ?? 0
                if rows.indices.contains(idx) { select(rows[idx]) }
                return nil
            case 53:    // Esc 仅清高亮,不清搜索
                if ui.clipSelectedIndex != nil { ui.clipSelectedIndex = nil; return nil }
                return ev
            default:
                return ev
            }
        }
    }

    private func removeKeyMonitor() {
        if let m = state.ui.clipKeyMonitor {
            NSEvent.removeMonitor(m)
            state.ui.clipKeyMonitor = nil
        }
    }
}

// MARK: - 密码(渲染证据:"共 N 条" + 添加胶囊 / 浅蓝钥匙块 + 站点/账号 + 眼睛)

struct PasswordsTab: View {
    @ObservedObject var state: AppState
    @ObservedObject private var store = AppState.shared.vault

    private var theme: ThemeColors { Theme.colors(dark: state.settings.themeIsDark) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CountRow(title: "共 \(store.entries.count) 条") {
                PillButton(title: "＋ 添加") { state.ui.vaultAdding.toggle() }
            }

            if state.ui.vaultAdding {
                VStack(spacing: 6) {
                    TextField("网站 / 用途", text: state.uiBind(\.vaultSite))
                    TextField("手机号 / 邮箱 / 用户名", text: state.uiBind(\.vaultAccount))
                    TextField("绑定的手机号(可选)", text: state.uiBind(\.vaultPhone))
                    HStack {
                        SecureField("密码(留空 = 稍后在条目上补填)", text: state.uiBind(\.vaultPassword))
                        Button {
                            state.ui.vaultPassword = PasswordGenerator.generate()
                        } label: {
                            Image(systemName: "wand.and.stars").foregroundStyle(theme.accent)
                        }
                        .buttonStyle(.plain).help("生成随机强密码")
                    }
                    HStack {
                        Button("保存") { addEntry() }
                            .buttonStyle(.borderedProminent).controlSize(.small)
                            .disabled(state.ui.vaultSite.isEmpty || state.ui.vaultAccount.isEmpty)
                        Button("取消") {
                            state.ui.vaultAdding = false
                            state.ui.vaultSite = ""; state.ui.vaultAccount = ""
                            state.ui.vaultPhone = ""; state.ui.vaultPassword = ""
                        }
                        .controlSize(.small)
                        Spacer()
                    }
                }
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 12).fill(theme.card))
            }

            if let toast = state.ui.vaultToast {
                Text(toast).font(.system(size: 11)).foregroundStyle(.green)
            }

            if store.entries.isEmpty {
                Text("暂无保存的密码").font(.system(size: 12)).foregroundStyle(theme.text3)
                    .frame(maxWidth: .infinity).padding(.vertical, 18)
            }
            ForEach(store.entries) { e in
                vaultRow(e)
            }
        }
    }

    @ViewBuilder
    private func vaultRow(_ e: VaultEntry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(state.settings.themeIsDark ? theme.accent.opacity(0.18) : Color(hex: 0xDDEBFF))
                    Image(systemName: "key.fill").font(.system(size: 15)).foregroundStyle(theme.accent)
                }
                .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text(e.site).font(.system(size: 13, weight: .semibold)).foregroundStyle(theme.text)
                    Text(e.account).font(.system(size: 11)).foregroundStyle(theme.text2)
                }
                Spacer(minLength: 0)

                if state.ui.vaultRevealFor == e.id, let text = state.ui.vaultRevealText {
                    Text(text).font(.system(size: 11, design: .monospaced)).foregroundStyle(theme.text)
                        .lineLimit(1).truncationMode(.middle).frame(maxWidth: 120)
                }

                if !hasPassword(e) {
                    Text("未保存密码").font(.system(size: 9)).foregroundStyle(.orange)
                }

                Button { authenticateAndReveal(e) } label: {
                    Image(systemName: state.ui.vaultRevealFor == e.id ? "eye.slash" : "eye")
                        .font(.system(size: 13)).foregroundStyle(theme.text2)
                }
                .buttonStyle(.plain).help(hasPassword(e) ? "查看(需验证)" : "该条目添加时未填密码")
            }

            if state.ui.vaultEditingFor == e.id {
                HStack {
                    SecureField("重新输入密码", text: state.uiBind(\.vaultEditPassword))
                        .textFieldStyle(.roundedBorder).font(.system(size: 12))
                    Button("保存") {
                        try? store.updatePassword(e.id, state.ui.vaultEditPassword)
                        state.ui.vaultEditingFor = nil
                        state.ui.vaultEditPassword = ""
                    }
                    .controlSize(.small)
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(theme.card))
        .contextMenu {
            Button("右键编辑重新输入密码") { state.ui.vaultEditingFor = e.id }
            Divider()
            Button("删除这条记录", role: .destructive) { store.remove(e.id) }
        }
    }

    private func hasPassword(_ e: VaultEntry) -> Bool {
        Keychain.password(for: e.id.uuidString) != nil
    }

    private func addEntry() {
        var entry = VaultEntry(site: state.ui.vaultSite, account: state.ui.vaultAccount)
        entry.phone = state.ui.vaultPhone.isEmpty ? nil : state.ui.vaultPhone
        do {
            try store.add(entry, password: state.ui.vaultPassword.isEmpty ? nil : state.ui.vaultPassword)
            state.ui.vaultSite = ""; state.ui.vaultAccount = ""
            state.ui.vaultPhone = ""; state.ui.vaultPassword = ""
            state.ui.vaultAdding = false
        } catch {
            state.ui.vaultToast = "密码写入钥匙串失败"
        }
    }

    private func copyPassword(_ e: VaultEntry) {
        guard let pw = Keychain.password(for: e.id.uuidString) else {
            state.ui.vaultToast = "该条目添加时未填密码"
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(pw, forType: .string)
        state.clipboard.suppressNextPoll()
        state.ui.vaultToast = "已复制,去粘贴吧"
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { state.ui.vaultToast = nil }
    }

    private func authenticateAndReveal(_ e: VaultEntry) {
        guard let pw = Keychain.password(for: e.id.uuidString) else {
            state.ui.vaultToast = "未找到保存的密码"
            return
        }
        let ctx = LAContext()
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else {
            state.ui.vaultRevealFor = e.id
            state.ui.vaultRevealText = pw
            return
        }
        ctx.evaluatePolicy(.deviceOwnerAuthentication,
                           localizedReason: "验证以查看“\(e.site)”的密码") { success, _ in
            DispatchQueue.main.async {
                if success {
                    state.ui.vaultRevealFor = e.id
                    state.ui.vaultRevealText = pw
                    DispatchQueue.main.asyncAfter(deadline: .now() + 12) {
                        if state.ui.vaultRevealFor == e.id {
                            state.ui.vaultRevealFor = nil
                            state.ui.vaultRevealText = nil
                        }
                    }
                } else {
                    state.ui.vaultToast = "验证失败"
                }
            }
        }
    }
}

// MARK: - 设置(渲染证据:外观与行为 / 悬停自动展开 / 点击外部时不收起 / 常驻模式)

struct SettingsView: View {
    @ObservedObject var state: AppState

    var body: some View {
        Form {
            Section("外观与行为") {
                Picker("主题", selection: Binding(
                    get: { state.settings.themeMode },
                    set: { state.applyThemeMode($0) }
                )) {
                    ForEach(ThemeMode.allCases, id: \.self) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                HStack {
                    Text("背景不透明度")
                    Slider(value: state.ui.settingsBinding(\.backgroundOpacity), in: 0.4...1.0)
                    Text("\(Int(state.settings.backgroundOpacity * 100))%")
                        .monospacedDigit().frame(width: 40)
                }
                Text("跟随系统:随 macOS 浅色/深色外观自动切换;面板、设置窗口与菜单栏剪贴板同步生效")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("侧边栏") {
                Toggle("悬停自动展开", isOn: state.ui.settingsBinding(\.autoExpand))
                Toggle("常驻模式(不自动收起)", isOn: state.ui.settingsBinding(\.pinned))
                Toggle("点击外部时不收起", isOn: state.ui.settingsBinding(\.clickOutsideKeepsOpen))
                Toggle("显示货架条", isOn: state.ui.settingsBinding(\.shelfBarVisible))
                Button("恢复默认大小与位置") {
                    state.resetPanelGeometry()
                    NotificationCenter.default.post(name: .sideDockGeometryReset, object: nil)
                }
            }

            Section("剪贴板") {
                Toggle("选中历史项后自动粘贴到前台应用", isOn: Binding(
                    get: { state.settings.autoPasteEnabled },
                    set: { state.settings.autoPaste = $0 }
                ))
                Text("Maccy 式行为:点击历史项即复制,并向原前台应用模拟 ⌘V(需在系统设置授予辅助功能权限;未授权时仅复制)")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("应用内快捷键") {
                HotkeyRecorder(state: state)
                Text("侧边栏处于焦点时按下即收起")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("开机启动") {
                LaunchAtLoginToggle(state: state)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 400, minHeight: 480)
    }
}

extension UIState {
    /// Settings 结构字段的便捷绑定
    func settingsBinding<Value>(_ keyPath: WritableKeyPath<Settings, Value>) -> Binding<Value> {
        let app = AppState.shared
        return Binding(
            get: { app.settings[keyPath: keyPath] },
            set: { app.settings[keyPath: keyPath] = $0 }
        )
    }
}

struct LaunchAtLoginToggle: View {
    @ObservedObject var state: AppState

    var body: some View {
        Toggle("开机时启动", isOn: state.uiBind(\.launchAtLoginMirror))
            .onChange(of: state.ui.launchAtLoginMirror) { on in
                do {
                    if on { try SMAppService.mainApp.register() }
                    else { try SMAppService.mainApp.unregister() }
                } catch {
                    state.ui.launchAtLoginMirror.toggle()
                }
            }
            .onAppear {
                state.ui.launchAtLoginMirror = SMAppService.mainApp.status == .enabled
            }
    }
}

// MARK: - 快捷键录入(证据: HotkeyRecorder / recording)

struct HotkeyRecorder: View {
    @ObservedObject var state: AppState

    var body: some View {
        HStack {
            if let hk = state.settings.hotkey {
                Text(hk.display)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 6).fill(.primary.opacity(0.08)))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.15)))
            } else {
                Text("未设置").foregroundStyle(.secondary)
            }
            Button(state.ui.hotkeyRecording ? "按下快捷键…(Esc 取消)" : "录制") {
                state.ui.hotkeyRecording ? stopRecording() : startRecording()
            }
            if state.settings.hotkey != nil {
                Button("清除") { state.settings.hotkey = nil }
            }
        }
    }

    private func startRecording() {
        state.ui.hotkeyRecording = true
        state.ui.hotkeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 {
                stopRecording()
                return nil
            }
            let mods = event.modifierFlags.intersection([.command, .option, .control, .shift])
            guard !mods.isEmpty else { return event }
            state.settings.hotkey = Hotkey(keyCode: event.keyCode, modifiers: mods.rawValue)
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        state.ui.hotkeyRecording = false
        if let m = state.ui.hotkeyMonitor {
            NSEvent.removeMonitor(m)
            state.ui.hotkeyMonitor = nil
        }
    }
}
