# SideDock

macOS 屏幕右缘侧边栏工具:待办、笔记、下载、暂存、密码、剪贴板(Maccy 式)、正在播放;剪贴板另有独立的菜单栏入口,悬停即展开。

基于对 SideDock 1.1(原第三方应用)的静态逆向与运行时行为分析,以 Swift(AppKit + SwiftUI)全新源码实现;剪贴板交互参照 [Maccy](https://github.com/p0deje/Maccy) 2.8.0 逆向结论。

## 功能

| 面板 | 功能 |
|---|---|
| 侧边栏 | 屏幕右缘 12×96 把手,悬停/点击展开;面板与把手中心对齐、贴右缘;上下拖动把手调位置,拖边缘/角调大小;常驻(图钉)模式、点击外部收起、应用内快捷键 |
| 待办 | 到期预设(今日/明日/一周)、分组筛选、到点系统通知、逾期红标与提醒角标 |
| 笔记 | 首行作标题、正文摘要、相对时间;JSON 本地保存 |
| 下载 | 监听下载文件夹(最近 3 天/全部)、QuickLook 缩略图、今天/昨天分组、Finder 定位、废纸篓、未授权引导 |
| 暂存 | 拖文件暂存(只记路径不复制)、文件网格、拖出 |
| 剪贴板 | 独立 Tab(密码之后)+ 菜单栏入口(可开关);Maccy 式:搜索、固定区+分隔线、清除=只清未固定、来源应用图标、键盘导航(↑↓/↩/Esc)、**选中即复制并向前台应用模拟 ⌘V** |
| 密码 | 元数据存 vault.json,密码本体存钥匙串(本机锁定);Touch ID/Face ID 验证查看;随机强密码(去易混淆字符) |
| 音乐 | MediaRemote 私有框架:曲名/歌手/进度/封面/播放控制;看门狗自动重启 |
| 底部常驻 | 每个面板底部固定迷你播放卡片 |

## 玻璃主题(视觉)

面板为毛玻璃拟态(与设计稿逐值对应,设计稿在仓库外层 `.open-design/sidedock-macos-glassmorphism-12-96pt-472-519pt-sd-44-44-5-ta/`):

- **面板底** = 透明 NSPanel + `NSVisualEffectView`(浅色 `.sidebar` / 深色 `.hudWindow`,behindWindow 真实取景模糊)+ 半透明 tint(设置里的「背景不透明度」直接乘在其上)+ 顶部内侧高光 + 发丝描边 + 双层投影
- **内容卡片** = 半透明玻璃层(填充 + 描边 + 内顶高光),悬停提亮一档
- **色板** = `AppState.swift` 的 `ThemeColors`,浅色 accent `#3B82F6` / 深色 accent `#4A8DFF`,与设计稿 :root 令牌一一对应
- **图标** = `make_icon.swift` 程序化绘制:超椭圆圆角方(n≈5,macOS squircle)+ 品牌蓝→靛渐变 + 玻璃面板图形(坞位横条 + 右缘把手),逐尺寸重绘 16–1024(@2x),小尺寸自动简化

## 构建(仅命令行工具,无需 Xcode)

```bash
./build.sh          # 产物: build/SideDock.app(ad-hoc 签名)
open build/SideDock.app
```

要求 macOS 14+ 与 Xcode Command Line Tools(swiftc 6.x)。

## 架构要点

- **MediaHelper 桥**:MediaRemote 私有框架的 completion 只在 Apple 签名宿主进程返回数据(`swiftc` 自编译二进制与 NSApplication 进程内均回调 nil),故 `Sources/MediaHelper.swift` 以源码分发,经 `/usr/bin/swift` 解释执行,提供 `watch`/`artwork`/`send` 三个子命令。
- **自动粘贴权限**:剪贴板"选中即粘贴"通过 CGEvent 模拟 ⌘V,需在 系统设置 → 隐私与安全性 → 辅助功能 中授权;未授权时仅复制。
- **下载文件夹 TCC**:首次打开"下载"面板需在 系统设置 → 隐私与安全性 → 文件与文件夹 中放行。
- **数据目录** `~/Library/Application Support/SideDock/`(JSON 持久化;`SIDEDOCK_DATA_DIR` 可覆盖),钥匙串服务 `com.xiaohao003.SideDock.vault`。

## 结构

```
Sources/
  main.swift               入口:手动装配 delegate + 状态栏菜单 + 事件监听 + promoshot 渲染
  AppState.swift           设置/持久化/UIState/主题色板/Hotkey
  Panel.swift              SidebarPanel(NSPanel)/SidebarController/把手/面板骨架/底部音乐卡
  Views.swift              五个面板内容 + MaccyClipboardList + 设置窗口 + 快捷键录入
  Stores.swift             笔记/待办/暂存/密码/剪贴板存储 + 钥匙串 + 密码生成
  Downloads.swift          下载监控 + QuickLook 缩略图
  MusicController.swift    正在播放(MediaHelper 子进程架构)
  MediaHelper.swift        无 GUI 的 MediaRemote 桥(经 /usr/bin/swift 解释执行)
  PasteHelper.swift        ⌘V 模拟粘贴(辅助功能权限) + 来源应用图标缓存
  ShelfBarController.swift 独立货架条窗口
  make_icon.swift          程序化生成应用图标
build.sh                   编译 + 组装 .app + iconutil + ad-hoc 签名
```

## 调试渲染

```bash
SIDEDOCK_PROMOSHOT=<输出目录> build/SideDock.app/Contents/MacOS/SideDock
# 逐面板离屏渲染 PNG(含演示数据),用于 UI 回归比对
```
