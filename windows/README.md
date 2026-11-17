# SideDock for Windows

macOS 版 SideDock 的 Windows 重实现(Rust + egui)。桌面右侧常驻侧边栏,六个面板:
待办 / 笔记 / 下载 / 暂存 / 密码 / 剪贴板。

## 构建

需要 Rust stable(1.85+)：

```powershell
cd windows
cargo build --release
# 产物: target/release/SideDock.exe
```

或直接在 GitHub Actions 的 **Windows Build** 工作流里下载 `SideDock-windows-x64` 产物
(push 到 `windows/**` 或手动 workflow_dispatch 触发)。

## 使用

- 首次启动后面板停靠屏幕右缘、垂直居中,置顶且不进任务栏;
- **拖四边/四角调整大小、拖空白区域移动窗口**(位置持久化,设置页"恢复默认"回到停靠右缘);
- 系统托盘图标:点击切换显示,菜单提供 显示面板 / 设置 / 退出;
- 全局快捷键默认 `Ctrl+Alt+S`(设置页可见);
- ⚙ 设置页:主题(跟随系统/浅色/深色)、常驻模式(失焦不收起)、剪贴板自动粘贴、开机自启;
- 头栏 📌 切换常驻,› 收起面板(托盘或热键再呼出)。

## 功能对照(macOS 版 → Windows 版)

| 功能 | 实现方式 |
| --- | --- |
| 主题 | 色值取自原版 promoshot 渲染逐点取样;跟随系统读注册表 `AppsUseLightTheme`(2s 轮询) |
| 待办 | 单一事实源分组算法(今日/明日/一周/历史),与 macOS 版同一套无头测试 |
| 笔记 | JSON 落盘,首行为标题 |
| 下载 | 轮询 `%USERPROFILE%\Downloads`,最近 3 天/全部,今天/昨天/本周/更早分组 |
| 暂存 | egui 原生文件拖放;只记录路径不复制文件 |
| 密码 | `vault.json` + **DPAPI** 加密(对应 macOS 钥匙串,仅本机可解);随机强密码生成同字符集 |
| 剪贴板 | 0.6s 轮询 `GetClipboardSequenceNumber`(对应 NSPasteboard changeCount);文本+图片(PNG 落盘);固定区/搜索/键盘导航;选中回写剪贴板,可选拟 `Ctrl+V` 自动粘贴 |
| 正在播放 | Windows **SMTC** 会话轮询(标题/艺人/进度/封面);播放控制模拟媒体键 |

## 数据位置

`%APPDATA%\SideDock\`(todos.json / notes.json / shelf.json / vault.json / clipboard.json / settings.json / images\)
;环境变量 `SIDEDOCK_DATA_DIR` 可覆盖。

## 已知差异(macOS 版没有的取舍)

- Windows 公开 API 无法取跨应用图标:剪贴板条目来源用首字母色块代替应用图标;
- SMTC 不提供跨应用播放命令:播放/上下曲走媒体键(`VK_MEDIA_PLAY_PAUSE` 等);
- 密码查看未接 Windows Hello(DES 内容本身已由 DPAPI 绑定本机);
- 菜单栏剪贴板独立入口(macOS 版已下线)未随附。
