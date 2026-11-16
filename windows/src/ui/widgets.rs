// widgets.rs — 矢量图标(替代 SF Symbols)与通用控件
// Windows 无 SF Symbols 且 egui 不渲染彩色 emoji,全部图标用 painter 手绘
use crate::theme::{alpha, colors, h_gradient_rect, ThemeColors};
use chrono::{DateTime, Local};
use egui::{
    epaint, Color32, CornerRadius, FontId, Pos2, Rect, Sense, Stroke, StrokeKind, Ui, Vec2,
};

// MARK: - 图标(painter 矢量;size 为图标外框边长)

pub type IconFn = fn(&egui::Painter, Rect, Color32, f32);

fn stroke_c(color: Color32, w: f32) -> Stroke {
    Stroke::new(w, color)
}

/// 待办:清单(两条横线 + 左侧小方点)
pub fn icon_todo(p: &egui::Painter, r: Rect, color: Color32, lw: f32) {
    let s = stroke_c(color, lw);
    let x0 = r.left();
    let x1 = r.right();
    for i in 0..2 {
        let y = r.top() + r.height() * (0.3 + 0.42 * i as f32);
        p.line_segment([Pos2::new(x0, y), Pos2::new(x1, y)], s);
    }
    p.line_segment([Pos2::new(x0, r.top()), Pos2::new(x0 + lw * 0.4, r.top())], s);
}

/// 笔记:便签(圆角矩形 + 折角)
pub fn icon_note(p: &egui::Painter, r: Rect, color: Color32, lw: f32) {
    let s = stroke_c(color, lw);
    let fold = r.width() * 0.28;
    let body = Rect::from_min_max(r.left_top(), Pos2::new(r.right() - fold, r.bottom()));
    p.rect_stroke(body, CornerRadius::same(3), s, StrokeKind::Inside);
    let mut tri = epaint::Mesh::default();
    let a = Pos2::new(r.right() - fold, r.top());
    let b = Pos2::new(r.right(), r.top() + fold);
    let cc = Pos2::new(r.right() - fold, r.top() + fold);
    tri.colored_vertex(a, color);
    tri.colored_vertex(b, color);
    tri.colored_vertex(cc, alpha(color, 140));
    tri.indices.extend_from_slice(&[0, 1, 2]);
    p.add(epaint::Shape::Mesh(std::sync::Arc::new(tri)));
    // 一条内容线
    let y = r.top() + r.height() * 0.62;
    p.line_segment(
        [Pos2::new(r.left() + r.width() * 0.22, y), Pos2::new(r.right() - r.width() * 0.25, y)],
        stroke_c(color, lw * 0.8),
    );
}

/// 下载:圆圈内向下箭头
pub fn icon_download(p: &egui::Painter, r: Rect, color: Color32, lw: f32) {
    let c = r.center();
    let rad = r.width() / 2.0;
    p.circle_stroke(c, rad - lw, stroke_c(color, lw));
    let dx = r.width() * 0.14;
    p.line_segment(
        [Pos2::new(c.x, c.y - rad * 0.45), Pos2::new(c.x, c.y + rad * 0.38)],
        stroke_c(color, lw),
    );
    p.line_segment(
        [Pos2::new(c.x - dx, c.y + rad * 0.38 - dx), Pos2::new(c.x, c.y + rad * 0.38)],
        stroke_c(color, lw),
    );
    p.line_segment(
        [Pos2::new(c.x + dx, c.y + rad * 0.38 - dx), Pos2::new(c.x, c.y + rad * 0.38)],
        stroke_c(color, lw),
    );
}

/// 暂存:托盘 + 落入箭头
pub fn icon_shelf(p: &egui::Painter, r: Rect, color: Color32, lw: f32) {
    let s = stroke_c(color, lw);
    let tray_top = r.top() + r.height() * 0.52;
    // 托盘(两侧壁 + 底)
    p.line_segment([Pos2::new(r.left(), tray_top), Pos2::new(r.left(), r.bottom())], s);
    p.line_segment([Pos2::new(r.left(), r.bottom()), Pos2::new(r.right(), r.bottom())], s);
    p.line_segment([Pos2::new(r.right(), r.bottom()), Pos2::new(r.right(), tray_top)], s);
    // 落入箭头
    let cx = r.center().x;
    let ay = r.top() + r.height() * 0.12;
    p.line_segment([Pos2::new(cx, ay), Pos2::new(cx, tray_top - r.height() * 0.10)], s);
    let dx = r.width() * 0.16;
    let by = tray_top - r.height() * 0.10;
    p.line_segment([Pos2::new(cx - dx, by - dx), Pos2::new(cx, by)], s);
    p.line_segment([Pos2::new(cx + dx, by - dx), Pos2::new(cx, by)], s);
}

