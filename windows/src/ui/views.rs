// views.rs — 六个 Tab 视图(布局对照原版 promoshot 渲染与 macOS 版 Views.swift)
use crate::app::App;
use crate::stores::PasswordGenerator;
use crate::theme::{alpha, c, colors, h_gradient_rect, ThemeColors};
use crate::ui::widgets::{
    self, capsule, hoverable, icon_bell, icon_check, icon_eye, icon_file, icon_folder,
    icon_pencil, icon_pin_small, icon_plus, icon_search, icon_trash, icon_wand, icon_x,
    rel_time, text_rect,
};
use chrono::{Duration, Local};
use egui::{
    Color32, Context, CornerRadius, FontId, Key, Pos2, Rect, ScrollArea, Sense, Stroke,
    StrokeKind, TextEdit, Ui, Vec2,
};
use std::time::Instant;

// MARK: - 通用小组件

/// 蓝渐变胶囊按钮(渲染证据:笔记"+ 新建"、密码"+ 添加")
fn pill_button(ui: &mut Ui, t: &ThemeColors, title: &str) -> egui::Response {
    let ts = text_rect(ui, title, 12.0);
    let size = Vec2::new(ts.x + 28.0, ts.y + 12.0);
    let (rect, resp) = ui.allocate_exact_size(size, Sense::click());
    let p = ui.painter().clone();
    h_gradient_rect(&p, rect, t.accent, t.accent2, size.y / 2.0);
    if resp.hovered() {
        p.rect_filled(rect, CornerRadius::same((size.y / 2.0) as u8), Color32::from_rgba_unmultiplied(255, 255, 255, 30));
    }
    p.text(rect.center(), egui::Align2::CENTER_CENTER, title.to_owned(), FontId::proportional(12.0), Color32::WHITE);
    resp
}

/// 小号文字链接(清除 / 全部清除 / 在资源管理器中显示)
fn action_link(ui: &mut Ui, t: &ThemeColors, title: &str, enabled: bool) -> egui::Response {
    let ts = text_rect(ui, title, 12.0);
    let (rect, resp) = ui.allocate_exact_size(Vec2::new(ts.x + 8.0, ts.y + 4.0), Sense::click());
    let color = if enabled { t.accent } else { t.text3 };
    ui.painter().text(
        rect.center(),
        egui::Align2::CENTER_CENTER,
        title.to_owned(),
        FontId::proportional(12.0),
        color,
    );
    resp
}

fn count_text(ui: &mut Ui, t: &ThemeColors, title: &str) {
    let w = text_rect(ui, title, 12.0).x;
    let (rect, _) = ui.allocate_exact_size(Vec2::new(w, 20.0), Sense::hover());
    body_text(ui, rect.center(), egui::Align2::CENTER_CENTER, title, 12.0, t.text2);
}

fn empty_hint(ui: &mut Ui, t: &ThemeColors, text: &str) {
    let (rect, _) = hoverable(ui, Vec2::new(ui.available_width(), 60.0));
    body_text(ui, rect.center(), egui::Align2::CENTER_CENTER, text, 12.0, t.text3);
}

/// 灰卡片(渲染证据 radius 12)
fn card_rect(ui: &mut Ui, t: &ThemeColors, h: f32) -> Rect {
    let (rect, _) = hoverable(ui, Vec2::new(ui.available_width(), h));
    ui.painter().rect_filled(rect, CornerRadius::same(12), t.card);
    rect
}

fn body_text(ui: &Ui, pos: Pos2, anchor: egui::Align2, s: impl Into<String>, size: f32, color: Color32) {
    ui.painter().text(pos, anchor, s.into(), FontId::proportional(size), color);
}

/// 绝对定位的单行输入框;返回 (响应, 是否回车提交)
fn inline_edit(
    ui: &mut Ui,
    rect: Rect,
    buf: &mut String,
    hint: &str,
    size: f32,
    password: bool,
) -> (egui::Response, bool) {
    ui.allocate_new_ui(egui::UiBuilder::new().max_rect(rect), |ui| {
        let mut edit = TextEdit::singleline(buf)
            .hint_text(hint)
            .font(FontId::proportional(size))
            .frame(false)
            .desired_width(rect.width());
        if password {
            edit = edit.password(true);
        }
        let resp = edit.show(ui).response;
        let enter = resp.lost_focus() && ui.input(|i| i.key_pressed(Key::Enter));
        (resp, enter)
    })
    .inner
}

/// 单行截断(字符级,避免多字节 panic)
fn clip_line(ui: &Ui, s: &str, size: f32, max_w: f32) -> String {
    if max_w <= 0.0 || text_rect(ui, s, size).x <= max_w {
        return s.to_string();
    }
    let mut chars: Vec<char> = s.chars().collect();
    while chars.len() > 1 {
        chars.pop();
        let candidate: String = chars.iter().collect::<String>();
        if text_rect(ui, &candidate, size).x <= max_w - 10.0 {
            return candidate + "…";
        }
    }
    "…".to_string()
}

// MARK: - 路由

pub fn body(ui: &mut Ui, app: &mut App, t: &ThemeColors, ctx: &Context) {
    if app.ui.settings_open {
        settings_view(ui, app, t);
        return;
    }
    use crate::settings::PanelTab::*;
    match app.settings.tab {
        Todo => todo_view(ui, app, t),
        Notes => notes_view(ui, app, t),
        Downloads => downloads_view(ui, app, t),
        Shelf => shelf_view(ui, app, t),
        Passwords => passwords_view(ui, app, t),
        Clipboard => clipboard_view(ui, app, t, ctx),
    }
}

// MARK: - 待办(渲染证据:输入卡+蓝圆加号 / 到期胶囊 / 分组计数胶囊 / 圆形勾选行)

