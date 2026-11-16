// ShelfBarController.swift — 独立常驻货架条
// 证据: ShelfBarContainerView / shelfBarItem / shelfBarX / shelfBarY /
//      shelfBarW / shelfBarH / toggleShelfBar / NSGradient 背景
import AppKit
import Combine
import SwiftUI

final class ShelfBarController: NSObject, NSWindowDelegate, ObservableObject {
    let state: AppState
    private(set) var window: NSPanel?

    init(state: AppState) {
        self.state = state
        super.init()
    }

    func show() {
        if window == nil {
            let frame = state.settings.shelfBarFrame
            let panel = NSPanel(contentRect: frame,
                                styleMask: [.borderless, .nonactivatingPanel],
                                backing: .buffered, defer: false)
            panel.isFloatingPanel = true
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.isMovableByWindowBackground = true
            panel.isReleasedWhenClosed = false
            panel.delegate = self
            panel.contentView = NSHostingView(
                rootView: ShelfBarView(state: state)
                    .environment(\.colorScheme, state.settings.themeIsDark ? .dark : .light))
            window = panel
        }
        window?.orderFrontRegardless()
    }

    func hide() {
        window?.orderOut(nil)
    }

    // 位置持久化(证据: shelfBarX / shelfBarY / shelfBarW / shelfBarH)
    func windowDidMove(_ notification: Notification) {
        guard let window else { return }
        var s = state.settings
        s.shelfBarFrame = window.frame
        state.settings = s
    }

    func windowDidResize(_ notification: Notification) {
        windowDidMove(notification)
    }
}

struct ShelfBarView: View {
    @ObservedObject var state: AppState
    @ObservedObject private var store = AppState.shared.shelf

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "square.stack.3d.up")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
            if store.items.isEmpty {
                Text("拖文件到这里")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.75))
            } else {
                ForEach(store.items.prefix(6)) { item in
                    HStack(spacing: 4) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: item.path))
                            .resizable().frame(width: 22, height: 22)
                        Text(item.url.lastPathComponent)
                            .lineLimit(1)
                            .font(.system(size: 11))
                            .foregroundStyle(.white)
                            .frame(maxWidth: 110)
                    }
                    .padding(.horizontal, 7).padding(.vertical, 5)
                    .background(
                        Capsule().fill(Color.white.opacity(0.16))
                    )
                    .draggable(item.url)
                    .contextMenu {
                        Button("在 Finder 中显示") {
                            NSWorkspace.shared.activateFileViewerSelecting([item.url])
                        }
                        Button("从暂存中移除", role: .destructive) {
                            store.remove(item.id)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .frame(minWidth: state.settings.shelfBarFrame.width,
               idealWidth: state.settings.shelfBarFrame.width,
               minHeight: state.settings.shelfBarFrame.height)
        .background(ShelfBarBackground())
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.35), radius: 6, y: 2)
    }
}

/// 渐变背景(证据: initWithStartingColor:endingColor: NSGradient)
struct ShelfBarBackground: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color(red: 0.16, green: 0.47, blue: 0.86),
                Color(red: 0.10, green: 0.62, blue: 0.70),
            ],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
        .opacity(0.92)
    }
}
