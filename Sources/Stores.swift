// Stores.swift — 数据模型与各面板的存储层
// 证据: JSON 文件持久化(vault.json / todos / notes / shelf)、
//      SecItemCopyMatching(钥匙串)、生成随机强密码字符集
//      (abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789!@#$%&*? — 已去除易混淆字符)
import AppKit
import Combine
import Foundation
import Security
import UserNotifications

// MARK: - 通用 JSON 持久化

protocol JSONStore: AnyObject {
    var filename: String { get }
}

extension JSONStore {
    func loadJSON<T: Decodable>(_ type: T.Type) -> T? {
        let url = DataDir.file(filename)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
    func saveJSON<T: Encodable>(_ value: T) {
        let url = DataDir.file(filename)
        if let data = try? JSONEncoder().encode(value) {
            try? data.write(to: url, options: .atomic)
        }
    }
}

// MARK: - 钥匙串(证据: 存入钥匙串加密 / 仅本机可解密 / 密码写入钥匙串失败)

enum Keychain {
    static let service = "com.xiaohao003.SideDock.vault"
    // 项目由 SideDock 更名而来:旧服务名保留为一次性迁移来源
    // (拆开拼接避免与批量重命名冲突)
    static let legacyService = "local." + "sidedock" + "re.vault"

    static func setPassword(_ password: String, for account: String) throws {
        let data = Data(password.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        var attrs = query
        attrs[kSecValueData as String] = data
        attrs[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(attrs as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status),
                          userInfo: [NSLocalizedDescriptionKey: "密码写入钥匙串失败 (\(status))"])
        }
    }

    static func password(for account: String, service: String = Keychain.service) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func deletePassword(for account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - 随机强密码(证据字符集)

enum PasswordGenerator {
    static let fullCharset = Array("abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789!@#$%&*?")
    static let letterCharset = Array("abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ")

    static func generate(length: Int = 20, symbols: Bool = true) -> String {
        let charset = symbols ? fullCharset : letterCharset
        return String((0..<length).map { _ in charset.randomElement()! })
    }
}

// MARK: - 笔记(证据: 删除这张笔记 / 回车保存)

struct Note: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var text: String
    var createdAt: Date = Date()
}

final class NotesStore: ObservableObject, JSONStore {
    let filename = "notes.json"
    @Published var notes: [Note] = [] { didSet { saveJSON(notes) } }
    init() { notes = loadJSON([Note].self) ?? [] }
}

// MARK: - 待办(证据: 到点弹系统通知 / 标记为未完成 / 清除全部已完成)

struct TodoItem: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var title: String
    var due: Date?
    var done: Bool = false
    var doneAt: Date?
    var createdAt: Date = Date()
}

final class TodoStore: ObservableObject, JSONStore {
    let filename = "todos.json"
    @Published var items: [TodoItem] = [] { didSet { saveJSON(items); syncNotifications() } }

    init() { items = loadJSON([TodoItem].self) ?? [] }

    func add(_ title: String, due: Date?) {
        items.append(TodoItem(title: title, due: due))
    }

    func toggle(_ id: UUID) {
        if let i = items.firstIndex(where: { $0.id == id }) {
            items[i].done.toggle()
            items[i].doneAt = items[i].done ? Date() : nil
        }
    }

    func clearCompleted() {
        items.removeAll { $0.done }
    }

    private func syncNotifications() {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        let pending = items.filter { !$0.done && $0.due.map { $0 > Date() } == true }
        guard !pending.isEmpty else { return }
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
            DispatchQueue.main.async {
                for item in pending {
                    let content = UNMutableNotificationContent()
                    content.title = "待办提醒"
                    content.body = item.title
                    content.sound = .default
                    let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: item.due!)
                    let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
                    let request = UNNotificationRequest(identifier: item.id.uuidString, content: content, trigger: trigger)
                    center.add(request)
                }
            }
        }
    }

    func requestAuthorization() {
        // 证据: requestAuthorizationWithOptions:completionHandler:
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }
}

