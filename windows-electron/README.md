# SideDock for Windows(Electron 版)

桌面侧边栏工具:待办 / 笔记 / 下载 / 暂存 / 密码 / 剪贴板 + 正在播放卡片。

本目录是 Windows 版的 **Electron 实现**(v1.2.0 起),替代原 Rust/egui 版(`windows/`,保留供参考)。
选 Electron 的原因:Chromium 渲染走 ANGLE→DirectX(远程桌面 RDP 只给 OpenGL 1.1,glow 全白屏的根因),
无边框窗口拖动/四边四角缩放由系统原生处理(与 ZCode 同一套交互)。

## 功能对照(与 macOS 版 / 旧 Rust 版一致)

- 待办:今日/明日/一周/长期/历史分组;完成当天留原分组、次日进历史;到期前 2h 提示铃铛;右键删除
- 笔记:首行为标题的速记卡片,相对时间
- 下载:监控系统"下载"文件夹,最近 3 天/全部切换,今天/昨天/本周/更早分组,进行中(.crdownload 等)标记
- 暂存:拖入文件记录位置(不复制),3 列网格,多文件保持拖入顺序
- 密码:本机 DPAPI 加密(safeStorage),随机强密码生成,12s 自动隐藏揭示
- 剪贴板:Maccy 式历史(文本/图片),来源应用标记,固定区+搜索,键盘导航,选中回写(+可选自动粘贴)
- 音乐卡:SMTC 轮询(封面/进度/媒体键模拟),可在设置关闭
- 待办/笔记/密码支持右键删除,删除前弹出确认弹框(回车确认、Esc 取消)
- 托盘 + 全局快捷键(Ctrl+Alt+S)+ 开机自启 + 跟随系统深浅色

界面图标来自 iconfont.cn 单色线性图标(主集合「基础图标」by muxuhang,
另挑选图钉/剪贴板/播放控制/魔棒等单枚图标,来源明细见 `src/renderer/icons.js` 头部注释)。

## 数据兼容

数据目录与旧版完全一致:`%APPDATA%\SideDock`
(settings.json / todos.json / notes.json / shelf.json / vault.json / clipboard.json / images/)。
从 Rust 版升级无需迁移;密码密文同为 DPAPI,仅本机可解。

## 开发

```bash
npm install
npm test          # node --test 纯逻辑单测(分组/预设/夹回/格式化)
npm start         # 本机(含 mac)可直接跑;Windows 专属能力(托盘/热键/SMTC)自动跳过
```

## 打包

```bash
npm run dist      # electron-builder → dist/SideDock-windows-setup.exe + SideDock-windows-x64.zip
```

NSIS 安装向导:可选安装目录、开始菜单/桌面快捷方式,中英文界面。

## 环境变量

| 变量 | 说明 |
| --- | --- |
| `SIDEDOCK_DATA_DIR` | 覆盖数据目录(测试/多开) |
| `SIDEDOCK_OPAQUE=1` | 强制不透明窗口(透明合成异常时兜底;四角方角) |
| `SIDEDOCK_SMOKE=1` | 启动 3s 后自动退出(CI 冒烟) |
