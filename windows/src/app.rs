// app.rs — 应用外壳:窗口/托盘/全局热键/轮询/主题/纹理缓存
// 对应 macOS 版 AppState + AppDelegate;eframe 单窗口常驻 + 失焦收起
use crate::settings::{
    data_dir, load_settings, save_json, PanelTab, Settings, ThemeMode, PANEL_H, PANEL_W,
};
use crate::stores::{ClipboardStore, VaultStore};
use crate::theme::{colors, ThemeColors};
use crate::todo::TodoStore;
use crate::ui::{shell, views};
use egui::{Color32, Context, CornerRadius, FontId, Pos2, Rect, ViewportCommand};
use std::collections::HashMap;
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::{Duration, Instant};

pub const WINDOW_TITLE: &str = "SideDock";

static CURRENT_DARK: AtomicBool = AtomicBool::new(false);

pub fn current_dark() -> bool {
    CURRENT_DARK.load(Ordering::Relaxed)
}

// MARK: - 瞬时 UI 状态(对应 macOS 版 UIState)

#[derive(Default)]
pub struct UIState {
    // 待办:到期预设 + 分组筛选 + 输入
    pub todo_draft: String,
    pub todo_preset: u8, // 1 今日(默认) 2 明日 3 一周
    pub todo_filter: u8, // 1 今日 2 明日 3 一周 4 历史
    // 笔记 / 密码:内联新建表单开关
    pub notes_adding: bool,
    pub notes_draft: String,
    pub vault_adding: bool,
    pub vault_site: String,
    pub vault_account: String,
    pub vault_phone: String,
    pub vault_password: String,
    pub vault_reveal_for: Option<uuid::Uuid>,
    pub vault_reveal_text: Option<String>,
    pub vault_reveal_until: Option<(uuid::Uuid, Instant)>,
    pub vault_toast: Option<(String, Instant)>,
    pub vault_edit_for: Option<uuid::Uuid>,
    pub vault_edit_pw: String,
    pub launch_failed_until: Option<Instant>,
    // 下载 / 剪贴板
    pub downloads_all: bool,
    pub downloads_search: String,
    pub clip_search: String,
    pub clip_selected: Option<usize>,
    pub clip_toast: Option<(String, Instant)>,
    // 暂存拖放高亮
    pub shelf_drop: bool,
    // 设置内页
    pub settings_open: bool,
    // 一次性动作请求(头栏/列表设置)
    pub pin_toggled: bool,
    pub hide_requested: bool,
    pub paste_requested: bool,
    pub reset_requested: bool,
}

// MARK: - 应用状态

pub struct App {
    pub settings: Settings,
    pub ui: UIState,
    pub todos: TodoStore,
    pub notes: crate::notes::NotesStore,
    pub shelf: crate::shelf::ShelfStore,
    pub vault: VaultStore,
    pub clipboard: ClipboardStore,
    pub downloads: crate::downloads::DownloadsStore,
    pub music: crate::music::MusicController,
    textures: HashMap<String, egui::TextureHandle>,
    music_art_key: String,
    last_clip_poll: Instant,
    last_dl_refresh: Instant,
    last_theme_poll: Instant,
    last_dark: Option<bool>,
    last_settings_json: String,
    win_fixed: bool,
    was_focused: bool,
    #[cfg(windows)]
    tray: Option<TrayHandles>,
    #[cfg(windows)]
    hotkey: Option<HotkeyHandles>,
}