fn todo_view(ui: &mut Ui, app: &mut App, t: &ThemeColors) {
    let today = Local::now().date_naive();
    ui.add_space(4.0);

    // 输入卡(输入行 + 到期胶囊行同处一张灰卡)
    let card = card_rect(ui, t, 76.0);
    let p = ui.painter().clone();
    // 加号圆钮
    let plus_r = Rect::from_center_size(
        Pos2::new(card.left() + 30.0, card.top() + 22.0),
        Vec2::new(24.0, 24.0),
    );
    let plus_resp = ui.allocate_rect(plus_r, Sense::click());
    h_gradient_rect(&p, plus_r.shrink(1.0), t.accent, t.accent2, 12.0);
    icon_plus(&p, plus_r.shrink(6.0), Color32::WHITE, 2.2);
    // 输入框(绝对定位到加号同行)
    let er = Rect::from_min_max(
        Pos2::new(card.left() + 52.0, card.top() + 10.0),
        Pos2::new(card.right() - 12.0, card.top() + 34.0),
    );
    let (_resp, enter) = inline_edit(ui, er, &mut app.ui.todo_draft, "添加待办，回车保存", 13.0, false);

    // 到期预设行
    let preset_y = card.top() + 54.0;
    body_text(ui, Pos2::new(card.left() + 14.0, preset_y), egui::Align2::LEFT_CENTER, "到期：", 12.0, t.text2);
    let mut px = card.left() + 52.0;
    for (label, idx) in [("今日", 1u8), ("明日", 2), ("一周", 3), ("历史", 4)] {
        let on = idx != 4 && app.ui.todo_preset == idx;
        let ts = text_rect(ui, label, 11.0);
        let pill = Rect::from_min_size(Pos2::new(px, preset_y - 13.0), Vec2::new(ts.x + 20.0, 26.0));
        let resp = ui.allocate_rect(pill, Sense::click());
        if on {
            h_gradient_rect(&p, pill, t.accent, t.accent2, 13.0);
        } else {
            p.rect_filled(pill, CornerRadius::same(13), t.pill);
        }
        body_text(ui, pill.center(), egui::Align2::CENTER_CENTER, label, 11.0, if on { Color32::WHITE } else { t.text });
        if resp.clicked() {
            if idx == 4 {
                app.ui.todo_filter = 4; // 历史:跳到历史分组
            } else {
                app.ui.todo_preset = idx;
            }
        }
        px += pill.width() + 6.0;
    }
    if enter || plus_resp.clicked() {
        todo_add(app, today);
    }

    ui.add_space(8.0);
    // 分组筛选(今日/明日/一周/历史 四枚带计数胶囊,渲染证据无"全部")
    ui.horizontal(|ui| {
        for (label, idx) in [("今日", 1u8), ("明日", 2), ("一周", 3), ("历史", 4)] {
            let n = app.todos.count_for(idx, today);
            let label = format!("{label} {n}");
            let selected = app.ui.todo_filter == idx;
            let resp = capsule(ui, &label, 11.0, None, None, selected, 9.0, 5.0, t, Color32::WHITE);
            if resp.clicked() {
                app.ui.todo_filter = idx;
            }
            ui.add_space(6.0);
        }
    });
    ui.add_space(6.0);

    let rows: Vec<_> = app
        .todos
        .items
        .iter()
        .filter(|it| app.todos.matches(it, app.ui.todo_filter, today))
        .cloned()
        .collect();
    if rows.is_empty() {
        empty_hint(ui, t, "暂无待办");
        return;
    }
    ScrollArea::vertical().auto_shrink([false, false]).show(ui, |ui| {
        for item in rows {
            todo_row(ui, app, t, &item);
            ui.add_space(6.0);
        }
    });
}

fn todo_add(app: &mut App, today: chrono::NaiveDate) {
    let text = app.ui.todo_draft.trim().to_string();
    if text.is_empty() {
        return;
    }
    let due = crate::todo::TodoStore::due_date_for_preset(app.ui.todo_preset, Local::now());
    let item = crate::todo::TodoItem::new(text.clone(), due);
    let bucket = app.todos.bucket_of(&item, today);
    app.todos.add(&text, due);
    app.ui.todo_draft.clear();
    // 新增后跳到新条目所在分组,保证"添加立刻可见"(否则像没加上一样)
    app.ui.todo_filter = bucket;
}

fn todo_row(ui: &mut Ui, app: &mut App, t: &ThemeColors, item: &crate::todo::TodoItem) {
    let h = 34.0;
    let (rect, hresp) = ui.allocate_exact_size(Vec2::new(ui.available_width(), h), Sense::click());
    let hovered = hresp.hovered();
    let p = ui.painter().clone();
    p.rect_filled(rect, CornerRadius::same(12), t.card);

    // 勾选圆
    let circ = Rect::from_center_size(
        Pos2::new(rect.left() + 20.0, rect.center().y),
        Vec2::new(17.0, 17.0),
    );
    let check_resp = ui.allocate_rect(circ.expand(4.0), Sense::click());
    if item.done {
        p.circle_filled(circ.center(), 8.5, t.accent);
        icon_check(&p, circ.shrink(2.0), Color32::WHITE, 2.0);
    } else {
        p.circle_stroke(circ.center(), 8.0, Stroke::new(1.6_f32, t.text3));
    }
    if check_resp.clicked() {
        app.todos.toggle(item.id);
    }

    // 标题(+完成删除线)
    let tx = rect.left() + 34.0;
    let title = clip_line(ui, &item.title, 14.0, rect.width() - 150.0);
    body_text(ui, Pos2::new(tx, rect.center().y), egui::Align2::LEFT_CENTER, title.clone(), 14.0, if item.done { t.text3 } else { t.text });
    if item.done {
        let tw = text_rect(ui, &title, 14.0).x;
        p.line_segment([Pos2::new(tx, rect.center().y), Pos2::new(tx + tw, rect.center().y)], Stroke::new(1.0_f32, t.text3));
    }

    // 右侧状态 + 悬停删除(渲染证据:行上不常显删除按钮,悬停才出现)
    let now = Local::now();
    let mut rx = rect.right() - 10.0;
    if hovered {
        let xr = Rect::from_center_size(Pos2::new(rx - 8.0, rect.center().y), Vec2::new(14.0, 14.0));
        let resp = ui.allocate_rect(xr.expand(4.0), Sense::click());
        icon_x(&p, xr, alpha(t.text3, 180), 1.8);
        if resp.clicked() {
            app.todos.remove(item.id);
            return;
        }
        rx -= 24.0;
    }
    if item.done {
        let label = "标记为未完成";
        let tw = text_rect(ui, label, 10.0).x;
        let lr = Rect::from_min_size(Pos2::new(rx - tw, rect.center().y - 8.0), Vec2::new(tw, 16.0));
        let resp = ui.allocate_rect(lr.expand(2.0), Sense::click());
        body_text(ui, lr.center(), egui::Align2::CENTER_CENTER, label, 10.0, if resp.hovered() { t.text2 } else { t.text3 });
        if resp.clicked() {
            app.todos.toggle(item.id);
        }
    } else if let Some(due) = item.due {
        if due < now {
            body_text(ui, Pos2::new(rx, rect.center().y), egui::Align2::RIGHT_CENTER, "已逾期", 11.0, t.danger);
        } else if due < now + Duration::hours(2) {
            // 渲染证据:只对 2 小时内即将到期的行显示铃铛时间
            let label = due.format("%H:%M").to_string();
            let tw = text_rect(ui, &label, 11.0).x;
            body_text(ui, Pos2::new(rx, rect.center().y), egui::Align2::RIGHT_CENTER, label, 11.0, t.accent);
            icon_bell(&p, Rect::from_center_size(Pos2::new(rx - tw - 8.0, rect.center().y), Vec2::new(10.0, 10.0)), t.accent, 1.2);
        }
    }
}

// MARK: - 笔记(渲染证据:"N 张" + 新建胶囊 / 标题+摘要+时间卡片)