/// 密码:钥匙(圆环 + 齿柄)
pub fn icon_key(p: &egui::Painter, r: Rect, color: Color32, lw: f32) {
    let s = stroke_c(color, lw);
    let rad = r.height() * 0.24;
    let cc = Pos2::new(r.left() + rad + lw, r.center().y);
    p.circle_stroke(cc, rad, s);
    let stem_y = r.center().y;
    let x0 = cc.x + rad;
    let x1 = r.right() - lw;
    p.line_segment([Pos2::new(x0, stem_y), Pos2::new(x1, stem_y)], s);
    // 齿
    let t1 = x1 - r.width() * 0.16;
    p.line_segment([Pos2::new(t1, stem_y), Pos2::new(t1, stem_y + r.height() * 0.2)], s);
    let t2 = x1 - r.width() * 0.32;
    p.line_segment([Pos2::new(t2, stem_y), Pos2::new(t2, stem_y + r.height() * 0.2)], s);
}

/// 剪贴板:板 + 顶部夹子
pub fn icon_clipboard(p: &egui::Painter, r: Rect, color: Color32, lw: f32) {
    let s = stroke_c(color, lw);
    let mut body = r;
    body.min.y += r.height() * 0.14;
    p.rect_stroke(body, CornerRadius::same(3), s, StrokeKind::Inside);
    let clip_w = r.width() * 0.42;
    let clip = Rect::from_center_size(
        Pos2::new(r.center().x, r.top() + r.height() * 0.10),
        Vec2::new(clip_w, r.height() * 0.16),
    );
    p.rect_filled(clip, CornerRadius::same(2), color);
    let y = body.top() + body.height() * 0.55;
    p.line_segment(
        [Pos2::new(body.left() + body.width() * 0.22, y), Pos2::new(body.right() - body.width() * 0.22, y)],
        stroke_c(color, lw * 0.8),
    );
}

/// 设置齿轮
pub fn icon_gear(p: &egui::Painter, r: Rect, color: Color32, lw: f32) {
    let c = r.center();
    let rad = r.width() / 2.0 - lw;
    p.circle_stroke(c, rad * 0.62, stroke_c(color, lw));
    for i in 0..8 {
        let a = i as f32 / 8.0 * std::f32::consts::TAU + 0.2;
        let dir = egui::vec2(a.cos(), a.sin());
        p.line_segment(
            [c + dir * (rad * 0.72), c + dir * rad],
            stroke_c(color, lw),
        );
    }
}

/// 图钉(常驻)
pub fn icon_pin(p: &egui::Painter, r: Rect, color: Color32, lw: f32) {
    let s = stroke_c(color, lw);
    let cx = r.center().x;
    let head_y = r.top() + r.height() * 0.28;
    p.line_segment([Pos2::new(cx - r.width() * 0.18, head_y), Pos2::new(cx + r.width() * 0.18, head_y)], s);
    p.line_segment(
        [Pos2::new(cx, head_y), Pos2::new(cx, r.bottom() - r.height() * 0.08)],
        s,
    );
    p.line_segment(
        [Pos2::new(cx - r.width() * 0.16, r.bottom() - r.height() * 0.08), Pos2::new(cx + r.width() * 0.16, r.bottom() - r.height() * 0.08)],
        s,
    );
}

/// 右箭头(收起)
pub fn icon_chevron(p: &egui::Painter, r: Rect, color: Color32, lw: f32) {
    let s = stroke_c(color, lw);
    let cx = r.center().x;
    p.line_segment(
        [
            Pos2::new(cx - r.width() * 0.18, r.top() + r.height() * 0.2),
            Pos2::new(cx + r.width() * 0.18, r.center().y),
        ],
        s,
    );
    p.line_segment(
        [
            Pos2::new(cx + r.width() * 0.18, r.center().y),
            Pos2::new(cx - r.width() * 0.18, r.bottom() - r.height() * 0.2),
        ],
        s,
    );
}

