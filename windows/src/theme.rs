// theme.rs — 主题 token(色值取自原版 --promoshot 渲染图逐点取样)
// 浅色 bg #F7F7F8 卡 #ECECEC chip #DCDCDC 选中渐变 #3B82F6→#32BFF1
// 深色 bg #1C1C1F 卡 #262629 chip #363639 选中渐变 #4A8DFF→#32BFF1
use egui::Color32;
use egui::epaint::{Mesh, Pos2, Shape};

#[derive(Clone, Copy)]
pub struct ThemeColors {
    pub bg: Color32,
    pub card: Color32,
    pub bar: Color32,
    pub pill: Color32,
    pub text: Color32,
    pub text2: Color32,
    pub text3: Color32,
    pub accent: Color32,
    pub accent2: Color32,
    pub danger: Color32,
    pub border: Color32,
}

pub const fn c(hex: u32) -> Color32 {
    Color32::from_rgb(((hex >> 16) & 0xFF) as u8, ((hex >> 8) & 0xFF) as u8, (hex & 0xFF) as u8)
}

pub fn colors(dark: bool) -> ThemeColors {
    if dark {
        ThemeColors {
            bg: c(0x1C1C1F), card: c(0x262629), bar: c(0x262629), pill: c(0x363639),
            text: c(0xE8E8EA), text2: c(0x9A9AA0), text3: c(0x6E6E74),
            accent: c(0x4A8DFF), accent2: c(0x32BFF1), danger: c(0xE5534B), border: c(0x3A3A3E),
        }
    } else {
        ThemeColors {
            bg: c(0xF7F7F8), card: c(0xECECEC), bar: c(0xECECEC), pill: c(0xDCDCDC),
            text: c(0x1C1C1E), text2: c(0x6B6E75), text3: c(0x9CA3AF),
            accent: c(0x3B82F6), accent2: c(0x32BFF1), danger: c(0xE5484D), border: c(0xE0E0E4),
        }
    }
}

/// 半透明覆盖色
pub fn alpha(color: Color32, a: u8) -> Color32 {
    Color32::from_rgba_unmultiplied(color.r(), color.g(), color.b(), a)
}

/// 画一个水平线性渐变圆角矩形(egui 0.32 无原生渐变画刷;
/// 用圆角矩形轮廓的三角扇 Mesh,顶点颜色按 x 线性插值 —— 直角会破坏胶囊外形)
pub fn h_gradient_rect(painter: &egui::Painter, rect: egui::Rect, left: Color32, right: Color32, radius: f32) {
    let radius = radius.max(0.0).min(rect.width() * 0.5).min(rect.height() * 0.5);
    let mut mesh = Mesh::default();
    let color_at = |x: f32| -> Color32 {
        let t = ((x - rect.left()) / rect.width().max(1.0)).clamp(0.0, 1.0);
        let mix = |a: u8, b: u8| (a as f32 + (b as f32 - a as f32) * t).round() as u8;
        Color32::from_rgb(mix(left.r(), right.r()), mix(left.g(), right.g()), mix(left.b(), right.b()))
    };
    if radius < 0.5 {
        mesh.colored_vertex(rect.left_top(), color_at(rect.left()));
        mesh.colored_vertex(rect.left_bottom(), color_at(rect.left()));
        mesh.colored_vertex(rect.right_top(), color_at(rect.right()));
        mesh.colored_vertex(rect.right_bottom(), color_at(rect.right()));
        mesh.indices.extend_from_slice(&[0, 1, 2, 2, 1, 3]);
        painter.add(Shape::Mesh(std::sync::Arc::new(mesh)));
        return;
    }
    // 圆角矩形轮廓点(顺时针;每角 seg 段圆弧),y 轴向下
    const SEG: f32 = 14.0;
    let (l, t_, r, b) = (rect.left(), rect.top(), rect.right(), rect.bottom());
    let mut pts: Vec<Pos2> = Vec::with_capacity(4 * (SEG as usize) + 1);
    let mut arc = |cx: f32, cy: f32, a0: f32, a1: f32, pts: &mut Vec<Pos2>| {
        for i in 0..=SEG as usize {
            let a = a0 + (a1 - a0) * (i as f32 / SEG);
            pts.push(Pos2::new(cx + radius * a.cos(), cy + radius * a.sin()));
        }
    };
    arc(l + radius, t_ + radius, core::f32::consts::PI, core::f32::consts::PI * 1.5, &mut pts);
    arc(r - radius, t_ + radius, -core::f32::consts::FRAC_PI_2, 0.0, &mut pts);
    arc(r - radius, b - radius, 0.0, core::f32::consts::FRAC_PI_2, &mut pts);
    arc(l + radius, b - radius, core::f32::consts::FRAC_PI_2, core::f32::consts::PI, &mut pts);
    // 三角扇:中心 + 相邻轮廓点(首尾闭合)
    let center = rect.center();
    mesh.colored_vertex(center, color_at(center.x));
    for (i, p) in pts.iter().enumerate() {
        mesh.colored_vertex(*p, color_at(p.x));
        let vi = (i + 1) as u32;
        let vn = ((i + 1) % pts.len() + 1) as u32;
        mesh.indices.extend_from_slice(&[0, vi, vn]);
    }
    painter.add(Shape::Mesh(std::sync::Arc::new(mesh)));
}