fn notes_view(ui: &mut Ui, app: &mut App, t: &ThemeColors) {
    ui.add_space(4.0);
    ui.horizontal(|ui| {
        count_text(ui, t, &format!("{} 张", app.notes.notes.len()));
        ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
            if pill_button(ui, t, "＋ 新建").clicked() {
                app.ui.notes_adding = !app.ui.notes_adding;
            }
        });
    });

    if app.ui.notes_adding {
        let card = card_rect(ui, t, 40.0);
        let er = Rect::from_min_max(
            Pos2::new(card.left() + 12.0, card.top() + 8.0),
            Pos2::new(card.right() - 44.0, card.bottom() - 8.0),
        );
        let (_resp, enter) = inline_edit(ui, er, &mut app.ui.notes_draft, "回车保存,首行为标题", 13.0, false);
        let br = Rect::from_center_size(
            Pos2::new(card.right() - 22.0, card.center().y),
            Vec2::new(20.0, 20.0),
        );
        let bresp = ui.allocate_rect(br.expand(3.0), Sense::click());
        widgets::icon_arrow_up(ui.painter(), br, t.accent, 2.0);
        if enter || bresp.clicked() {
            let text = app.ui.notes_draft.trim().to_string();
            if !text.is_empty() {
                app.notes.insert_top(text);
                app.ui.notes_draft.clear();
                app.ui.notes_adding = false;
            }
        }
        ui.add_space(8.0);
    }

    if app.notes.notes.is_empty() {
        empty_hint(ui, t, "还没有笔记");
        return;
    }
    ScrollArea::vertical().auto_shrink([false, false]).show(ui, |ui| {
        for note in app.notes.notes.clone() {
            let (rect, hresp) = ui.allocate_exact_size(Vec2::new(ui.available_width(), 64.0), Sense::click());
            let hovered = hresp.hovered();
            let p = ui.painter().clone();
            p.rect_filled(rect, CornerRadius::same(14), t.card);
            body_text(
                ui,
                Pos2::new(rect.left() + 12.0, rect.top() + 16.0),
                egui::Align2::LEFT_CENTER,
                clip_line(ui, &note.title_line(), 13.0, rect.width() - 24.0),
                13.0,
                t.text,
            );
            let body = note.body_line();
            if !body.is_empty() {
                body_text(
                    ui,
                    Pos2::new(rect.left() + 12.0, rect.top() + 34.0),
                    egui::Align2::LEFT_CENTER,
                    clip_line(ui, &body, 11.0, rect.width() - 24.0),
                    11.0,
                    t.text2,
                );
            }
            body_text(
                ui,
                Pos2::new(rect.left() + 12.0, rect.bottom() - 12.0),
                egui::Align2::LEFT_CENTER,
                rel_time(&note.created_at),
                10.0,
                t.text3,
            );
            // 渲染证据:卡片上不常显删除按钮,悬停才出现
            if hovered {
                let xr = Rect::from_center_size(
                    Pos2::new(rect.right() - 14.0, rect.bottom() - 12.0),
                    Vec2::new(12.0, 12.0),
                );
                let resp = ui.allocate_rect(xr.expand(3.0), Sense::click());
                icon_x(&p, xr, alpha(t.text3, 180), 1.8);
                if resp.clicked() {
                    app.notes.remove(note.id);
                }
            }
            ui.add_space(8.0);
        }
    });
}

// MARK: - 分段控件(渲染证据:紧凑灰底圆角容器,白底描边选中段)
// 颜色全部走主题 token:系统动态色在深色下会白字白底(macOS 版踩过的坑)

fn segmented(ui: &mut Ui, t: &ThemeColors, options: &[&str], selected: usize) -> Option<usize> {
    let dark = crate::app::current_dark();
    let track = if dark { c(0x262629) } else { c(0xE4E4E7) };
    let sel_fill = if dark { c(0x3A3A3E) } else { Color32::WHITE };
    let sel_stroke = if dark { c(0x4A4A4E) } else { c(0xD6D6DA) };
    let mut out = None;
    let mut total_w = 4.0;
    for (i, o) in options.iter().enumerate() {
        total_w += text_rect(ui, o, 12.0).x + 32.0;
        if i + 1 < options.len() {
            total_w += 4.0;
        }
    }
    let h = 26.0;
    let (rect, _) = hoverable(ui, Vec2::new(total_w, h + 4.0));
    let p = ui.painter().clone();
    p.rect_filled(rect, CornerRadius::same(8), track);
    let mut sx = rect.left() + 2.0;
    for (i, o) in options.iter().enumerate() {
        let tw = text_rect(ui, o, 12.0).x + 32.0;
        let cell = Rect::from_min_size(Pos2::new(sx, rect.top() + 2.0), Vec2::new(tw, h));
        let cresp = ui.allocate_rect(cell, Sense::click());
        if i == selected {
            p.rect_filled(cell, CornerRadius::same(6), sel_fill);
            p.rect_stroke(cell, CornerRadius::same(6), Stroke::new(1.0_f32, sel_stroke), StrokeKind::Inside);
        }
        body_text(ui, cell.center(), egui::Align2::CENTER_CENTER, *o, 12.0, if i == selected { t.text } else { t.text2 });
        if cresp.clicked() {
            out = Some(i);
        }
        sx += tw + 4.0;
    }
    out
}

fn search_capsule(ui: &mut Ui, t: &ThemeColors, buf: &mut String, placeholder: &str) {
    let w = ui.available_width();
    let (rect, _) = hoverable(ui, Vec2::new(w, 30.0));
    let p = ui.painter().clone();
    p.rect_filled(rect, CornerRadius::same(15), t.pill);
    icon_search(&p, Rect::from_center_size(Pos2::new(rect.left() + 15.0, rect.center().y), Vec2::new(12.0, 12.0)), t.text3, 1.6);
    let tr = Rect::from_min_max(
        Pos2::new(rect.left() + 27.0, rect.top() + 3.0),
        Pos2::new(rect.right() - if buf.is_empty() { 10.0 } else { 28.0 }, rect.bottom() - 3.0),
    );
    let _ = inline_edit(ui, tr, buf, placeholder, 12.0, false);
    if !buf.is_empty() {
        let xr = Rect::from_center_size(
            Pos2::new(rect.right() - 14.0, rect.center().y),
            Vec2::new(12.0, 12.0),
        );
        let xresp = ui.allocate_rect(xr.expand(3.0), Sense::click());
        icon_x(&p, xr, t.text3, 1.6);
        if xresp.clicked() {
            buf.clear();
        }
    }
}

// MARK: - 下载(渲染证据:最近|全部 分段 + 搜索胶囊 + 文件夹按钮 / 今天、昨天分组行)