/// 加号
pub fn icon_plus(p: &egui::Painter, r: Rect, color: Color32, lw: f32) {
    let c = r.center();
    let h = r.height() / 2.0;
    p.line_segment([Pos2::new(c.x - h, c.y), Pos2::new(c.x + h, c.y)], stroke_c(color, lw));
    p.line_segment([Pos2::new(c.x, c.y - h), Pos2::new(c.x, c.y + h)], stroke_c(color, lw));
}

/// 叉号
pub fn icon_x(p: &egui::Painter, r: Rect, color: Color32, lw: f32) {
    let s = stroke_c(color, lw);
    let a = r.width() * 0.25;
    let (l, t, rt, b) = (r.left() + a, r.top() + a, r.right() - a, r.bottom() - a);
    p.line_segment([Pos2::new(l, t), Pos2::new(rt, b)], s);
    p.line_segment([Pos2::new(rt, t), Pos2::new(l, b)], s);
}

/// 勾
pub fn icon_check(p: &egui::Painter, r: Rect, color: Color32, lw: f32) {
    let s = stroke_c(color, lw);
    let p1 = Pos2::new(r.left() + r.width() * 0.12, r.center().y + r.height() * 0.05);
    let p2 = Pos2::new(r.left() + r.width() * 0.42, r.bottom() - r.height() * 0.18);
    let p3 = Pos2::new(r.right() - r.width() * 0.06, r.top() + r.height() * 0.16);
    p.line_segment([p1, p2], s);
    p.line_segment([p2, p3], s);
}

/// 铃铛
pub fn icon_bell(p: &egui::Painter, r: Rect, color: Color32, lw: f32) {
    let s = stroke_c(color, lw);
    let cx = r.center().x;
    let top = Pos2::new(cx, r.top() + r.height() * 0.22);
    p.line_segment([top, Pos2::new(cx, r.top() + r.height() * 0.3)], s);
    p.line_segment(
        [
            Pos2::new(r.left() + r.width() * 0.12, r.bottom() - r.height() * 0.3),
            Pos2::new(r.right() - r.width() * 0.12, r.bottom() - r.height() * 0.3),
        ],
        s,
    );
    // 钟身(梯形近似:两条斜线)
    p.line_segment(
        [
            Pos2::new(r.left() + r.width() * 0.12, r.bottom() - r.height() * 0.3),
            Pos2::new(r.left() + r.width() * 0.3, r.top() + r.height() * 0.34),
        ],
        s,
    );
    p.line_segment(
        [
            Pos2::new(r.right() - r.width() * 0.12, r.bottom() - r.height() * 0.3),
            Pos2::new(r.right() - r.width() * 0.3, r.top() + r.height() * 0.34),
        ],
        s,
    );
    p.line_segment(
        [
            Pos2::new(r.left() + r.width() * 0.3, r.top() + r.height() * 0.34),
            Pos2::new(r.right() - r.width() * 0.3, r.top() + r.height() * 0.34),
        ],
        s,
    );
    p.circle_filled(Pos2::new(cx, r.bottom() - r.height() * 0.14), lw, color);
}

/// 放大镜
pub fn icon_search(p: &egui::Painter, r: Rect, color: Color32, lw: f32) {
    let rad = r.width() * 0.3;
    let c = Pos2::new(r.left() + rad + lw * 0.5, r.top() + rad + lw * 0.5);
    p.circle_stroke(c, rad, stroke_c(color, lw));
    p.line_segment(
        [
            Pos2::new(c.x + rad * 0.7, c.y + rad * 0.7),
            Pos2::new(r.right() - lw, r.bottom() - lw),
        ],
        stroke_c(color, lw),
    );
}

/// 文件夹
pub fn icon_folder(p: &egui::Painter, r: Rect, color: Color32, lw: f32) {
    let s = stroke_c(color, lw);
    let mut body = r;
    body.min.y += r.height() * 0.22;
    p.rect_stroke(body, CornerRadius::same(3), s, StrokeKind::Inside);
    let tab = Rect::from_min_size(
        Pos2::new(r.left(), r.top() + r.height() * 0.14),
        Vec2::new(r.width() * 0.45, r.height() * 0.16),
    );
    p.rect_stroke(tab, CornerRadius { ne: 2, nw: 2, se: 0, sw: 0 }, s, StrokeKind::Inside);
}