impl App {
    fn new(cc: &eframe::CreationContext<'_>) -> Self {
        let mut settings = load_settings();
        if settings.theme_mode == ThemeMode::System {
            settings.theme_is_dark = crate::platform::system_is_dark();
        }
        setup_fonts(&cc.egui_ctx);
        apply_visuals(&cc.egui_ctx, settings.theme_is_dark);
        let downloads = crate::downloads::DownloadsStore::new();
        let clipboard = ClipboardStore::load();
        let mut app = App {
            settings,
            ui: UIState {
                todo_filter: 1,
                todo_preset: 1,
                ..Default::default()
            },
            todos: TodoStore::load(),
            notes: crate::notes::NotesStore::load(),
            shelf: crate::shelf::ShelfStore::load(),
            vault: VaultStore::load(),
            clipboard,
            downloads,
            music: crate::music::MusicController::new(),
            textures: HashMap::new(),
            music_art_key: String::new(),
            last_clip_poll: Instant::now(),
            last_dl_refresh: Instant::now(),
            last_theme_poll: Instant::now(),
            last_dark: None,
            last_settings_json: String::new(),
            win_fixed: false,
            was_focused: false,
            #[cfg(windows)]
            tray: setup_tray(),
            #[cfg(windows)]
            hotkey: setup_hotkey(),
        };
        let json = serde_json::to_string(&app.settings).unwrap_or_default();
        app.last_settings_json = json;
        app
    }

    fn persist_settings(&mut self) {
        let json = serde_json::to_string(&self.settings).unwrap_or_default();
        if json != self.last_settings_json {
            save_json("settings.json", &self.settings);
            self.last_settings_json = json;
        }
    }

    fn tab_counts(&self) -> [Option<u32>; 6] {
        let unfinished = self.todos.items.iter().filter(|it| !it.done).count() as u32;
        [
            Some(unfinished),
            None,
            None,
            Some(self.shelf.items.len() as u32),
            Some(self.vault.entries.len() as u32),
            Some(self.clipboard.entries.len() as u32),
        ]
    }

    /// 剪贴板图片缩略图纹理(按路径缓存)
    pub fn clip_texture(&mut self, ctx: &Context, e: &crate::stores::ClipEntry) -> Option<egui::TextureHandle> {
        let path = e.image_path.clone()?;
        let key = format!("clip:{}", path);
        if let Some(t) = self.textures.get(&key) {
            return Some(t.clone());
        }
        let bytes = std::fs::read(&path).ok()?;
        let img = image::load_from_memory(&bytes).ok()?;
        let rgba = img.to_rgba8();
        let ci = egui::ColorImage::from_rgba_unmultiplied([rgba.width() as _, rgba.height() as _], rgba.as_raw());
        let tex = ctx.load_texture(key.clone(), ci, egui::TextureOptions::LINEAR);
        self.textures.insert(key, tex.clone());
        Some(tex)
    }

    /// 音乐封面纹理(曲目变化时重载)
    fn music_texture(&mut self, ctx: &Context) -> Option<egui::TextureHandle> {
        let snap = self.music.snapshot()?;
        let (w, h, rgba) = snap.art.clone()?;
        let key = format!("art:{}:{}", snap.title, snap.artist);
        if key == self.music_art_key {
            return self.textures.get(&key).cloned();
        }
        let ci = egui::ColorImage::from_rgba_unmultiplied([w as _, h as _], &rgba);
        let tex = ctx.load_texture(key.clone(), ci, egui::TextureOptions::LINEAR);
        self.textures.insert(key.clone(), tex.clone());
        self.music_art_key = key;
        Some(tex)
    }

    fn hide(&self, ctx: &Context) {
        ctx.send_viewport_cmd(ViewportCommand::Visible(false));
    }

    fn show(&self, ctx: &Context) {
        ctx.send_viewport_cmd(ViewportCommand::Visible(true));
        ctx.send_viewport_cmd(ViewportCommand::Focus);
        #[cfg(windows)]
        crate::platform::fixup_panel_window(WINDOW_TITLE, true);
    }

    fn toggle_visible(&mut self, ctx: &Context) {
        let visible = ctx.input(|i| i.viewport().focused == Some(true))
            || self.was_focused;
        if visible {
            self.hide(ctx);
            self.was_focused = false;
        } else {
            self.show(ctx);
        }
    }