fn downloads_view(ui: &mut Ui, app: &mut App, t: &ThemeColors) {
    ui.add_space(4.0);
    let mut seg_changed = None;
    ui.horizontal(|ui| {
        if let Some(sel) = segmented(ui, t, &["最近", "全部"], if app.ui.downloads_all { 1 } else { 0 }) {
            seg_changed = Some(sel);
        }
        ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
            let (_frect, fresp) = ui.allocate_exact_size(Vec2::new(26.0, 26.0), Sense::click());
            icon_folder(ui.painter(), _frect.shrink(3.0), t.text2, 1.7);
            if fresp.clicked() {
                crate::platform::open_path(&crate::downloads::DownloadsStore::downloads_dir());
            }
        });
    });
    if let Some(sel) = seg_changed {
        app.ui.downloads_all = sel == 1;
        app.downloads.recent_only = !app.ui.downloads_all;
        app.downloads.refresh();
    }
    ui.add_space(4.0);
    search_capsule(ui, t, &mut app.ui.downloads_search, "搜索");
    ui.add_space(8.0);

    if app.downloads.read_error {
        empty_hint(ui, t, "无法读取“下载”文件夹");
        return;
    }
    let q = app.ui.downloads_search.to_lowercase();
    let shown: Vec<_> = app
        .downloads
        .files
        .iter()
        .filter(|f| q.is_empty() || f.name.to_lowercase().contains(&q))
        .cloned()
        .collect();
    if shown.is_empty() {
        empty_hint(
            ui,
            t,
            if app.downloads.recent_only { "最近 3 天没有新下载" } else { "没有匹配的文件" },
        );
        return;
    }
    ScrollArea::vertical().auto_shrink([false, false]).show(ui, |ui| {
        let mut last_group = None;
        for f in shown {
            let group = crate::downloads::DownloadGroup::of(&f.date);
            if Some(group) != last_group {
                let (grect, _) = ui.allocate_exact_size(Vec2::new(ui.available_width(), 18.0), Sense::hover());
                body_text(ui, Pos2::new(grect.left(), grect.center().y), egui::Align2::LEFT_CENTER, group.title(), 11.0, t.text2);
                last_group = Some(group);
            }
            download_row(ui, app, t, &f);
            ui.add_space(2.0);
        }
    });
}

fn download_row(ui: &mut Ui, app: &mut App, t: &ThemeColors, f: &crate::downloads::DownloadFile) {
    let h = 48.0;
    let (rect, resp) = ui.allocate_exact_size(Vec2::new(ui.available_width(), h), Sense::click());
    let hovered = resp.hovered();
    let p = ui.painter().clone();
    // 文件图标 40×40 radius 9
    let ic = Rect::from_min_size(rect.left_top() + Vec2::new(4.0, 4.0), Vec2::new(40.0, 40.0));
    p.rect_filled(ic, CornerRadius::same(9), t.pill);
    icon_file(&p, ic.shrink(8.0), t.text2, 1.6);
    // 名称
    let name = clip_line(ui, &f.name, 13.0, rect.width() - 150.0);
    body_text(ui, Pos2::new(ic.right() + 8.0, rect.top() + 16.0), egui::Align2::LEFT_CENTER, name, 13.0, t.text);
    // 元信息(渲染证据:下载中…橙色 / 大小 · 相对时间)
    let mut meta = String::new();
    if f.is_partial {
        meta.push_str("下载中… ");
    }
    meta.push_str(&f.size_text());
    meta.push_str(" · ");
    meta.push_str(&rel_time(&f.date));
    let meta_color = if f.is_partial { c(0xE8A33D) } else { t.text2 };
    body_text(ui, Pos2::new(ic.right() + 8.0, rect.top() + 34.0), egui::Align2::LEFT_CENTER, meta, 10.0, meta_color);
    // 悬停操作:打开 / 在资源管理器中显示 / 移到回收站
    if hovered {
        let mut bx = rect.right() - 10.0;
        let actions = [(icon_file as widgets::IconFn, 0u8), (widgets::icon_folder as widgets::IconFn, 1), (icon_trash as widgets::IconFn, 2)];
        for (icon, action) in actions {
            let br = Rect::from_center_size(Pos2::new(bx - 9.0, rect.center().y), Vec2::new(18.0, 18.0));
            let bresp = ui.allocate_rect(br.expand(2.0), Sense::click());
            icon(&p, br, if bresp.hovered() { t.accent } else { t.text3 }, 1.6);
            if bresp.clicked() {
                match action {
                    0 => app.downloads.open(f),
                    1 => app.downloads.reveal(f),
                    _ => app.downloads.trash(f),
                }
            }
            bx -= 26.0;
        }
    }
    if resp.double_clicked() {
        app.downloads.open(f);
    }
}

// MARK: - 暂存(文件货架;拖放由 app 层统一处理)

fn shelf_view(ui: &mut Ui, app: &mut App, t: &ThemeColors) {
    ui.add_space(4.0);
    ui.horizontal(|ui| {
        count_text(ui, t, &format!("{} 个文件", app.shelf.items.len()));
        ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
            let has = !app.shelf.items.is_empty();
            if action_link(ui, t, "清空", has).clicked() && has {
                app.shelf.clear();
            }
            if action_link(ui, t, "在资源管理器中显示", has).clicked() && has {
                for it in app.shelf.items.clone() {
                    crate::platform::reveal_in_explorer(&it.path);
                }
            }
        });
    });
    ui.add_space(4.0);

    if app.shelf.items.is_empty() {
        let w = ui.available_width();
        let (rect, _) = hoverable(ui, Vec2::new(w, 190.0));
        let p = ui.painter().clone();
        let color = if app.ui.shelf_drop { t.accent } else { t.border };
        p.rect_stroke(rect, CornerRadius::same(14), Stroke::new(1.2_f32, color), StrokeKind::Inside);
        p.text(
            rect.center() - Vec2::new(0.0, 12.0),
            egui::Align2::CENTER_CENTER,
            "把文件拖到这里暂存",
            FontId::proportional(12.0),
            t.text3,
        );
        p.text(
            rect.center() + Vec2::new(0.0, 10.0),
            egui::Align2::CENTER_CENTER,
            "暂存只记录文件位置,不会复制文件",
            FontId::proportional(10.0),
            alpha(t.text3, 200),
        );
        return;
    }
    ScrollArea::vertical().auto_shrink([false, false]).show(ui, |ui| {
        let items = app.shelf.items.clone();
        let cols = 3; // 渲染证据:360pt 面板下文件网格为 3 列
        let gap = 8.0;
        let cell_w = (ui.available_width() - gap * (cols - 1) as f32) / cols as f32;
        let cell_h = 86.0;
        for row_start in (0..items.len()).step_by(cols) {
            ui.horizontal(|ui| {
                for j in 0..cols {
                    let idx = row_start + j;
                    if idx >= items.len() {
                        break;
                    }
                    let it = &items[idx];
                    let (rect, resp) = ui.allocate_exact_size(Vec2::new(cell_w, cell_h), Sense::click());
                    let hovered = resp.hovered();
                    let p = ui.painter().clone();
                    p.rect_filled(rect, CornerRadius::same(14), t.card);
                    let ic = Rect::from_center_size(
                        Pos2::new(rect.center().x, rect.top() + 26.0),
                        Vec2::new(36.0, 36.0),
                    );
                    icon_file(&p, ic, t.text2, 1.7);
                    let name = it.path.file_name().map(|s| s.to_string_lossy().to_string()).unwrap_or_default();
                    let name = clip_line(ui, &name, 11.0, cell_w - 14.0);
                    p.text(
                        Pos2::new(rect.center().x, rect.bottom() - 16.0),
                        egui::Align2::CENTER_CENTER,
                        name,
                        FontId::proportional(11.0),
                        t.text,
                    );
                    if hovered {
                        let xr = Rect::from_center_size(
                            Pos2::new(rect.right() - 11.0, rect.top() + 11.0),
                            Vec2::new(12.0, 12.0),
                        );
                        let xresp = ui.allocate_rect(xr.expand(3.0), Sense::click());
                        icon_x(&p, xr, alpha(t.text3, 200), 1.8);
                        if xresp.clicked() {
                            app.shelf.remove(it.id);
                        }
                    }
                    if resp.clicked() {
                        crate::platform::open_path(&it.path);
                    }
                    if j + 1 < cols {
                        ui.add_space(gap);
                    }
                }
            });
            ui.add_space(gap);
        }
    });
}

