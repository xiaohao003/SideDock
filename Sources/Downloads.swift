// Downloads.swift — 下载文件夹监控 + QuickLook 缩略图
// 证据: contentsOfDirectoryAtURL: / .crdownload / stringFromByteCount: /
//      activateFileViewerSelectingURLs: / trashItemAtURL: /
//      generateBestRepresentationForRequest: (QLThumbnailGenerator) /
//      _accessDenied + “请在 系统设置 隐私与安全性 文件与文件夹 中允许…”
import AppKit
import Combine
import Foundation
import QuickLookThumbnailing

struct DownloadFile: Identifiable, Equatable {
    let id: String
    let url: URL
    let name: String
    let size: Int64
    let date: Date
    let isPartial: Bool  // .crdownload / .download / .part

    var sizeText: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}

final class DownloadsStore: ObservableObject {
    @Published var files: [DownloadFile] = []
    @Published var accessDenied = false
    @Published var folderEmpty = true
    @Published var thumbs: [String: NSImage] = [:]
    /// 渲染证据:分段「最近 | 全部」— 最近 = 3 天
    var recentOnly = true

    private var timer: Timer?
    private static let recentDays = 3.0   // 证据: “最近 3 天没有新下载”

    static var downloadsURL: URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
    }

    func startWatching() {
        guard timer == nil else { return }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    func stopWatching() { timer?.invalidate(); timer = nil }

    func refresh() {
        let dir = Self.downloadsURL
        let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey, .totalFileSizeKey, .contentModificationDateKey]
        guard let list = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]) else {
            accessDenied = true   // TCC 拒绝 → 界面展示引导
            return
        }
        accessDenied = false
        let cutoff = Date().addingTimeInterval(-Self.recentDays * 86400)
        var result: [DownloadFile] = []
        for url in list {
            let values = try? url.resourceValues(forKeys: Set(keys))
            let date = values?.contentModificationDate ?? Date()
            if recentOnly, date <= cutoff { continue }
            let isDir = values?.isDirectory ?? false
            let size = Int64((values?.totalFileSize ?? values?.fileSize) ?? 0)
            let name = url.lastPathComponent
            let partial = name.hasSuffix(".crdownload") || name.hasSuffix(".download") || name.hasSuffix(".part")
            result.append(DownloadFile(id: url.path, url: url, name: name,
                                       size: isDir ? -1 : size, date: date, isPartial: partial))
        }
        folderEmpty = result.isEmpty
        result.sort { $0.date > $1.date }
        files = Array(result.prefix(60))
    }

    func reveal(_ f: DownloadFile) {
        NSWorkspace.shared.activateFileViewerSelecting([f.url])
    }

    func open(_ f: DownloadFile) {
        NSWorkspace.shared.open(f.url)
    }

    func trash(_ f: DownloadFile) {
        var out: NSURL?
        try? FileManager.default.trashItem(at: f.url, resultingItemURL: &out)
        refresh()
    }

    func loadThumb(for f: DownloadFile) {
        guard thumbs[f.id] == nil else { return }
        ThumbnailProvider.shared.thumbnail(for: f.url, size: 68) { [weak self] img in
            guard let img else { return }
            self?.thumbs[f.id] = img
        }
    }
}

// MARK: - 缩略图(证据: ThumbnailProvider / QLThumbnailGenerator)

final class ThumbnailProvider {
    static let shared = ThumbnailProvider()
    private var cache: [String: NSImage] = [:]

    func thumbnail(for url: URL, size: CGFloat, completion: @escaping (NSImage?) -> Void) {
        let key = url.path
        if let hit = cache[key] { return completion(hit) }
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: size, height: size),
                                                   scale: scale, representationTypes: .thumbnail)
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { [weak self] rep, _ in
            DispatchQueue.main.async {
                if let img = rep?.nsImage { self?.cache[key] = img }
                completion(rep?.nsImage)
            }
        }
    }

    func icon(for url: URL) -> NSImage {
        NSWorkspace.shared.icon(forFile: url.path)
    }
}