    #[allow(unused_variables)] // 非 Windows 平台无托盘/热键频道
    fn poll_platform(&mut self, ctx: &Context) {
        // 托盘菜单 / 托盘点击 / 全局热键
        #[cfg(windows)]
        {
            use tray_icon::menu::MenuEvent;
            if let Some(tray) = &self.tray {
                let ids = &tray.ids;
                while let Ok(ev) = MenuEvent::receiver().try_recv() {
                    if ev.id == ids[0] {
                        self.show(ctx);
                    } else if ev.id == ids[1] {
                        self.ui.settings_open = true;
                        self.show(ctx);
                    } else if ev.id == ids[2] {
                        std::process::exit(0);
                    }
                }
                while let Ok(ev) = tray_icon::TrayIconEvent::receiver().try_recv() {
                    if matches!(ev, tray_icon::TrayIconEvent::Click { .. }) {
                        self.toggle_visible(ctx);
                    }
                }
            }
            if self.hotkey.is_some() {
                use global_hotkey::HotKeyState;
                while let Ok(ev) = global_hotkey::GlobalHotKeyEvent::receiver().try_recv() {
                    if ev.state == HotKeyState::Pressed {
                        self.toggle_visible(ctx);
                    }
                }
            }
        }
    }

    fn poll_timers(&mut self, ctx: &Context) {
        // 剪贴板 0.6s(对应 NSPasteboard changeCount 轮询)
        if self.last_clip_poll.elapsed() >= Duration::from_millis(600) {
            self.last_clip_poll = Instant::now();
            self.clipboard.poll();
        }
        // 下载目录 2s
        if self.last_dl_refresh.elapsed() >= Duration::from_secs(2) {
            self.last_dl_refresh = Instant::now();
            self.downloads.refresh();
        }
        // 跟随系统主题 2s(注册表 AppsUseLightTheme)
        if self.settings.theme_mode == ThemeMode::System
            && self.last_theme_poll.elapsed() >= Duration::from_secs(2)
        {
            self.last_theme_poll = Instant::now();
            let dark = crate::platform::system_is_dark();
            if dark != self.settings.theme_is_dark {
                self.settings.theme_is_dark = dark;
            }
        }
        // 暂存拖放高亮
        self.ui.shelf_drop = self.settings.tab == PanelTab::Shelf
            && ctx.input(|i| !i.raw.hovered_files.is_empty());
    }

    fn one_shots(&mut self, ctx: &Context) {
        if self.ui.pin_toggled {
            self.ui.pin_toggled = false;
            self.settings.pinned = !self.settings.pinned;
        }
        if self.ui.reset_requested {
            self.ui.reset_requested = false;
            #[cfg(windows)]
            crate::platform::fixup_panel_window(WINDOW_TITLE, true);
        }
        if self.ui.hide_requested {
            self.ui.hide_requested = false;
            self.hide(ctx);
            self.was_focused = false;
        }
        if self.ui.paste_requested {
            self.ui.paste_requested = false;
            // 面板已收起,延迟后向前台应用模拟 Ctrl+V(对应 macOS AutoPaste)
            std::thread::spawn(|| {
                std::thread::sleep(Duration::from_millis(80));
                crate::platform::send_paste();
            });
        }
    }