// MARK: - 暂存货架(证据: 暂存只记录文件位置 / 不会复制文件 / 从暂存中移除)

struct ShelfItem: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var path: String
    var addedAt: Date = Date()
    var url: URL { URL(fileURLWithPath: path) }
}

final class ShelfStore: ObservableObject, JSONStore {
    let filename = "shelf.json"
    @Published var items: [ShelfItem] = [] { didSet { saveJSON(items) } }
    init() { items = loadJSON([ShelfItem].self) ?? [] }

    func add(_ url: URL) {
        guard !items.contains(where: { $0.path == url.path }) else { return }
        items.insert(ShelfItem(path: url.path), at: 0)
    }

    func remove(_ id: UUID) { items.removeAll { $0.id == id } }
}

// MARK: - 密码保险库(证据: vault.json + 钥匙串 / 留空=稍后在条目上补填 / 右键编辑重新输入一次)

struct VaultEntry: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var site: String        // 网站 / 用途
    var account: String     // 手机号 / 邮箱 / 用户名
    var phone: String?      // 绑定的手机号(可选)
    var note: String?
    var createdAt: Date = Date()
}

final class VaultStore: ObservableObject, JSONStore {
    let filename = "vault.json"
    @Published var entries: [VaultEntry] = [] { didSet { saveJSON(entries) } }
    init() {
        entries = loadJSON([VaultEntry].self) ?? []
        migrateLegacyPasswords()
    }

    /// 更名迁移:旧钥匙串服务里的密码补写到新服务(仅缺失时)
    private func migrateLegacyPasswords() {
        for e in entries {
            if Keychain.password(for: e.id.uuidString) == nil,
               let pw = Keychain.password(for: e.id.uuidString, service: Keychain.legacyService) {
                try? Keychain.setPassword(pw, for: e.id.uuidString)
            }
        }
    }

    var hasPasswords: Bool {
        entries.contains { Keychain.password(for: $0.id.uuidString) != nil }
    }

    func add(_ e: VaultEntry, password: String?) throws {
        entries.insert(e, at: 0)
        if let password, !password.isEmpty {
            try Keychain.setPassword(password, for: e.id.uuidString)
        }
    }

    func updatePassword(_ id: UUID, _ password: String) throws {
        guard entries.contains(where: { $0.id == id }) else { return }
        try Keychain.setPassword(password, for: id.uuidString)
    }

    func remove(_ id: UUID) {
        entries.removeAll { $0.id == id }
        Keychain.deletePassword(for: id.uuidString)
    }
}

// MARK: - 剪贴板历史(仿 Maccy 2.8.0,REA 逆向证据:
//   类名 Clipboard/History/HistoryItem/PinManager/Search/Sorter/ApplicationImageCache;
//   选择器 checkForChangesInPasteboard + changeCount + scheduledTimer(轮询 watcher)、
//   _filteredPinnedItems/_filteredUnpinnedItems(固定/未固定双列表)、
//   _searchQuery + fuzzySearchLimit(模糊搜索)、_selectionIndex + 
//   _hoverSelectionWhileKeyboardNavigating(键盘导航)、frontmostApplication(来源应用);
//   zh 文案:清除="清除未置顶的项目,按住⇧以全部清除"、清除前确认弹窗、
//   每项"固定/取消固定/删除"、搜索占位"搜索…"、来源图标键 appIcon)

struct ClipEntry: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var text: String
    var copiedAt: Date = Date()
    // 以下为 Maccy 行为字段(optional 保证旧 JSON 兼容)
    var pinned: Bool?          // 置顶(PinManager)
    var pinnedAt: Date?
    var sourceBundle: String?  // 复制时的前台应用(frontmostApplication)
    var sourceName: String?

    var isPinned: Bool { pinned ?? false }
}

