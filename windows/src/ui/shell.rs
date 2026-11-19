// shell.rs — 面板外壳:日期头 / Tab 胶囊条 / 音乐卡(布局对照原版 promoshot 渲染)
use crate::settings::PanelTab;
use crate::theme::{alpha, h_gradient_rect, ThemeColors};
use crate::ui::widgets::{self, capsule, mmss, text_rect, weekday_cn};
use chrono::Datelike;
use egui::{Color32, CornerRadius, FontId, Pos2, Rect, Sense, Ui, Vec2};

/// 顶部:SD 徽标 + 星期/日期 + ⚙/📌/›
pub fn header(ui: &mut Ui, t: &ThemeColors, st: &mut crate::app::UIState) {
    let w = ui.available_width();
    let (row, _) = ui.allocate_exact_size(Vec2::new(w, 48.0), Sense::hover());
    let p = ui.painter().clone();

    // SD 徽标(34pt 圆角蓝渐变方块,渲染证据 radius 9 font 12)
    let logo = Rect::from_center_size(
        Pos2::new(row.left() + 20.0, row.center().y),
        Vec2::new(34.0, 34.0),
    );
    h_gradient_rect(&p, logo, t.accent, t.accent2, 9.0);
    p.text(
        logo.center(),
        egui::Align2::CENTER_CENTER,
        "SD",
        FontId::proportional(12.0),
        Color32::WHITE,
    );

    // 日期两行:星期 + X月X日
    let now = chrono::Local::now();
    let date_text = format!("{}月{}日", now.month(), now.day());
    p.text(
        Pos2::new(logo.right() + 10.0, row.center().y - 9.0),
        egui::Align2::LEFT_CENTER,
        weekday_cn(now.weekday()),
        FontId::proportional(12.0),
        t.text2,
    );
    p.text(
        Pos2::new(logo.right() + 10.0, row.center().y + 9.0),
        egui::Align2::LEFT_CENTER,
        date_text,
        FontId::proportional(19.0),
        t.text,
    );

    // 右侧三个小按钮:› 📌 ⚙(对应原版 收起/常驻/设置)
    let defs: [(u8, widgets::IconFn); 3] = [
        (0, widgets::icon_chevron),
        (1, widgets::icon_pin),
        (2, widgets::icon_gear),
    ];
    let mut rx = row.right() - 12.0;
    for (icon_id, draw) in defs {
        let hit = Rect::from_center_size(
            Pos2::new(rx - 13.0, row.center().y),
            Vec2::new(26.0, 26.0),
        );
        // interact 而非 allocate_rect:allocate_rect 的光标推进会把后续 Tab 条
        // 顶回头栏行内造成重叠(interact 只注册交互,不动布局光标)
        let resp = ui.interact(hit, ui.id().with(("hdr_btn", icon_id)), Sense::click());
        let color = if resp.hovered() { t.text } else { t.text2 };
        draw(&p, Rect::from_center_size(hit.center(), Vec2::new(18.0, 18.0)), color, 1.8);
        let clicked = resp.clicked();
        match icon_id {
            2 => {
                if clicked {
                    st.settings_open = !st.settings_open;
                }
            }
            1 => {
                if clicked {
                    st.pin_toggled = true;
                }
            }
            _ => {
                if clicked {
                    st.hide_requested = true;
                }
            }
        }
        rx -= 30.0;
    }
}

/// Tab 胶囊条(溢出自动换行,不出横向滚动条;选中渐变 + 徽标,渲染证据:间距 5)
pub fn tab_bar(
    ui: &mut Ui,
    state: &mut crate::app::App,
    t: &ThemeColors,
    counts: [Option<u32>; 6],
) {
    // 溢出换行而非横向滚动;行距略大于默认 3pt,两行时不显挤
    ui.spacing_mut().item_spacing.y = 6.0;
    ui.horizontal_wrapped(|ui| {
        for (i, tab) in PanelTab::ALL.into_iter().enumerate() {
            let selected = state.settings.tab == tab;
            let resp = capsule(
                ui,
                tab.title(),
                12.0,
                Some((widgets::tab_icon_of(tab), 14.0)),
                counts[i],
                selected,
                10.0,
                5.0,
                t,
                Color32::WHITE,
            );
            if resp.clicked() {
                state.settings.tab = tab;
                state.ui.settings_open = false;
            }
            ui.add_space(5.0);
        }
    });
}