    fn paint(&mut self, ctx: &Context, dark: bool) {
        let t: ThemeColors = colors(dark);
        egui::CentralPanel::default()
            .frame(egui::Frame::NONE.inner_margin(egui::Margin::same(10)).fill(Color32::TRANSPARENT))
            .show(ctx, |ui| {
                // 整窗圆角背景(窗口透明,四角透出)
                let outer = ui.max_rect().expand(10.0);
                ui.painter().rect_filled(outer, CornerRadius::same(14), t.bg);

                shell::header(ui, &t, &mut self.ui);
                ui.add_space(8.0);
                let counts = self.tab_counts();
                shell::tab_bar(ui, self, &t, counts);
                ui.add_space(8.0);

                let has_music = self.music.snapshot().is_some();
                let card_h = if has_music { 152.0 } else { 0.0 };
                let inner = ui.max_rect();
                let body_top = ui.cursor().top();
                let body_r = Rect::from_min_max(
                    Pos2::new(inner.left(), body_top),
                    Pos2::new(inner.right(), inner.bottom() - card_h),
                );
                let art = self.music_texture(ctx);
                ui.allocate_new_ui(egui::UiBuilder::new().max_rect(body_r), |ui| {
                    views::body(ui, self, &t, ctx);
                });
                if has_music {
                    let card_r = Rect::from_min_max(
                        Pos2::new(inner.left(), inner.bottom() - card_h),
                        Pos2::new(inner.right(), inner.bottom()),
                    );
                    ui.allocate_new_ui(egui::UiBuilder::new().max_rect(card_r), |ui| {
                        shell::music_card(ui, self, &t, art.as_ref());
                    });
                }
            });
    }
}

impl eframe::App for App {
    fn update(&mut self, ctx: &Context, _frame: &mut eframe::Frame) {
        // 首帧:窗口修饰(去任务栏条 + 贴右缘 + 置顶)
        if !self.win_fixed {
            self.win_fixed = true;
            #[cfg(windows)]
            crate::platform::fixup_panel_window(WINDOW_TITLE, true);
        }

        self.poll_platform(ctx);
        self.poll_timers(ctx);

        // 主题生效值 → egui visuals
        let dark = self.settings.theme_is_dark;
        CURRENT_DARK.store(dark, Ordering::Relaxed);
        if self.last_dark != Some(dark) {
            self.last_dark = Some(dark);
            apply_visuals(ctx, dark);
        }

        self.one_shots(ctx);

        // 失焦自动收起(常驻模式除外)
        let focused = ctx.input(|i| i.viewport().focused);
        if focused == Some(true) {
            self.was_focused = true;
        } else if focused == Some(false) && self.was_focused && !self.settings.pinned {
            self.was_focused = false;
            self.hide(ctx);
        }

        // 暂存拖放落盘
        if self.settings.tab == PanelTab::Shelf {
            let dropped = ctx.input(|i| i.raw.dropped_files.clone());
            for f in dropped {
                if let Some(p) = f.path {
                    self.shelf.add(p);
                }
            }
        }

        self.paint(ctx, dark);
        self.persist_settings();

        // 常驻心跳:隐藏状态下也保持轮询(托盘/热键由平台线程推动)
        ctx.request_repaint_after(Duration::from_millis(300));
    }
}

// MARK: - 字体 / 视觉

fn setup_fonts(ctx: &Context) {
    let mut fonts = egui::FontDefinitions::default();
    if let Some(bytes) = crate::platform::load_cjk_font() {
        // 追加为后备字库(拉丁仍用 egui 默认,中文回退到系统字体)
        fonts
            .font_data
            .insert("cjk".to_owned(), egui::FontData::from_owned(bytes).into());
        for family in [egui::FontFamily::Proportional, egui::FontFamily::Monospace] {
            fonts.families.entry(family).or_default().push("cjk".to_owned());
        }
    }
    ctx.set_fonts(fonts);
    // 文本尺寸对齐 macOS 版(13 正文字号)
    let mut style = (*ctx.style()).clone();
    style.text_styles.insert(egui::TextStyle::Body, FontId::proportional(13.0));
    style.text_styles.insert(egui::TextStyle::Button, FontId::proportional(13.0));
    style.text_styles.insert(egui::TextStyle::Small, FontId::proportional(11.0));
    style.text_styles.insert(egui::TextStyle::Heading, FontId::proportional(18.0));
    ctx.set_style(style);
}