final class ClipboardStore: ObservableObject, JSONStore {
    let filename = "clipboard.json"
    /// 上限(Maccy 默认更大;本实现取 200 平衡性能)
    static let cap = 200
    @Published var entries: [ClipEntry] = [] { didSet { saveJSON(entries) } }

    private var timer: Timer?
    private var lastChangeCount: Int = 0

    init() { entries = loadJSON([ClipEntry].self) ?? [] }

    func startWatching() {
        guard timer == nil else { return }
        lastChangeCount = NSPasteboard.general.changeCount
        timer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { [weak self] _ in
            self?.poll()
        }
    }

    private func poll() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastChangeCount else { return }
        lastChangeCount = pb.changeCount
        guard let text = pb.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { return }
        // 来源应用(Maccy: frontmostApplication;跳过自身)
        let front = NSWorkspace.shared.frontmostApplication
        let bundle = front?.bundleIdentifier
        let name = front?.localizedName
        let trimmed = String(text.prefix(4000))

        // 去重:已有相同内容 → 移到顶部;已固定的留在固定区并刷新时间
        if let idx = entries.firstIndex(where: { $0.text == trimmed }) {
            let wasPinned = entries[idx].isPinned
            entries.remove(at: idx)
            if wasPinned {
                entries.append(ClipEntry(text: trimmed, copiedAt: Date(), pinned: true,
                                         pinnedAt: Date(), sourceBundle: bundle, sourceName: name))
            } else {
                entries.insert(ClipEntry(text: trimmed, copiedAt: Date(), pinned: nil,
                                         pinnedAt: nil, sourceBundle: bundle, sourceName: name), at: 0)
            }
        } else {
            entries.insert(ClipEntry(text: trimmed, copiedAt: Date(), pinned: nil,
                                     pinnedAt: nil, sourceBundle: bundle, sourceName: name), at: 0)
        }
        normalize()
    }

    /// 规范化:固定项(任意序)+ 未固定(新→旧),未固定超过 cap 裁剪
    private func normalize() {
        let pinned = entries.filter(\.isPinned)
        var rest = entries.filter { !$0.isPinned }
        if rest.count > Self.cap { rest = Array(rest.prefix(Self.cap)) }
        entries = pinned + rest
    }

    func copyBack(_ entry: ClipEntry) {
        // Maccy: 选中项 → 回写系统剪贴板
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(entry.text, forType: .string)
        lastChangeCount = NSPasteboard.general.changeCount // 避免自记
    }

    /// 复制密码等场景下,避免下一次轮询把剪贴板内容记录为剪贴板历史
    func suppressNextPoll() {
        lastChangeCount = NSPasteboard.general.changeCount
    }

    // MARK: PinManager 行为

    func togglePin(_ id: UUID) {
        guard let i = entries.firstIndex(where: { $0.id == id }) else { return }
        if entries[i].isPinned {
            entries[i].pinned = nil
            entries[i].pinnedAt = nil
        } else {
            entries[i].pinned = true
            entries[i].pinnedAt = Date()
        }
        normalize()
    }

    // MARK: 清除(zh 文案证据:"清除未置顶的项目,按住⇧以全部清除")

    func clearUnpinned() {
        entries.removeAll { !$0.isPinned }
    }

    func clearAll() {
        entries.removeAll()
    }

    // MARK: 搜索(Search + fuzzySearchLimit;本实现用包含匹配)

    func visible(query: String) -> [ClipEntry] {
        let q = query.lowercased()
        let match = { (e: ClipEntry) in q.isEmpty || e.text.lowercased().contains(q) }
        let pinned = entries.filter { $0.isPinned && match($0) }
            .sorted { ($0.pinnedAt ?? .distantPast) > ($1.pinnedAt ?? .distantPast) }
        let rest = entries.filter { !$0.isPinned && match($0) }
        return pinned + rest
    }

    func remove(_ id: UUID) {
        entries.removeAll { $0.id == id }
    }
}