// MARK: - 密码(渲染证据:浅蓝钥匙块 + 站点/账号 + 眼睛)

fn passwords_view(ui: &mut Ui, app: &mut App, t: &ThemeColors) {
    ui.add_space(4.0);
    ui.horizontal(|ui| {
        count_text(ui, t, &format!("共 {} 条", app.vault.entries.len()));
        ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
            if pill_button(ui, t, "＋ 添加").clicked() {
                app.ui.vault_adding = !app.ui.vault_adding;
            }
        });
    });
    ui.add_space(4.0);

    if app.ui.vault_adding {
        let card = card_rect(ui, t, 158.0);
        let mut y = card.top() + 8.0;
        let field_w = card.width() - 60.0;
        let mut texts = [
            std::mem::take(&mut app.ui.vault_site),
            std::mem::take(&mut app.ui.vault_account),
            std::mem::take(&mut app.ui.vault_phone),
            std::mem::take(&mut app.ui.vault_password),
        ];
        let fields = [
            ("网站 / 用途", 0usize),
            ("手机号 / 邮箱 / 用户名", 1),
            ("绑定的手机号(可选)", 2),
            ("密码(留空 = 稍后补填)", 3),
        ];
        let mut generate = false;
        for (hint, idx) in fields {
            let fr = Rect::from_min_max(
                Pos2::new(card.left() + 12.0, y),
                Pos2::new(card.left() + 12.0 + field_w, y + 26.0),
            );
            let (_r, _e) = inline_edit(ui, fr, &mut texts[idx], hint, 12.0, idx == 3);
            if idx == 3 {
                let wr = Rect::from_center_size(
                    Pos2::new(card.right() - 26.0, y + 13.0),
                    Vec2::new(18.0, 18.0),
                );
                let wresp = ui.allocate_rect(wr.expand(3.0), Sense::click());
                icon_wand(ui.painter(), wr, t.accent, 1.7);
                if wresp.clicked() {
                    generate = true;
                }
            }
            y += 30.0;
        }
        if generate {
            texts[3] = PasswordGenerator::generate(20, true);
        }
        app.ui.vault_site = texts[0].clone();
        app.ui.vault_account = texts[1].clone();
        app.ui.vault_phone = texts[2].clone();
        app.ui.vault_password = texts[3].clone();

        // 保存 / 取消
        let save_r = Rect::from_min_size(Pos2::new(card.left() + 12.0, y), Vec2::new(64.0, 26.0));
        let save = ui.allocate_rect(save_r, Sense::click());
        h_gradient_rect(ui.painter(), save_r, t.accent, t.accent2, 6.0);
        body_text(ui, save_r.center(), egui::Align2::CENTER_CENTER, "保存", 12.0, Color32::WHITE);
        let cancel_r = Rect::from_min_size(Pos2::new(save_r.right() + 10.0, y), Vec2::new(64.0, 26.0));
        let cancel = ui.allocate_rect(cancel_r, Sense::click());
        body_text(ui, cancel_r.center(), egui::Align2::CENTER_CENTER, "取消", 12.0, t.text2);
        let can_save = !app.ui.vault_site.trim().is_empty() && !app.ui.vault_account.trim().is_empty();
        if cancel.clicked() {
            app.ui.vault_adding = false;
            app.ui.vault_site.clear();
            app.ui.vault_account.clear();
            app.ui.vault_phone.clear();
            app.ui.vault_password.clear();
        }
        if save.clicked() && can_save {
            let mut entry = crate::stores::VaultEntry::new(
                app.ui.vault_site.trim().to_string(),
                app.ui.vault_account.trim().to_string(),
            );
            if !app.ui.vault_phone.trim().is_empty() {
                entry.phone = Some(app.ui.vault_phone.trim().to_string());
            }
            let pw = if app.ui.vault_password.is_empty() { None } else { Some(app.ui.vault_password.as_str()) };
            match app.vault.add(entry, pw) {
                Ok(()) => {
                    app.ui.vault_adding = false;
                    app.ui.vault_site.clear();
                    app.ui.vault_account.clear();
                    app.ui.vault_phone.clear();
                    app.ui.vault_password.clear();
                }
                Err(e) => {
                    app.ui.vault_toast = Some((e, Instant::now() + std::time::Duration::from_secs(3)))
                }
            }
        }
        ui.add_space(8.0);
    }

    // toast
    if let Some((msg, until)) = app.ui.vault_toast.clone() {
        if Instant::now() < until {
            let (trect, _) = ui.allocate_exact_size(Vec2::new(ui.available_width(), 18.0), Sense::hover());
            body_text(ui, Pos2::new(trect.left(), trect.center().y), egui::Align2::LEFT_CENTER, msg, 11.0, c(0x34C759));
        } else {
            app.ui.vault_toast = None;
        }
    }

    if app.vault.entries.is_empty() {
        empty_hint(ui, t, "暂无保存的密码");
        return;
    }
    ScrollArea::vertical().auto_shrink([false, false]).show(ui, |ui| {
        for e in app.vault.entries.clone() {
            vault_row(ui, app, t, &e);
            ui.add_space(8.0);
        }
    });
}