fn apply_visuals(ctx: &Context, dark: bool) {
    let mut v = if dark { egui::Visuals::dark() } else { egui::Visuals::light() };
    v.selection.bg_fill = colors(dark).accent.gamma_multiply(0.4);
    v.selection.stroke = egui::Stroke::new(1.0_f32, colors(dark).accent);
    v.widgets.noninteractive.bg_fill = Color32::TRANSPARENT;
    let mut style = (*ctx.style()).clone();
    style.visuals = v;
    ctx.set_style(style);
}

// MARK: - 托盘(仅 Windows)

#[cfg(windows)]
struct TrayHandles {
    _tray: tray_icon::TrayIcon,
    ids: [tray_icon::menu::MenuId; 3],
}

#[cfg(windows)]
fn tray_icon_rgba() -> Option<Vec<u8>> {
    // 32×32 代码绘制:蓝渐变圆角方块 + 白色剪贴板形
    let s = 32usize;
    let mut v = vec![0u8; s * s * 4];
    let radius = 8.0f32;
    let in_rounded = |x: f32, y: f32| {
        let (cx, cy) = (radius, radius);
        let (rx, ry) = (s as f32 - radius, s as f32 - radius);
        // 四角圆角判定
        let corners = [(cx, cy), (rx, cy), (cx, ry), (rx, ry)];
        for (qx, qy) in corners {
            let in_corner_x = (qx == cx && x < cx) || (qx == rx && x > rx);
            let in_corner_y = (qy == cy && y < cy) || (qy == ry && y > ry);
            if in_corner_x && in_corner_y {
                let dx = x - qx;
                let dy = y - qy;
                if dx * dx + dy * dy > radius * radius {
                    return false;
                }
            }
        }
        true
    };
    for y in 0..s {
        for x in 0..s {
            let (xf, yf) = (x as f32 + 0.5, y as f32 + 0.5);
            if !in_rounded(xf, yf) {
                continue;
            }
            let frac = x as f32 / s as f32;
            let r = (59.0 + (50.0 - 59.0) * frac) as u8;
            let g = (130.0 + (191.0 - 130.0) * frac) as u8;
            let b = (246.0 + (241.0 - 246.0) * frac) as u8;
            // 白色剪贴板:板 10..22 × 9..24,夹子 14..18 × 7..11
            let board = (10..22).contains(&x) && (9..24).contains(&y);
            let clip = (14..18).contains(&x) && (7..11).contains(&y);
            let (pr, pg, pb) = if board || clip { (255, 255, 255) } else { (r, g, b) };
            let i = (y * s + x) * 4;
            v[i] = pr;
            v[i + 1] = pg;
            v[i + 2] = pb;
            v[i + 3] = 255;
        }
    }
    Some(v)
}

#[cfg(windows)]
fn setup_tray() -> Option<TrayHandles> {
    use tray_icon::menu::{Menu, MenuItem, PredefinedMenuItem};
    use tray_icon::TrayIconBuilder;
    let icon = tray_icon::Icon::from_rgba(tray_icon_rgba()?, 32, 32).ok()?;
    let menu = Menu::new();
    let show = MenuItem::new("显示面板", true, None);
    let settings = MenuItem::new("设置", true, None);
    let quit = MenuItem::new("退出", true, None);
    menu.append(&show).ok()?;
    menu.append(&settings).ok()?;
    menu.append(&PredefinedMenuItem::separator()).ok()?;
    menu.append(&quit).ok()?;
    let tray = TrayIconBuilder::new()
        .with_menu(Box::new(menu))
        .with_tooltip("SideDock")
        .with_icon(icon)
        .build()
        .ok()?;
    Some(TrayHandles {
        _tray: tray,
        ids: [show.id().clone(), settings.id().clone(), quit.id().clone()],
    })
}

// MARK: - 全局热键(仅 Windows;默认 Ctrl+Alt+S)

#[cfg(windows)]
struct HotkeyHandles {
    _mgr: global_hotkey::GlobalHotKeyManager,
}