/// 垃圾桶
pub fn icon_trash(p: &egui::Painter, r: Rect, color: Color32, lw: f32) {
    let s = stroke_c(color, lw);
    let lid_y = r.top() + r.height() * 0.22;
    p.line_segment(
        [Pos2::new(r.left(), lid_y), Pos2::new(r.right(), lid_y)],
        s,
    );
    p.line_segment(
        [Pos2::new(r.center().x, r.top() + r.height() * 0.06), Pos2::new(r.center().x, lid_y)],
        s,
    );
    let body = Rect::from_min_max(
        Pos2::new(r.left() + r.width() * 0.14, lid_y),
        Pos2::new(r.right() - r.width() * 0.14, r.bottom()),
    );
    p.rect_stroke(body, CornerRadius::same(2), s, StrokeKind::Inside);
    let x1 = r.left() + r.width() * 0.38;
    let x2 = r.right() - r.width() * 0.38;
    p.line_segment(
        [Pos2::new(x1, lid_y + r.height() * 0.16), Pos2::new(x1, r.bottom() - r.height() * 0.12)],
        stroke_c(color, lw * 0.8),
    );
    p.line_segment(
        [Pos2::new(x2, lid_y + r.height() * 0.16), Pos2::new(x2, r.bottom() - r.height() * 0.12)],
        stroke_c(color, lw * 0.8),
    );
}

/// 图钉小图标(剪贴板行固定标记)
pub fn icon_pin_small(p: &egui::Painter, r: Rect, color: Color32, lw: f32) {
    let s = stroke_c(color, lw);
    let cx = r.center().x;
    p.circle_filled(Pos2::new(cx, r.top() + r.height() * 0.3), r.width() * 0.18, color);
    p.line_segment(
        [Pos2::new(cx, r.top() + r.height() * 0.3), Pos2::new(cx + r.width() * 0.12, r.bottom())],
        s,
    );
}

/// 眼睛
pub fn icon_eye(p: &egui::Painter, r: Rect, color: Color32, lw: f32) {
    let s = stroke_c(color, lw);
    let c = r.center();
    p.line_segment(
        [Pos2::new(r.left(), c.y), Pos2::new(r.right(), c.y)],
        s,
    );
    p.circle_stroke(c, r.height() * 0.3, s);
}

/// 魔法棒(生成密码)
pub fn icon_wand(p: &egui::Painter, r: Rect, color: Color32, lw: f32) {
    let s = stroke_c(color, lw);
    p.line_segment(
        [Pos2::new(r.left() + r.width() * 0.15, r.bottom() - r.height() * 0.15), Pos2::new(r.right() - r.width() * 0.3, r.top() + r.height() * 0.3)],
        s,
    );
    // 星点
    p.circle_filled(Pos2::new(r.right() - r.width() * 0.12, r.top() + r.height() * 0.18), lw, color);
    p.circle_filled(Pos2::new(r.left() + r.width() * 0.2, r.top() + r.height() * 0.2), lw * 0.8, color);
    p.circle_filled(Pos2::new(r.right() - r.width() * 0.28, r.bottom() - r.height() * 0.2), lw * 0.8, color);
}

/// 音乐符(无封面占位)
pub fn icon_music_note(p: &egui::Painter, r: Rect, color: Color32, lw: f32) {
    let s = stroke_c(color, lw);
    let x = r.left() + r.width() * 0.36;
    p.line_segment(
        [Pos2::new(x, r.bottom() - r.height() * 0.22), Pos2::new(x, r.top() + r.height() * 0.22)],
        stroke_c(color, lw * 1.2),
    );
    p.line_segment(
        [Pos2::new(x, r.top() + r.height() * 0.22), Pos2::new(r.right() - r.width() * 0.25, r.top() + r.height() * 0.34)],
        stroke_c(color, lw * 1.2),
    );
    p.line_segment(
        [Pos2::new(r.right() - r.width() * 0.25, r.top() + r.height() * 0.34), Pos2::new(r.right() - r.width() * 0.25, r.center().y + r.height() * 0.08)],
        stroke_c(color, lw * 1.2),
    );
    p.circle_filled(Pos2::new(x - r.width() * 0.08, r.bottom() - r.height() * 0.2), r.width() * 0.14, color);
    p.circle_filled(
        Pos2::new(r.right() - r.width() * 0.25 - r.width() * 0.08, r.center().y + r.height() * 0.1),
        r.width() * 0.14,
        color,
    );
    let _ = s;
}

