// MusicController.swift — 正在播放
// 架构(2026-11-15 定稿):MediaRemote 私有框架只在**无 NSApplication 的进程**里
// 返回数据(NSApplication 上下文恒回调 nil),故由应用启动 MediaHelper 子进程:
//   watch   — 每秒 stdout 一行 JSON 快照(变化才输出 + 5 拍心跳保看门狗)
//   artwork — MRArtwork.imageData(JPEG)base64(新系统已把 ArtworkData 从
//             nowPlayingInfo 移除,须走实例方法)
//   send N  — MRMediaRemoteSendCommand 播放控制
import AppKit
import Combine
import Foundation

// MARK: - 快照模型

struct NowPlayingSnapshot: Codable {
    var bundle: String = ""
    var app: String = ""
    var pid: Int = 0
    var playing: Bool = false
    var title: String = ""
    var artist: String = ""
    var album: String = ""
    var duration: Double = 0
    var elapsed: Double = 0
    var rate: Double = 0
    var ts: Double = 0
    var artId: String = ""
    var error: String?
}

// MRMediaRemoteSendCommand 命令号(2 为播放/暂停切换)
enum MediaCommand: Int {
    case play = 0, pause = 1, toggle = 2, next = 4, previous = 5
}

// MARK: - 控制器(MediaHelper 子进程架构)

final class MusicController: ObservableObject {
    // snapshot 允许内部注入:promoshot 渲染模式要放演示曲目
    @Published var snapshot: NowPlayingSnapshot?
    @Published private(set) var artwork: NSImage?
    @Published private(set) var agentRunning = false

    private var process: Process?
    private var watchdog: Timer?
    private var lastLineAt = Date()
    private var lineBuffer = ""
    private var lastArtId = ""
    private(set) var watchRequested = false
    private let queue = DispatchQueue(label: "sidedock.nowplaying")

    // MediaHelper.swift 源码位置 + Apple 签名的 swift 解释器
    // (MediaRemote 只信任 Apple 签名宿主进程;自编译二进制 completion 恒回调 nil)
    private var helperSourceURL: URL? {
        if let url = Bundle.main.resourceURL?.appendingPathComponent("MediaHelper.swift"),
           FileManager.default.fileExists(atPath: url.path) { return url }
        if let exe = Bundle.main.executableURL {
            let candidate = exe.deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Resources/MediaHelper.swift")
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        }
        return nil
    }

    private var interpreterURL: URL? {
        for path in ["/usr/bin/swift", "/usr/bin/swift3"] {
            if FileManager.default.fileExists(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        return nil
    }

    func startWatch() {
        // promoshot 渲染模式不启动真实监听,用注入的演示曲目
        guard ProcessInfo.processInfo.environment["SIDEDOCK_PROMOSHOT"] == nil else { return }
        guard !watchRequested else { return }
        watchRequested = true
        launchAgent()
    }

    func stopWatch() {
        watchRequested = false
        watchdog?.invalidate(); watchdog = nil
        process?.terminate()
        process = nil
        agentRunning = false
    }

    private func launchAgent() {
        guard watchRequested, let helper = helperSourceURL, let interpreter = interpreterURL else { return }
        if let existing = process, existing.isRunning {
            existing.terminationHandler = nil
            existing.terminate()
            let deadline = Date().addingTimeInterval(1)
            while existing.isRunning && Date() < deadline {
                Thread.sleep(forTimeInterval: 0.05)
            }
        }
        process = nil
        let p = Process()
        p.executableURL = interpreter
        p.arguments = [helper.path, "watch"]
        let outPipe = Pipe()
        let errPipe = Pipe()
        p.standardOutput = outPipe
        p.standardError = errPipe

        outPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil; return }
            if let text = String(data: data, encoding: .utf8) {
                self?.queue.async { self?.ingest(text) }
            }
        }
        errPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil }
        }
        p.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                self?.agentRunning = false
                // 统一重启路径:被看门狗终止或自行退出后 2 秒重启
                if self?.watchRequested == true {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self?.launchAgent() }
                }
            }
        }
        do {
            try p.run()
            process = p
            agentRunning = true
            lastLineAt = Date()
            startWatchdog()
        } catch {
            agentRunning = false
        }
    }

    private func startWatchdog() {
        watchdog?.invalidate()
        watchdog = Timer.scheduledTimer(withTimeInterval: 8, repeats: true) { [weak self] _ in
            guard let self, self.watchRequested else { return }
            if Date().timeIntervalSince(self.lastLineAt) > 10 {
                self.process?.terminate()   // 重启统一交给 terminationHandler
            }
        }
    }

    private func ingest(_ text: String) {
        DispatchQueue.main.async { self.lastLineAt = Date() }
        lineBuffer += text
        var lines = lineBuffer.split(separator: "\n", omittingEmptySubsequences: false)
        guard !lines.isEmpty else { return }
        lineBuffer = String(lines.removeLast())
        for line in lines {
            guard let data = line.data(using: .utf8),
                  let snap = try? JSONDecoder().decode(NowPlayingSnapshot.self, from: data) else { continue }
            DispatchQueue.main.async {
                self.snapshot = snap
                if snap.artId != self.lastArtId {
                    self.lastArtId = snap.artId
                    if !snap.title.isEmpty { self.fetchArtwork() } else { self.artwork = nil }
                }
            }
        }
    }

    // MARK: 封面(helper artwork 模式)

    private var fetchingArtwork = false

    private func fetchArtwork() {
        guard !fetchingArtwork, let helper = helperSourceURL, let interpreter = interpreterURL else { return }
        fetchingArtwork = true
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let p = Process()
            p.executableURL = interpreter
            p.arguments = [helper.path, "artwork"]
            let pipe = Pipe()
            p.standardOutput = pipe
            p.standardError = FileHandle.nullDevice
            var result = ""
            do {
                try p.run()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                result = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            } catch { }
            DispatchQueue.main.async {
                self?.fetchingArtwork = false
                guard !result.isEmpty, let data = Data(base64Encoded: result),
                      let img = NSImage(data: data) else { return }
                self?.artwork = img
            }
        }
    }

    // MARK: 播放控制

    func send(_ command: MediaCommand) {
        guard let helper = helperSourceURL, let interpreter = interpreterURL else { return }
        DispatchQueue.global(qos: .utility).async {
            let p = Process()
            p.executableURL = interpreter
            p.arguments = [helper.path, "send", String(command.rawValue)]
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
            try? p.run()
            p.waitUntilExit()
        }
    }

    func openPlayingApp() {
        guard let bundle = snapshot?.bundle, !bundle.isEmpty,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) else { return }
        let config = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.openApplication(at: url, configuration: config)
    }
}
