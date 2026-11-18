// settings.rs — 设置持久化 + 数据目录
// 对应 macOS 版 AppState.Settings:字段缺省即回退默认(serde default 等价 decodeIfPresent)
use serde::{Deserialize, Serialize};
use std::path::PathBuf;

pub const PANEL_W: f32 = 472.0;
pub const PANEL_H: f32 = 519.0;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum ThemeMode {
    System,
    Light,
    Dark,
}

impl ThemeMode {
    pub fn title(self) -> &'static str {
        match self {
            ThemeMode::System => "跟随系统",
            ThemeMode::Light => "浅色",
            ThemeMode::Dark => "深色",
        }
    }
    pub fn all() -> [ThemeMode; 3] {
        [ThemeMode::System, ThemeMode::Light, ThemeMode::Dark]
    }
}

/// 全局快捷键(与 global-hotkey 的 HotKey 互转;JSON 存字符串便于跨版本)
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct HotkeySpec {
    pub ctrl: bool,
    pub alt: bool,
    pub shift: bool,
    pub win: bool,
    pub code: String, // 如 "KeyS"
}

impl Default for HotkeySpec {
    fn default() -> Self {
        HotkeySpec { ctrl: true, alt: true, shift: false, win: false, code: "KeyS".into() }
    }
}

impl HotkeySpec {
    pub fn display(&self) -> String {
        let mut parts: Vec<String> = Vec::new();
        if self.ctrl { parts.push("Ctrl".to_string()); }
        if self.alt { parts.push("Alt".to_string()); }
        if self.shift { parts.push("Shift".to_string()); }
        if self.win { parts.push("Win".to_string()); }
        parts.push(match self.code.as_str() {
            "Space" => "空格".to_string(),
            c if c.starts_with("Key") => c.trim_start_matches("Key").to_string(),
            c if c.starts_with("Digit") => c.trim_start_matches("Digit").to_string(),
            c => c.to_string(),
        });
        parts.join("+")
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct Settings {
    pub theme_mode: ThemeMode,
    pub theme_is_dark: bool, // 当前生效主题(视图统一读这里)
    pub pinned: bool,        // 常驻模式(失焦不收起)
    pub auto_paste: bool,    // 选中剪贴板历史后自动粘贴
    pub launch_at_login: bool,
    pub hotkey: Option<HotkeySpec>,
    pub tab: PanelTab,
    /// 底部正在播放卡片开关(对应 macOS 版 musicCardVisible)
    pub show_music: bool,
    /// 自由定位(对应 macOS 版 panelOriginX/Y):拖空白移动/拖边缘缩放后记录
    /// 物理像素坐标;None = 未动过,仍停靠屏幕右缘
    pub pos: Option<(f32, f32)>,
}

impl Default for Settings {
    fn default() -> Self {
        Settings {
            theme_mode: ThemeMode::System,
            theme_is_dark: false,
            pinned: true,
            auto_paste: true,
            launch_at_login: false,
            hotkey: Some(HotkeySpec::default()),
            tab: PanelTab::Todo,
            show_music: true,
            pos: None,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum PanelTab {
    Todo,
    Notes,
    Downloads,
    Shelf,
    Passwords,
    Clipboard,
}

impl PanelTab {
    pub const ALL: [PanelTab; 6] = [
        PanelTab::Todo,
        PanelTab::Notes,
        PanelTab::Downloads,
        PanelTab::Shelf,
        PanelTab::Passwords,
        PanelTab::Clipboard,
    ];

    pub fn title(self) -> &'static str {
        match self {
            PanelTab::Todo => "待办",
            PanelTab::Notes => "笔记",
            PanelTab::Downloads => "下载",
            PanelTab::Shelf => "暂存",
            PanelTab::Passwords => "密码",
            PanelTab::Clipboard => "剪贴板",
        }
    }

    pub fn icon(self) -> &'static str {
        match self {
            PanelTab::Todo => "☑",
            PanelTab::Notes => "✎",
            PanelTab::Downloads => "⬇",
            PanelTab::Shelf => "⌸",
            PanelTab::Passwords => "⚿",
            PanelTab::Clipboard => "📋",
        }
    }
}

// MARK: - 数据目录(%APPDATA%\SideDock;SIDEDOCK_DATA_DIR 可覆盖)

pub fn data_dir() -> PathBuf {
    if let Ok(over) = std::env::var("SIDEDOCK_DATA_DIR") {
        if !over.is_empty() {
            let p = PathBuf::from(over);
            let _ = std::fs::create_dir_all(&p);
            return p;
        }
    }
    let base = dirs::data_dir().unwrap_or_else(|| PathBuf::from("."));
    let dir = base.join("SideDock");
    let _ = std::fs::create_dir_all(&dir);
    dir
}

pub fn data_file(name: &str) -> PathBuf {
    data_dir().join(name)
}

pub fn load_json<T: for<'de> Deserialize<'de>>(name: &str) -> Option<T> {
    let bytes = std::fs::read(data_file(name)).ok()?;
    serde_json::from_slice(&bytes).ok()
}

pub fn save_json<T: Serialize>(name: &str, value: &T) {
    if let Ok(bytes) = serde_json::to_vec_pretty(value) {
        let path = data_file(name);
        let tmp = path.with_extension("tmp");
        if std::fs::write(&tmp, &bytes).is_ok() {
            let _ = std::fs::rename(&tmp, &path);
        }
    }
}

pub fn settings_path() -> PathBuf {
    data_file("settings.json")
}

pub fn load_settings() -> Settings {
    load_json::<Settings>("settings.json").unwrap_or_default()
}
