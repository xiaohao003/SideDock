// theme.rs — 主题 token(色值取自原版 --promoshot 渲染图逐点取样)
// 浅色 bg #F7F7F8 卡 #ECECEC chip #DCDCDC 选中渐变 #3B82F6→#32BFF1
// 深色 bg #1C1C1F 卡 #262629 chip #363639 选中渐变 #4A8DFF→#32BFF1
use egui::Color32;
use egui::epaint::{CornerRadius, Mesh, Pos2, RectShape, Shape, Stroke};

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

/// 画一个水平线性渐变圆角矩形(egui 无原生渐变,用 Mesh 四顶点插值呈现)
pub fn h_gradient_rect(painter: &egui::Painter, rect: egui::Rect, left: Color32, right: Color32, radius: f32) {
    let rounding = CornerRadius::same(radius as u8);
    // 底层:同形状透明矩形仅占层序;真正颜色由顶点 mesh 提供
    painter.add(Shape::Rect(RectShape::filled(rect, rounding, Color32::TRANSPARENT)));
    let mut mesh = Mesh::default();
    mesh.colored_vertex(Pos2::new(rect.left(), rect.top()), left);
    mesh.colored_vertex(Pos2::new(rect.left(), rect.bottom()), left);
    mesh.colored_vertex(Pos2::new(rect.right(), rect.top()), right);
    mesh.colored_vertex(Pos2::new(rect.right(), rect.bottom()), right);
    mesh.indices.extend_from_slice(&[0, 1, 2, 2, 1, 3]);
    painter.add(Shape::Mesh(std::sync::Arc::new(mesh)));
    let _ = Stroke::NONE;
}