fn vault_row(ui: &mut Ui, app: &mut App, t: &ThemeColors, e: &crate::stores::VaultEntry) {
    let editing = app.ui.vault_edit_for == Some(e.id);
    let h = if editing { 94.0 } else { 60.0 };
    let (rect, _) = hoverable(ui, Vec2::new(ui.available_width(), h));
    let hovered = ui.rect_contains_pointer(rect);
    let p = ui.painter().clone();
    p.rect_filled(rect, CornerRadius::same(14), t.card);
    // 钥匙块
    let kb = Rect::from_min_size(rect.left_top() + Vec2::new(12.0, 12.0), Vec2::new(36.0, 36.0));
    p.rect_filled(
        kb,
        CornerRadius::same(10),
        if crate::app::current_dark() { alpha(t.accent, 46) } else { c(0xDDEBFF) },
    );
    widgets::icon_key(&p, kb.shrink(8.0), t.accent, 1.8);
    // 站点 / 账号(或揭示的密码)
    body_text(ui, Pos2::new(kb.right() + 10.0, rect.top() + 20.0), egui::Align2::LEFT_CENTER, e.site.clone(), 13.0, t.text);
    let revealing = app.ui.vault_reveal_for == Some(e.id);
    let acc = if revealing {
        app.ui.vault_reveal_text.clone().unwrap_or_else(|| e.account.clone())
    } else {
        e.account.clone()
    };
    body_text(ui, Pos2::new(kb.right() + 10.0, rect.top() + 40.0), egui::Align2::LEFT_CENTER, acc, 11.0, if revealing { t.text } else { t.text2 });
    // 右侧:未保存密码标记 / 眼睛 / 悬停(编辑、删除)
    let mut rx = rect.right() - 12.0;
    if hovered {
        for (icon, action) in [(icon_trash as widgets::IconFn, 2u8), (icon_pencil as widgets::IconFn, 1)] {
            let br = Rect::from_center_size(Pos2::new(rx - 9.0, rect.center().y), Vec2::new(18.0, 18.0));
            let resp = ui.allocate_rect(br.expand(2.0), Sense::click());
            icon(&p, br, if resp.hovered() { t.accent } else { t.text3 }, 1.7);
            if resp.clicked() {
                match action {
                    1 => {
                        app.ui.vault_edit_for = Some(e.id);
                        app.ui.vault_edit_pw.clear();
                    }
                    _ => app.vault.remove(e.id),
                }
            }
            rx -= 26.0;
        }
    }
    let has_pw = e.has_password();
    if !has_pw {
        let label = "未保存密码";
        let tw = text_rect(ui, label, 9.0).x;
        body_text(ui, Pos2::new(rx - tw / 2.0, rect.center().y), egui::Align2::CENTER_CENTER, label, 9.0, c(0xE8A33D));
        rx -= tw + 8.0;
    }
    let eye_r = Rect::from_center_size(Pos2::new(rx - 9.0, rect.center().y), Vec2::new(18.0, 18.0));
    let eresp = ui.allocate_rect(eye_r.expand(2.0), Sense::click());
    icon_eye(&p, eye_r, if eresp.hovered() { t.text } else { t.text2 }, 1.7);
    if eresp.clicked() {
        if revealing {
            app.ui.vault_reveal_for = None;
            app.ui.vault_reveal_text = None;
        } else if let Some(pw) = e.reveal() {
            app.ui.vault_reveal_for = Some(e.id);
            app.ui.vault_reveal_text = Some(pw);
            // 12s 后自动隐藏
            app.ui.vault_reveal_until = Some((e.id, Instant::now() + std::time::Duration::from_secs(12)));
        } else {
            app.ui.vault_toast = Some(("未找到保存的密码".into(), Instant::now() + std::time::Duration::from_secs(2)));
        }
    }

    // 揭示超时
    if let Some((id, until)) = &app.ui.vault_reveal_until {
        if Instant::now() > *until {
            app.ui.vault_reveal_for = None;
            app.ui.vault_reveal_text = None;
            app.ui.vault_reveal_until = None;
        } else if *id != e.id && revealing {
            // 只显示一条
        }
    }

    // 内联编辑密码(渲染证据:右键编辑重新输入一次)
    if editing {
        let er = Rect::from_min_max(
            Pos2::new(rect.left() + 12.0, rect.bottom() - 30.0),
            Pos2::new(rect.right() - 90.0, rect.bottom() - 4.0),
        );
        let (_r, enter) = inline_edit(ui, er, &mut app.ui.vault_edit_pw, "重新输入密码", 12.0, true);
        let sr = Rect::from_min_max(
            Pos2::new(er.right() + 8.0, er.top()),
            Pos2::new(er.right() + 72.0, er.bottom()),
        );
        let sresp = ui.allocate_rect(sr, Sense::click());
        h_gradient_rect(&p, sr, t.accent, t.accent2, 6.0);
        body_text(ui, sr.center(), egui::Align2::CENTER_CENTER, "保存", 12.0, Color32::WHITE);
        let save_hit = sresp.clicked() || (enter && !app.ui.vault_edit_pw.is_empty());
        if save_hit && !app.ui.vault_edit_pw.is_empty() {
            if app.vault.update_password(e.id, &app.ui.vault_edit_pw).is_ok() {
                app.ui.vault_edit_for = None;
                app.ui.vault_edit_pw.clear();
            }
        }
    }
}

// MARK: - 剪贴板(Maccy 式:搜索 / 固定区分隔 / 来源图标 / 键盘导航 / 选中即复制)