/// 通用文件(下载行/暂存格)
pub fn icon_file(p: &egui::Painter, r: Rect, color: Color32, lw: f32) {
    let s = stroke_c(color, lw);
    let fold = r.width() * 0.3;
    let corner = [
        Pos2::new(r.left(), r.top()),
        Pos2::new(r.right() - fold, r.top()),
        Pos2::new(r.right(), r.top() + fold),
        Pos2::new(r.right(), r.bottom()),
        Pos2::new(r.left(), r.bottom()),
        Pos2::new(r.left(), r.top()),
    ];
    for w in corner.windows(2) {
        p.line_segment([w[0], w[1]], s);
    }
    let fa = Pos2::new(r.right() - fold, r.top());
    let fb = Pos2::new(r.right() - fold, r.top() + fold);
    let fc = Pos2::new(r.right(), r.top() + fold);
    p.line_segment([fa, fb], s);
    p.line_segment([fb, fc], s);
    let y = r.top() + r.height() * 0.6;
    p.line_segment(
        [Pos2::new(r.left() + r.width() * 0.2, y), Pos2::new(r.right() - r.width() * 0.2, y)],
        stroke_c(color, lw * 0.8),
    );
}

/// 播放/暂停/上一首/下一首(音乐卡传输键)
pub fn icon_pause(p: &egui::Painter, r: Rect, color: Color32) {
    let w = r.width() * 0.22;
    for x in [r.left() + r.width() * 0.18, r.right() - r.width() * 0.18 - w] {
        let bar = Rect::from_min_size(Pos2::new(x, r.top()), Vec2::new(w, r.height()));
        p.rect_filled(bar, CornerRadius::same(2), color);
    }
}

pub fn icon_play(p: &egui::Painter, r: Rect, color: Color32) {
    let mut mesh = epaint::Mesh::default();
    let a = Pos2::new(r.left(), r.top());
    let b = Pos2::new(r.left(), r.bottom());
    let cc = Pos2::new(r.right(), r.center().y);
    mesh.colored_vertex(a, color);
    mesh.colored_vertex(b, color);
    mesh.colored_vertex(cc, color);
    mesh.indices.extend_from_slice(&[0, 1, 2]);
    p.add(epaint::Shape::Mesh(std::sync::Arc::new(mesh)));
}

pub fn icon_prev(p: &egui::Painter, r: Rect, color: Color32) {
    let bar = Rect::from_min_size(r.left_top(), Vec2::new(r.width() * 0.14, r.height()));
    p.rect_filled(bar, CornerRadius::same(1), color);
    let mut mesh = epaint::Mesh::default();
    let a = Pos2::new(r.right() - r.width() * 0.16, r.top());
    let b = Pos2::new(r.right() - r.width() * 0.16, r.bottom());
    let cc = Pos2::new(r.left() + r.width() * 0.2, r.center().y);
    mesh.colored_vertex(a, color);
    mesh.colored_vertex(b, color);
    mesh.colored_vertex(cc, color);
    mesh.indices.extend_from_slice(&[0, 1, 2]);
    p.add(epaint::Shape::Mesh(std::sync::Arc::new(mesh)));
}

pub fn icon_next(p: &egui::Painter, r: Rect, color: Color32) {
    let bar = Rect::from_min_size(
        Pos2::new(r.right() - r.width() * 0.14, r.top()),
        Vec2::new(r.width() * 0.14, r.height()),
    );
    p.rect_filled(bar, CornerRadius::same(1), color);
    let mut mesh = epaint::Mesh::default();
    let a = Pos2::new(r.left() + r.width() * 0.16, r.top());
    let b = Pos2::new(r.left() + r.width() * 0.16, r.bottom());
    let cc = Pos2::new(r.right() - r.width() * 0.2, r.center().y);
    mesh.colored_vertex(a, color);
    mesh.colored_vertex(b, color);
    mesh.colored_vertex(cc, color);
    mesh.indices.extend_from_slice(&[0, 1, 2]);
    p.add(epaint::Shape::Mesh(std::sync::Arc::new(mesh)));
}

