// MediaHelper.swift — 无 NSApplication 的 MediaRemote 桥进程
// 实测(2026-11-15):requestNowPlayingInfoWithCompletion:/requestNowPlayingItemArtwork
// WithCompletion: 只在**无 NSApplication 的进程**里返回数据(NSApplication 上下文恒回调
// nil),故由 SideDock.app 以子进程方式调用本 helper。
// 用法:
//   MediaHelper watch            每秒输出一行 JSON 快照(变化才输出 + 5 拍心跳)
//   MediaHelper artwork          输出封面 JPEG 的 base64
//   MediaHelper send <cmd>       发送播放控制命令(MRMediaRemoteSendCommand)
import AppKit
import CoreMedia

let bundle = Bundle(path: "/System/Library/PrivateFrameworks/MediaRemote.framework")
if bundle?.load() != true {
    FileHandle.standardError.write("MediaRemote.framework load failed\n".data(using: .utf8)!)
    exit(1)
}
guard let cls = NSClassFromString("MRNowPlayingRequest") as? NSObject.Type else {
    FileHandle.standardError.write("MRNowPlayingRequest not found\n".data(using: .utf8)!)
    exit(1)
}

func requestInfo() -> [String: Any]? {
    let sem = DispatchSemaphore(value: 0)
    var dict: [String: Any]?
    let block: @convention(block) (AnyObject?) -> Void = { info in
        dict = info as? [String: Any]
        sem.signal()
    }
    let req = cls.init()
    req.perform(NSSelectorFromString("requestNowPlayingInfoWithCompletion:"), with: block)
    _ = sem.wait(timeout: .now() + 3)
    return dict
}

func playerClient() -> NSObject? {
    guard let path = cls.perform(NSSelectorFromString("localNowPlayingPlayerPath"))?
        .takeUnretainedValue() as? NSObject else { return nil }
    return path.perform(NSSelectorFromString("client"))?.takeUnretainedValue() as? NSObject
}

func snapshotJSON() -> String? {
    guard let dict = requestInfo() else { return nil }
    var s: [String: Any] = [:]
    s["title"] = dict["kMRMediaRemoteNowPlayingInfoTitle"] as? String ?? ""
    s["artist"] = dict["kMRMediaRemoteNowPlayingInfoArtist"] as? String ?? ""
    s["album"] = dict["kMRMediaRemoteNowPlayingInfoAlbum"] as? String ?? ""
    s["duration"] = (dict["kMRMediaRemoteNowPlayingInfoDuration"] as? NSNumber)?.doubleValue ?? 0
    s["elapsed"] = (dict["kMRMediaRemoteNowPlayingInfoElapsedTime"] as? NSNumber)?.doubleValue ?? 0
    s["rate"] = (dict["kMRMediaRemoteNowPlayingInfoPlaybackRate"] as? NSNumber)?.doubleValue ?? 0
    s["playing"] = s["rate"] as! Double > 0
    s["artId"] = dict["kMRMediaRemoteNowPlayingInfoArtworkIdentifier"] as? String ?? ""
    if let ts = dict["kMRMediaRemoteNowPlayingInfoTimestamp"] as? Date {
        s["ts"] = ts.timeIntervalSince1970
    }
    let client = playerClient()
    s["app"] = client?.perform(NSSelectorFromString("displayName"))?
        .takeUnretainedValue() as? String ?? ""
    s["bundle"] = client?.perform(NSSelectorFromString("bundleIdentifier"))?
        .takeUnretainedValue() as? String ?? ""
    s["pid"] = 0
    guard let data = try? JSONSerialization.data(withJSONObject: s),
          let line = String(data: data, encoding: .utf8) else { return nil }
    return line
}

func emit(_ line: String) {
    FileHandle.standardOutput.write((line + "\n").data(using: .utf8)!)
}

let argv = CommandLine.arguments

// MARK: watch
if argv.count > 1, argv[1] == "watch" {
    var last = ""
    for i in 0..<86400 {
        if let line = snapshotJSON(), line != last || i % 5 == 0 {
            emit(line)
            last = line
        } else if i % 5 == 0 {
            emit("{\"watchdog\":true}")   // 心跳,保证输出不断流
        }
        Thread.sleep(forTimeInterval: 1)
    }
    exit(0)
}

// MARK: artwork
if argv.count > 1, argv[1] == "artwork" {
    let sem = DispatchSemaphore(value: 0)
    var b64 = ""
    let block: @convention(block) (AnyObject?) -> Void = { obj in
        defer { sem.signal() }
        guard let art = obj,
              art.responds(to: NSSelectorFromString("imageData")),
              let v = art.perform(NSSelectorFromString("imageData"))?.takeUnretainedValue(),
              let data = v as? Data else { return }
        b64 = data.base64EncodedString()
    }
    let req = cls.init()
    req.perform(NSSelectorFromString("requestNowPlayingItemArtworkWithCompletion:"), with: block)
    _ = sem.wait(timeout: .now() + 6)
    emit(b64)
    exit(0)
}

// MARK: send
if argv.count > 2, argv[1] == "send" {
    guard let sym = dlsym(dlopen(nil, RTLD_LAZY), "MRMediaRemoteSendCommand") else {
        FileHandle.standardError.write("MRMediaRemoteSendCommand symbol not found\n".data(using: .utf8)!)
        exit(1)
    }
    typealias SendFn = @convention(c) (Int32, AnyObject?) -> Bool
    let fn = unsafeBitCast(sym, to: SendFn.self)
    let cmd = Int32(argv[2]) ?? 2
    let ok = fn(cmd, nil)
    emit(ok ? "true" : "false")
    exit(0)
}

FileHandle.standardError.write("usage: MediaHelper watch|artwork|send <cmd>\n".data(using: .utf8)!)
exit(2)