fn clipboard_view(ui: &mut Ui, app: &mut App, t: &ThemeColors, ctx: &Context) {
    ui.add_space(4.0);
    search_capsule(ui, t, &mut app.ui.clip_search, "搜索…");
    ui.add_space(6.0);

    // 计数行 + toast + 清除(Maccy:清除 = 清未固定;⇧/全部清除是增强)
    ui.horizontal(|ui| {
        count_text(ui, t, &format!("{} 条 · 纯本地保存", app.clipboard.entries.len()));
        if let Some((msg, until)) = app.ui.clip_toast.clone() {
            if Instant::now() < until {
                let w = text_rect(ui, &msg, 11.0).x + 10.0;
                let (trect, _) = ui.allocate_exact_size(Vec2::new(w, 18.0), Sense::hover());
                body_text(ui, trect.center(), egui::Align2::LEFT_CENTER, msg, 11.0, t.accent);
            } else {
                app.ui.clip_toast = None;
            }
        }
        ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
            let has_any = !app.clipboard.entries.is_empty();
            if action_link(ui, t, "全部清除", has_any).clicked() && has_any {
                app.clipboard.clear_all();
                app.ui.clip_search.clear();
                app.ui.clip_selected = None;
            }
            let has_unpinned = app.clipboard.entries.iter().any(|e| !e.is_pinned());
            if action_link(ui, t, "清除", has_unpinned).clicked() && has_unpinned {
                app.clipboard.clear_unpinned();
            }
        });
    });
    ui.add_space(4.0);

    // 键盘导航(证据:_selectionIndex;↑↓/↩/Esc,Maccy 同)
    let rows = app.clipboard.visible(&app.ui.clip_search);
    let (down, up, enter, esc) = ctx.input(|i| {
        (
            i.key_pressed(Key::ArrowDown),
            i.key_pressed(Key::ArrowUp),
            i.key_pressed(Key::Enter),
            i.key_pressed(Key::Escape),
        )
    });
    if down && !rows.is_empty() {
        app.ui.clip_selected = Some(match app.ui.clip_selected {
            Some(s) => (s + 1).min(rows.len() - 1),
            None => 0,
        });
    }
    if up && !rows.is_empty() {
        app.ui.clip_selected = Some(match app.ui.clip_selected {
            Some(s) => s.saturating_sub(1),
            None => rows.len() - 1,
        });
    }
    if esc && app.ui.clip_selected.is_some() {
        app.ui.clip_selected = None;
    }
    let mut select_now: Option<crate::stores::ClipEntry> = None;
    if enter && !rows.is_empty() {
        // ↩ 选中(无高亮则选第一个,同 Maccy)
        let idx = app.ui.clip_selected.unwrap_or(0).min(rows.len() - 1);
        select_now = rows.get(idx).cloned();
    }

    if rows.is_empty() {
        let w = ui.available_width();
        let (rect, _) = hoverable(ui, Vec2::new(w, 150.0));
        let p = ui.painter().clone();
        let icon_color = t.text3;
        if app.ui.clip_search.is_empty() {
            widgets::icon_clipboard(&p, Rect::from_center_size(rect.center() - Vec2::new(0.0, 14.0), Vec2::new(24.0, 24.0)), icon_color, 1.7);
            p.text(rect.center() + Vec2::new(0.0, 2.0), egui::Align2::CENTER_CENTER, "剪贴板还是空的", FontId::proportional(12.0), icon_color);
            p.text(rect.center() + Vec2::new(0.0, 20.0), egui::Align2::CENTER_CENTER, "在任何应用里复制文字,都会自动记录到这里", FontId::proportional(10.0), alpha(icon_color, 200));
        } else {
            icon_search(&p, Rect::from_center_size(rect.center() - Vec2::new(0.0, 12.0), Vec2::new(24.0, 24.0)), icon_color, 1.7);
            p.text(rect.center() + Vec2::new(0.0, 16.0), egui::Align2::CENTER_CENTER, "没有匹配的复制记录", FontId::proportional(12.0), icon_color);
        }
        return;
    }

    let pinned_count = rows.iter().filter(|e| e.is_pinned()).count();
    ScrollArea::vertical().auto_shrink([false, false]).show(ui, |ui| {
        for (i, e) in rows.iter().enumerate() {
            if i == pinned_count && pinned_count > 0 && pinned_count < rows.len() {
                let (drect, _) = ui.allocate_exact_size(Vec2::new(ui.available_width(), 8.0), Sense::hover());
                ui.painter().line_segment(
                    [Pos2::new(drect.left(), drect.center().y), Pos2::new(drect.right(), drect.center().y)],
                    Stroke::new(1.0_f32, alpha(t.border, 128)),
                );
            }
            let selected = app.ui.clip_selected == Some(i);
            if clip_row(ui, app, t, e, selected) {
                select_now = Some(e.clone());
            }
        }
    });

    // 选中(Maccy:回写剪贴板 → 按设置向前台应用模拟 Ctrl+V)
    if let Some(e) = select_now {
        let ok = app.clipboard.copy_back(&e);
        app.ui.clip_selected = None;
        if ok {
            if app.settings.auto_paste {
                app.ui.clip_toast = Some(("已复制并粘贴".into(), Instant::now() + std::time::Duration::from_secs(2)));
                app.ui.hide_requested = true; // 先收起,再向前台应用模拟 Ctrl+V
                app.ui.paste_requested = true;
            } else {
                app.ui.clip_toast = Some(("已复制".into(), Instant::now() + std::time::Duration::from_secs(2)));
            }
        }
    }
}

/// 返回 true = 请求选中该条目
fn clip_row(ui: &mut Ui, app: &mut App, t: &ThemeColors, e: &crate::stores::ClipEntry, selected: bool) -> bool {
    let h = 34.0;
    let (rect, resp) = ui.allocate_exact_size(Vec2::new(ui.available_width(), h), Sense::click());
    let hovered = resp.hovered();
    let p = ui.painter().clone();
    let bg = if selected {
        alpha(t.accent, 38)
    } else if hovered {
        alpha(t.text, 15)
    } else {
        Color32::TRANSPARENT
    };
    p.rect_filled(rect, CornerRadius::same(8), bg);

    // 左侧:图片缩略图(Maccy 同)或来源应用标记
    let mut tx = rect.left() + 8.0;
    if e.is_image() {
        let thumb = Rect::from_center_size(Pos2::new(tx + 18.0, rect.center().y), Vec2::new(36.0, 22.0));
        if let Some(tex) = app.clip_texture(ui.ctx(), e) {
            p.image(tex.id(), thumb, Rect::from_min_size(Pos2::ZERO, Vec2::splat(1.0)), Color32::WHITE);
        } else {
            p.rect_filled(thumb, CornerRadius::same(3), t.pill);
            icon_file(&p, thumb.shrink(5.0), t.text3, 1.4);
        }
        tx += 44.0;
        body_text(ui, Pos2::new(tx, rect.center().y), egui::Align2::LEFT_CENTER, "图片", 12.0, t.text2);
    } else {
        let cc = Rect::from_center_size(Pos2::new(tx + 8.0, rect.center().y), Vec2::new(16.0, 16.0));
        let (r, g, b) = source_color(e.source_name.as_deref().unwrap_or("?"));
        p.circle_filled(cc.center(), 8.0, Color32::from_rgb(r, g, b));
        let initial = e
            .source_name
            .as_deref()
            .and_then(|s| s.chars().next())
            .map(|ch| ch.to_uppercase().next().unwrap_or(ch).to_string())
            .unwrap_or_else(|| "?".into());
        p.text(cc.center(), egui::Align2::CENTER_CENTER, initial, FontId::proportional(9.0), Color32::WHITE);
        tx += 22.0;
        // 文本预览(换行折为空格,单行截尾)
        let max_w = rect.right() - tx
            - (if e.is_pinned() { 24.0 } else { 8.0 })
            - (if hovered { 48.0 } else { 0.0 });
        let raw = e.text.replace('\n', " ");
        let line = clip_line(ui, &raw, 12.0, max_w);
        body_text(ui, Pos2::new(tx, rect.center().y), egui::Align2::LEFT_CENTER, line, 12.0, t.text);
    }
    // 固定标 / 悬停操作(Maccy:固定/取消固定 + 删除)
    let mut rx = rect.right() - 8.0;
    if hovered {
        let tr = Rect::from_center_size(Pos2::new(rx - 8.0, rect.center().y), Vec2::new(14.0, 14.0));
        let tresp = ui.allocate_rect(tr.expand(2.0), Sense::click());
        icon_pin_small(&p, tr, if e.is_pinned() { t.accent } else { t.text2 }, 1.5);
        if tresp.clicked() {
            app.clipboard.toggle_pin(e.id);
        }
        rx -= 26.0;
        let xr = Rect::from_center_size(Pos2::new(rx - 8.0, rect.center().y), Vec2::new(14.0, 14.0));
        let xresp = ui.allocate_rect(xr.expand(2.0), Sense::click());
        icon_trash(&p, xr, if xresp.hovered() { t.accent } else { t.text2 }, 1.5);
        if xresp.clicked() {
            app.clipboard.remove(e.id);
        }
    } else if e.is_pinned() {
        icon_pin_small(&p, Rect::from_center_size(Pos2::new(rx - 8.0, rect.center().y), Vec2::new(12.0, 12.0)), t.accent, 1.5);
    }
    resp.clicked()
}

/// 来源名 → 稳定的区分色
fn source_color(name: &str) -> (u8, u8, u8) {
    let palette: [(u8, u8, u8); 8] = [
        (59, 130, 246), (16, 185, 129), (245, 158, 11), (239, 68, 68),
        (139, 92, 246), (6, 182, 212), (236, 72, 153), (132, 204, 22),
    ];
    let mut h = 0u32;
    for b in name.bytes() {
        h = h.wrapping_mul(31).wrapping_add(b as u32);
    }
    palette[(h as usize) % palette.len()]
}