/// Tab 图标分派
pub fn tab_icon(
    p: &egui::Painter,
    r: Rect,
    tab: crate::settings::PanelTab,
    color: Color32,
    lw: f32,
) {
    use crate::settings::PanelTab::*;
    match tab {
        Todo => icon_todo(p, r, color, lw),
        Notes => icon_note(p, r, color, lw),
        Downloads => icon_download(p, r, color, lw),
        Shelf => icon_shelf(p, r, color, lw),
        Passwords => icon_key(p, r, color, lw),
        Clipboard => icon_clipboard(p, r, color, lw),
    }
}

/// Tab 图标分派(返回函数指针,供胶囊条调用)
pub fn tab_icon_of(tab: crate::settings::PanelTab) -> IconFn {
    use crate::settings::PanelTab::*;
    match tab {
        Todo => icon_todo,
        Notes => icon_note,
        Downloads => icon_download,
        Shelf => icon_shelf,
        Passwords => icon_key,
        Clipboard => icon_clipboard,
    }
}

/// 向上箭头(笔记提交)
pub fn icon_arrow_up(p: &egui::Painter, r: Rect, color: Color32, lw: f32) {
    let s = stroke_c(color, lw);
    let cx = r.center().x;
    p.line_segment(
        [Pos2::new(cx, r.bottom() - r.height() * 0.15), Pos2::new(cx, r.top() + r.height() * 0.2)],
        s,
    );
    p.line_segment(
        [Pos2::new(cx - r.width() * 0.24, r.top() + r.height() * 0.44), Pos2::new(cx, r.top() + r.height() * 0.2)],
        s,
    );
    p.line_segment(
        [Pos2::new(cx + r.width() * 0.24, r.top() + r.height() * 0.44), Pos2::new(cx, r.top() + r.height() * 0.2)],
        s,
    );
}

/// 铅笔(编辑)
pub fn icon_pencil(p: &egui::Painter, r: Rect, color: Color32, lw: f32) {
    let s = stroke_c(color, lw);
    let a = Pos2::new(r.left() + r.width() * 0.18, r.bottom() - r.height() * 0.18);
    let b = Pos2::new(r.right() - r.width() * 0.2, r.top() + r.height() * 0.2);
    p.line_segment([a, b], s);
    p.line_segment(
        [
            Pos2::new(r.left() + r.width() * 0.18, r.bottom() - r.height() * 0.18),
            Pos2::new(r.left() + r.width() * 0.26, r.bottom() - r.height() * 0.08),
        ],
        s,
    );
    p.line_segment(
        [
            Pos2::new(r.right() - r.width() * 0.24, r.top() + r.height() * 0.24),
            Pos2::new(r.right() - r.width() * 0.14, r.top() + r.height() * 0.32),
        ],
        s,
    );
}

// MARK: - 文本/布局小助手

pub fn text_rect(ui: &Ui, text: &str, size: f32) -> Vec2 {
    let font = FontId::proportional(size);
    ui.ctx().fonts(|f| f.layout_no_wrap(text.to_owned(), font, Color32::WHITE)).size()
}

pub fn draw_text(p: &egui::Painter, pos: Pos2, anchor: egui::Align2, text: &str, size: f32, color: Color32) -> Rect {
    p.text(pos, anchor, text.to_owned(), FontId::proportional(size), color)
}

/// 点击区域(先分配后绘制;统一入口避免 allocate 顺序问题)
pub fn clickable(ui: &mut Ui, size: Vec2) -> (Rect, egui::Response) {
    ui.allocate_exact_size(size, Sense::click())
}

pub fn hoverable(ui: &mut Ui, size: Vec2) -> (Rect, egui::Response) {
    ui.allocate_exact_size(size, Sense::hover())
}

// MARK: - 胶囊按钮(渐变选中/灰底未选中,渲染证据同款)