/// 底部音乐卡(渲染证据:52 封面 radius 12 / 标题15 / 进度渐变 / 传输键居中间距 56)
pub fn music_card(
    ui: &mut Ui,
    app: &mut crate::app::App,
    t: &ThemeColors,
    art_tex: Option<&egui::TextureHandle>,
) {
    let Some(snap) = app.music.snapshot() else { return };
    const CARD_H: f32 = 150.0;
    let (rect, _) = ui.allocate_exact_size(Vec2::new(ui.available_width(), CARD_H), Sense::hover());
    let p = ui.painter().clone();
    p.rect_filled(rect, CornerRadius::same(14), t.card);

    // 封面 52×52 radius 12
    let art = Rect::from_min_size(rect.left_top() + Vec2::new(14.0, 14.0), Vec2::new(52.0, 52.0));
    if let Some(tex) = art_tex {
        p.image(
            tex.id(),
            art,
            Rect::from_min_size(Pos2::ZERO, Vec2::splat(1.0)),
            Color32::WHITE,
        );
    } else {
        h_gradient_rect(&p, art, t.accent, t.accent2, 12.0);
        widgets::icon_music_note(&p, art.shrink(8.0), Color32::WHITE, 2.0);
    }

    // 标题 / 艺人
    let tx = art.right() + 12.0;
    let max_w = rect.right() - 14.0 - tx;
    let title = clip_to_width(ui, &snap.title, 15.0, max_w);
    p.text(
        Pos2::new(tx, art.top() + 10.0),
        egui::Align2::LEFT_CENTER,
        title,
        FontId::proportional(15.0),
        t.text,
    );
    let artist = clip_to_width(ui, &format!("{}", snap.artist), 12.0, max_w);
    p.text(
        Pos2::new(tx, art.top() + 32.0),
        egui::Align2::LEFT_CENTER,
        artist,
        FontId::proportional(12.0),
        t.text2,
    );

    // 进度条(全宽,高 4,渐变填充)
    let now_secs = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs_f64())
        .unwrap_or(0.0);
    let pos = snap.display_position(now_secs);
    let bar = Rect::from_min_max(
        Pos2::new(rect.left() + 14.0, rect.top() + 82.0),
        Pos2::new(rect.right() - 14.0, rect.top() + 86.0),
    );
    p.rect_filled(bar, CornerRadius::same(2), alpha(t.text, 30));
    if snap.duration_secs > 0.0 {
        let frac = (pos / snap.duration_secs).clamp(0.0, 1.0) as f32;
        if frac > 0.0 {
            let fill =
                Rect::from_min_max(bar.min, Pos2::new(bar.left() + bar.width() * frac, bar.max.y));
            h_gradient_rect(&p, fill, t.accent, t.accent2, 2.0);
        }
    }

    // 时间
    p.text(
        Pos2::new(rect.left() + 14.0, rect.top() + 100.0),
        egui::Align2::LEFT_CENTER,
        mmss(pos),
        FontId::proportional(10.0),
        t.text3,
    );
    p.text(
        Pos2::new(rect.right() - 14.0, rect.top() + 100.0),
        egui::Align2::RIGHT_CENTER,
        mmss(snap.duration_secs),
        FontId::proportional(10.0),
        t.text3,
    );

    // 传输键:prev / play-pause / next(居中,间距 56;媒体键模拟)
    let cy = rect.top() + 128.0;
    type TransportFn = fn(&egui::Painter, Rect, Color32);
    let mut cx = rect.center().x - 56.0;
    let play_icon: TransportFn = if snap.playing { widgets::icon_pause } else { widgets::icon_play };
    for (ki, (size, icon, key)) in [
        (16.0, widgets::icon_prev as TransportFn, crate::platform::MediaKey::Prev),
        (18.0, play_icon, crate::platform::MediaKey::PlayPause),
        (16.0, widgets::icon_next as TransportFn, crate::platform::MediaKey::Next),
    ]
    .into_iter()
    .enumerate()
    {
        let hit = Rect::from_center_size(Pos2::new(cx, cy), Vec2::new(30.0, 30.0));
        let resp = ui.interact(hit, ui.id().with(("music_key", ki)), Sense::click());
        icon(
            &p,
            Rect::from_center_size(hit.center(), Vec2::new(size, size)),
            if resp.hovered() { t.accent } else { t.text },
        );
        if resp.clicked() {
            app.music.control(key);
        }
        cx += 56.0;
    }
}

/// 宽度截断(末尾 …)
fn clip_to_width(ui: &Ui, s: &str, size: f32, max_w: f32) -> String {
    if max_w <= 0.0 {
        return s.to_string();
    }
    if text_rect(ui, s, size).x <= max_w {
        return s.to_string();
    }
    let mut chars: Vec<char> = s.chars().collect();
    while chars.len() > 1 {
        chars.pop();
        let candidate: String = chars.iter().collect::<String>() + "…";
        if text_rect(ui, &candidate, size).x <= max_w {
            return candidate;
        }
    }
    "…".to_string()
}