#[cfg(windows)]
fn parse_code(s: &str) -> Option<global_hotkey::hotkey::Code> {
    use global_hotkey::hotkey::Code;
    if let Some(c) = s.strip_prefix("Key") {
        let code = match c {
            "A" => Code::KeyA, "B" => Code::KeyB, "C" => Code::KeyC, "D" => Code::KeyD,
            "E" => Code::KeyE, "F" => Code::KeyF, "G" => Code::KeyG, "H" => Code::KeyH,
            "I" => Code::KeyI, "J" => Code::KeyJ, "K" => Code::KeyK, "L" => Code::KeyL,
            "M" => Code::KeyM, "N" => Code::KeyN, "O" => Code::KeyO, "P" => Code::KeyP,
            "Q" => Code::KeyQ, "R" => Code::KeyR, "S" => Code::KeyS, "T" => Code::KeyT,
            "U" => Code::KeyU, "V" => Code::KeyV, "W" => Code::KeyW, "X" => Code::KeyX,
            "Y" => Code::KeyY, "Z" => Code::KeyZ,
            _ => return None,
        };
        return Some(code);
    }
    if let Some(d) = s.strip_prefix("Digit") {
        let code = match d {
            "0" => Code::Digit0, "1" => Code::Digit1, "2" => Code::Digit2, "3" => Code::Digit3,
            "4" => Code::Digit4, "5" => Code::Digit5, "6" => Code::Digit6, "7" => Code::Digit7,
            "8" => Code::Digit8, "9" => Code::Digit9,
            _ => return None,
        };
        return Some(code);
    }
    if let Some(f) = s.strip_prefix('F') {
        if let Ok(n) = f.parse::<u8>() {
            let code = match n {
                1 => Code::F1, 2 => Code::F2, 3 => Code::F3, 4 => Code::F4,
                5 => Code::F5, 6 => Code::F6, 7 => Code::F7, 8 => Code::F8,
                9 => Code::F9, 10 => Code::F10, 11 => Code::F11, 12 => Code::F12,
                _ => return None,
            };
            return Some(code);
        }
    }
    match s {
        "Space" => Some(global_hotkey::hotkey::Code::Space),
        _ => None,
    }
}

#[cfg(windows)]
fn to_hotkey(spec: &crate::settings::HotkeySpec) -> Option<global_hotkey::hotkey::HotKey> {
    use global_hotkey::hotkey::{Code, HotKey, Modifiers};
    let mut mods = Modifiers::empty();
    if spec.ctrl {
        mods |= Modifiers::CONTROL;
    }
    if spec.alt {
        mods |= Modifiers::ALT;
    }
    if spec.shift {
        mods |= Modifiers::SHIFT;
    }
    if spec.win {
        mods |= Modifiers::META;
    }
    let code = parse_code(&spec.code)?;
    let _ = Code::KeyA; // 保持 import 平衡
    Some(HotKey::new(Some(mods), code))
}

#[cfg(windows)]
fn setup_hotkey() -> Option<HotkeyHandles> {
    let mgr = global_hotkey::GlobalHotKeyManager::new().ok()?;
    let spec = load_settings().hotkey.unwrap_or_default();
    if let Some(hk) = to_hotkey(&spec) {
        mgr.register(hk).ok()?;
    }
    Some(HotkeyHandles { _mgr: mgr })
}

// MARK: - 入口

pub fn run() {
    let _ = data_dir(); // 确保数据目录存在
    let options = eframe::NativeOptions {
        viewport: egui::ViewportBuilder::default()
            .with_title(WINDOW_TITLE)
            .with_inner_size([PANEL_W, PANEL_H])
            .with_resizable(false)
            .with_always_on_top()
            .with_transparent(true)
            .with_decorations(false)
            .with_app_id(WINDOW_TITLE.to_owned()),
        ..Default::default()
    };
    eframe::run_native(
        WINDOW_TITLE,
        options,
        Box::new(|cc| Ok(Box::new(App::new(cc)))),
    )
    .expect("SideDock 启动失败");
}