#[allow(clippy::too_many_arguments)]
pub fn capsule(
    ui: &mut Ui,
    label: &str,
    text_size: f32,
    icon: Option<(IconFn, f32)>,
    badge: Option<u32>,
    selected: bool,
    pad_h: f32,
    pad_v: f32,
    theme: &ThemeColors,
    badge_color: Color32,
) -> egui::Response {
    let icon_w = icon.map(|(_, w)| w + 5.0).unwrap_or(0.0);
    let badge_w = badge.map(|b| 18.0 + b.to_string().len() as f32 * 7.0).unwrap_or(0.0);
    let label_size = text_rect(ui, label, text_size);
    let h = label_size.y + pad_v * 2.0;
    let w = pad_h * 2.0 + icon_w + label_size.x + badge_w;
    let (rect, resp) = ui.allocate_exact_size(Vec2::new(w, h), Sense::click());
    let p = ui.painter().clone();
    let radius = h / 2.0;
    if selected {
        h_gradient_rect(&p, rect, theme.accent, theme.accent2, radius);
    } else {
        p.rect_filled(rect, CornerRadius::same(radius as u8), theme.pill);
    }
    // 悬停微高亮
    if resp.hovered() && !selected {
        p.rect_filled(rect, CornerRadius::same(radius as u8), alpha(theme.text, 14));
    }
    let mut cx = rect.left() + pad_h;
    let cy = rect.center().y;
    if let Some((draw, iw)) = icon {
        let ir = Rect::from_center_size(
            Pos2::new(cx + iw / 2.0, cy),
            Vec2::new(iw, iw),
        );
        draw(&p, ir, Color32::WHITE, 1.6);
        cx += iw + 5.0;
    }
    let text_color = if selected { Color32::WHITE } else { theme.text };
    p.text(
        Pos2::new(cx, cy),
        egui::Align2::LEFT_CENTER,
        label.to_owned(),
        FontId::proportional(text_size),
        text_color,
    );
    if let Some(b) = badge {
        let text = b.to_string();
        let tw = text_rect(ui, &text, 10.0).x;
        let bw = tw + 10.0;
        let brect = Rect::from_center_size(
            Pos2::new(rect.right() - pad_h - bw / 2.0, cy),
            Vec2::new(bw.max(16.0), 14.0),
        );
        p.rect_filled(brect, CornerRadius::same(7), badge_color);
        p.text(
            brect.center(),
            egui::Align2::CENTER_CENTER,
            text,
            FontId::proportional(10.0),
            theme.accent,
        );
    }
    resp
}

// MARK: - 开关(设置页)

pub fn toggle_switch(ui: &mut Ui, on: &mut bool) -> egui::Response {
    let (rect, resp) = ui.allocate_exact_size(Vec2::new(36.0, 21.0), Sense::click());
    if resp.clicked() {
        *on = !*on;
    }
    let p = ui.painter().clone();
    let t = colors(crate::app::current_dark());
    let track = if *on { t.accent } else { t.pill };
    p.rect_filled(rect, CornerRadius::same(10), track);
    let knob_x = if *on { rect.right() - 11.0 } else { rect.left() + 11.0 };
    p.circle_filled(
        Pos2::new(knob_x, rect.center().y),
        8.5,
        if *on { Color32::WHITE } else { t.text2 },
    );
    resp
}

// MARK: - 相对时间("3 分钟前")

pub fn rel_time(t: &DateTime<Local>) -> String {
    let now = Local::now();
    let secs = (now - *t).num_seconds().max(0);
    if secs < 60 {
        "刚刚".into()
    } else if secs < 3600 {
        format!("{} 分钟前", secs / 60)
    } else if secs < 86400 {
        format!("{} 小时前", secs / 3600)
    } else if secs < 7 * 86400 {
        format!("{} 天前", secs / 86400)
    } else {
        t.format("%m月%d日").to_string()
    }
}

pub fn weekday_cn(d: chrono::Weekday) -> &'static str {
    match d {
        chrono::Weekday::Mon => "星期一",
        chrono::Weekday::Tue => "星期二",
        chrono::Weekday::Wed => "星期三",
        chrono::Weekday::Thu => "星期四",
        chrono::Weekday::Fri => "星期五",
        chrono::Weekday::Sat => "星期六",
        chrono::Weekday::Sun => "星期日",
    }
}

/// 时间 1:36 / 3:47
pub fn mmss(secs: f64) -> String {
    let s = secs.max(0.0) as i64;
    format!("{}:{:02}", s / 60, s % 60)
}