// MARK: - 设置(原版为独立窗口;Windows 版收进面板内页)

fn settings_view(ui: &mut Ui, app: &mut App, t: &ThemeColors) {
    ui.add_space(4.0);
    ui.horizontal(|ui| {
        count_text(ui, t, "设置");
        ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
            if action_link(ui, t, "返回", true).clicked() {
                app.ui.settings_open = false;
            }
        });
    });
    ui.add_space(6.0);

    // 开关值在 ScrollArea 闭包内修改,声明提到外面(闭包结束后统一落盘)
    let mut pinned = app.settings.pinned;
    let mut auto_paste = app.settings.auto_paste;
    let mut launch = app.settings.launch_at_login;

    ScrollArea::vertical().auto_shrink([false, false]).show(ui, |ui| {
        // ── 外观:主题三态(渲染证据:跟随系统/浅色/深色)
        let card = card_rect(ui, t, 84.0);
        body_text(ui, Pos2::new(card.left() + 12.0, card.top() + 16.0), egui::Align2::LEFT_CENTER, "主题", 13.0, t.text);
        let modes = crate::settings::ThemeMode::all();
        let sel = modes.iter().position(|m| *m == app.settings.theme_mode).unwrap_or(0);
        let labels: Vec<&str> = modes.iter().map(|m| m.title()).collect();
        let mut seg_w = 4.0;
        for (i, o) in labels.iter().enumerate() {
            seg_w += text_rect(ui, o, 12.0).x + 32.0;
            if i + 1 < labels.len() {
                seg_w += 4.0;
            }
        }
        let seg_r = Rect::from_min_max(
            Pos2::new(card.right() - 12.0 - seg_w, card.top() + 6.0),
            Pos2::new(card.right() - 12.0, card.top() + 36.0),
        );
        let picked = ui
            .allocate_new_ui(egui::UiBuilder::new().max_rect(seg_r), |ui| segmented(ui, t, &labels, sel))
            .inner;
        if let Some(i) = picked {
            let mode = modes[i];
            app.settings.theme_mode = mode;
            app.settings.theme_is_dark = match mode {
                crate::settings::ThemeMode::System => crate::platform::system_is_dark(),
                crate::settings::ThemeMode::Light => false,
                crate::settings::ThemeMode::Dark => true,
            };
        }
        body_text(
            ui,
            Pos2::new(card.left() + 12.0, card.bottom() - 16.0),
            egui::Align2::LEFT_CENTER,
            "跟随系统:随 Windows 浅色/深色模式自动切换",
            10.0,
            t.text3,
        );
        ui.add_space(8.0);

        // ── 行为开关
        let card = card_rect(ui, t, 102.0);
        for (i, (label, val)) in [
            ("常驻模式(失焦不收起)", &mut pinned),
            ("选中剪贴板后自动粘贴", &mut auto_paste),
            ("开机自启", &mut launch),
        ]
        .into_iter()
        .enumerate()
        {
            let row = Rect::from_min_max(
                Pos2::new(card.left() + 12.0, card.top() + 8.0 + 32.0 * i as f32),
                Pos2::new(card.right() - 12.0, card.top() + 36.0 + 32.0 * i as f32),
            );
            body_text(ui, Pos2::new(row.left(), row.center().y), egui::Align2::LEFT_CENTER, label, 13.0, t.text);
            toggle_switch_at(
                ui,
                Rect::from_center_size(Pos2::new(row.right() - 18.0, row.center().y), Vec2::new(36.0, 21.0)),
                val,
            );
        }
        if let Some(until) = app.ui.launch_failed_until {
            if Instant::now() < until {
                body_text(
                    ui,
                    Pos2::new(card.left() + 12.0, card.bottom() - 6.0),
                    egui::Align2::LEFT_CENTER,
                    "写入注册表失败",
                    10.0,
                    t.danger,
                );
            } else {
                app.ui.launch_failed_until = None;
            }
        }
        ui.add_space(8.0);

        // ── 快捷键 + 恢复默认
        let card = card_rect(ui, t, 68.0);
        let hk = app.settings.hotkey.clone().unwrap_or_default();
        body_text(
            ui,
            Pos2::new(card.left() + 12.0, card.top() + 18.0),
            egui::Align2::LEFT_CENTER,
            "显示/隐藏快捷键",
            13.0,
            t.text,
        );
        body_text(
            ui,
            Pos2::new(card.right() - 12.0, card.top() + 18.0),
            egui::Align2::RIGHT_CENTER,
            hk.display(),
            12.0,
            t.text2,
        );
        let r2resp = ui.allocate_rect(
            Rect::from_min_max(Pos2::new(card.left() + 12.0, card.top() + 40.0), Pos2::new(card.left() + 160.0, card.bottom() - 6.0)),
            Sense::click(),
        );
        let r2 = r2resp.rect;
        body_text(ui, r2.center(), egui::Align2::LEFT_CENTER, "恢复默认大小与位置", 13.0, t.accent);
        if r2resp.clicked() {
            app.ui.reset_requested = true;
        }
        ui.add_space(8.0);

        // ── 说明
        let card = card_rect(ui, t, 96.0);
        for (i, line) in [
            "· 剪贴板历史纯本地保存,图片条目落盘为 PNG",
            "· 密码经 DPAPI 加密,仅本机可解密",
            "· 拖拽文件到「暂存」页即可快速收纳",
        ]
        .into_iter()
        .enumerate()
        {
            body_text(
                ui,
                Pos2::new(card.left() + 12.0, card.top() + 16.0 + 22.0 * i as f32),
                egui::Align2::LEFT_CENTER,
                line,
                10.0,
                t.text3,
            );
        }
    });

    if pinned != app.settings.pinned {
        app.settings.pinned = pinned;
    }
    if auto_paste != app.settings.auto_paste {
        app.settings.auto_paste = auto_paste;
    }
    if launch != app.settings.launch_at_login {
        if crate::platform::set_launch_at_login(launch) {
            app.settings.launch_at_login = launch;
        } else {
            app.ui.launch_failed_until = Some(Instant::now() + std::time::Duration::from_secs(3));
            app.settings.launch_at_login = crate::platform::is_launch_at_login();
        }
    }
}

fn toggle_switch_at(ui: &mut Ui, rect: Rect, on: &mut bool) {
    let resp = ui.allocate_rect(rect, Sense::click());
    if resp.clicked() {
        *on = !*on;
    }
    let t = colors(crate::app::current_dark());
    let track = if *on { t.accent } else { t.pill };
    ui.painter().rect_filled(rect, CornerRadius::same(10), track);
    let knob_x = if *on { rect.right() - 11.0 } else { rect.left() + 11.0 };
    ui.painter().circle_filled(
        Pos2::new(knob_x, rect.center().y),
        8.5,
        if *on { Color32::WHITE } else { t.text2 },
    );
}
