// stores.rs — 密码保险库(DPAPI 加密,对应 macOS 版 Keychain)+ 剪贴板历史(Maccy 式)
// 剪贴板行为证据(逆向 Maccy 2.8.0):轮询 watcher / 固定-未固定双列表 / 搜索 /
// 来源应用 / 图片条目 / 选中回写系统剪贴板(+自动粘贴)
use crate::platform;
use crate::settings::{load_json, save_json};
use chrono::{DateTime, Local};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

// MARK: - 随机强密码(证据字符集:已去除易混淆字符)

pub struct PasswordGenerator;

impl PasswordGenerator {
    const FULL_CHARSET: &'static [u8] =
        b"abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789!@#$%&*?";
    const LETTER_CHARSET: &'static [u8] = b"abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ";

    pub fn generate(length: usize, symbols: bool) -> String {
        use rand::seq::SliceRandom;
        let charset = if symbols { Self::FULL_CHARSET } else { Self::LETTER_CHARSET };
        let mut rng = rand::thread_rng();
        (0..length)
            .map(|_| charset.choose(&mut rng).copied().unwrap_or(b'a') as char)
            .collect()
    }
}

// MARK: - 密码保险库(vault.json;密码经 DPAPI 加密为 base64 内嵌,仅本机可解)

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VaultEntry {
    pub id: Uuid,
    pub site: String,   // 网站 / 用途
    pub account: String, // 手机号 / 邮箱 / 用户名
    pub phone: Option<String>,
    pub note: Option<String>,
    pub created_at: DateTime<Local>,
    #[serde(default)]
    pub pw: Option<String>, // DPAPI(base64)
}

impl VaultEntry {
    pub fn new(site: String, account: String) -> Self {
        VaultEntry {
            id: Uuid::new_v4(),
            site,
            account,
            phone: None,
            note: None,
            created_at: Local::now(),
            pw: None,
        }
    }

    pub fn has_password(&self) -> bool {
        self.pw.is_some()
    }

    pub fn reveal(&self) -> Option<String> {
        platform::unprotect(self.pw.as_deref()?)
    }

    pub fn set_password(&mut self, plain: &str) -> Result<(), String> {
        self.pw = Some(platform::protect(plain)?);
        Ok(())
    }
}

#[derive(Debug, Default)]
pub struct VaultStore {
    pub entries: Vec<VaultEntry>,
}

impl VaultStore {
    pub fn load() -> Self {
        VaultStore { entries: load_json::<Vec<VaultEntry>>("vault.json").unwrap_or_default() }
    }

    fn save(&self) {
        save_json("vault.json", &self.entries);
    }

    pub fn add(&mut self, mut entry: VaultEntry, password: Option<&str>) -> Result<(), String> {
        if let Some(pw) = password {
            if !pw.is_empty() {
                entry.set_password(pw)?;
            }
        }
        self.entries.insert(0, entry);
        self.save();
        Ok(())
    }

    pub fn update_password(&mut self, id: Uuid, plain: &str) -> Result<(), String> {
        let Some(e) = self.entries.iter_mut().find(|e| e.id == id) else { return Ok(()) };
        e.set_password(plain)?;
        self.save();
        Ok(())
    }

    pub fn remove(&mut self, id: Uuid) {
        self.entries.retain(|e| e.id != id);
        self.save();
    }
}

// MARK: - 剪贴板历史(上限 200;固定区+未固定;文本优先,图片落盘 PNG)

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ClipEntry {
    pub id: Uuid,
    pub text: String,
    pub copied_at: DateTime<Local>,
    #[serde(default)]
    pub pinned: Option<bool>,
    pub pinned_at: Option<DateTime<Local>>,
    #[serde(default)]
    pub source_name: Option<String>,
    #[serde(default)]
    pub image_path: Option<String>,
}

impl ClipEntry {
    pub fn is_pinned(&self) -> bool {
        self.pinned.unwrap_or(false)
    }
    pub fn is_image(&self) -> bool {
        self.image_path.is_some()
    }
}

#[derive(Debug, Default)]
pub struct ClipboardStore {
    pub entries: Vec<ClipEntry>,
    last_seq: u64,
}

pub const CLIP_CAP: usize = 200;

impl ClipboardStore {
    pub fn load() -> Self {
        let mut s = ClipboardStore { entries: load_json::<Vec<ClipEntry>>("clipboard.json").unwrap_or_default(), last_seq: 0 };
        // 启动后不把已有剪贴板内容当新条目
        s.last_seq = platform::clipboard_sequence();
        s
    }

    fn save(&self) {
        save_json("clipboard.json", &self.entries);
    }

    /// 轮询:剪贴板序号变化 → 文本优先记录,无文本但有图片 → 记录图片条目
    pub fn poll(&mut self) {
        let seq = platform::clipboard_sequence();
        if seq == self.last_seq {
            return;
        }
        self.last_seq = seq;
        let source = platform::foreground_app();

        if let Some(text) = platform::clipboard_text() {
            let text = text.trim().to_string();
            if !text.is_empty() {
                let clipped: String = text.chars().take(4000).collect();
                self.record(ClipEntry {
                    id: Uuid::new_v4(),
                    text: clipped,
                    copied_at: Local::now(),
                    pinned: None,
                    pinned_at: None,
                    source_name: source,
                    image_path: None,
                });
                return;
            }
        }
        // 文本为空 → 尝试图片(rgba → PNG 落盘)
        if let Some((w, h, rgba)) = platform::clipboard_image_rgba() {
            if let Some(path) = save_image_png(w, h, &rgba) {
                self.record(ClipEntry {
                    id: Uuid::new_v4(),
                    text: "图片".into(),
                    copied_at: Local::now(),
                    pinned: None,
                    pinned_at: None,
                    source_name: source,
                    image_path: Some(path),
                });
            }
        }
    }

    /// 去重:已有相同文本内容 → 移到顶部;已固定的留在固定区并刷新时间
    fn record(&mut self, entry: ClipEntry) {
        if let Some(idx) = self
            .entries
            .iter()
            .position(|e| e.text == entry.text && e.image_path.is_none() && entry.image_path.is_none())
        {
            let was_pinned = self.entries[idx].is_pinned();
            let old = self.entries.remove(idx);
            unlink_image(&old); // 文本去重不会走到这,防御图片路径泄漏
            let mut fresh = entry;
            if was_pinned {
                fresh.pinned = Some(true);
                fresh.pinned_at = Some(Local::now());
                self.entries.push(fresh);
            } else {
                self.entries.insert(0, fresh);
            }
        } else {
            self.entries.insert(0, entry);
        }
        self.normalize();
    }

    /// 规范化:固定项(任意序)+ 未固定(新→旧),未固定超过 cap 裁剪
    fn normalize(&mut self) {
        let mut pinned: Vec<ClipEntry> =
            self.entries.iter().filter(|e| e.is_pinned()).cloned().collect();
        pinned.sort_by(|a, b| b.pinned_at.cmp(&a.pinned_at));
        let mut rest: Vec<ClipEntry> =
            self.entries.iter().filter(|e| !e.is_pinned()).cloned().collect();
        if rest.len() > CLIP_CAP {
            rest.truncate(CLIP_CAP);
        }
        pinned.extend(rest);
        self.entries = pinned;
    }

    pub fn copy_back(&mut self, entry: &ClipEntry) -> bool {
        // 选中项 → 回写系统剪贴板(图片条目回写位图);序号对齐避免自记
        let ok = if let Some(path) = &entry.image_path {
            std::fs::read(path).ok()
                .and_then(|bytes| image::load_from_memory(&bytes).ok())
                .map(|img| {
                    let rgba = img.to_rgba8();
                    platform::clipboard_set_image(rgba.width() as usize, rgba.height() as usize, rgba.into_raw())
                })
                .unwrap_or(false)
        } else {
            platform::clipboard_set_text(&entry.text)
        };
        if ok {
            self.suppress_next_poll();
        }
        ok
    }

    /// 复制密码等场景下,避免下一次轮询把剪贴板内容记录为历史
    pub fn suppress_next_poll(&mut self) {
        self.last_seq = platform::clipboard_sequence();
    }

    // MARK: PinManager 行为

    pub fn toggle_pin(&mut self, id: Uuid) {
        if let Some(e) = self.entries.iter_mut().find(|e| e.id == id) {
            if e.is_pinned() {
                e.pinned = None;
                e.pinned_at = None;
            } else {
                e.pinned = Some(true);
                e.pinned_at = Some(Local::now());
            }
        }
        self.normalize();
        self.save();
    }

    // MARK: 清除(zh 文案证据:"清除未置顶的项目,按住⇧以全部清除")

    pub fn clear_unpinned(&mut self) {
        let old = std::mem::take(&mut self.entries);
        self.entries = old
            .into_iter()
            .filter(|e| {
                if e.is_pinned() {
                    true
                } else {
                    unlink_image(e);
                    false
                }
            })
            .collect();
        self.save();
    }

    pub fn clear_all(&mut self) {
        self.entries.iter().for_each(unlink_image);
        self.entries.clear();
        self.save();
    }

    // MARK: 搜索(包含匹配;固定区在前)

    pub fn visible(&self, query: &str) -> Vec<ClipEntry> {
        let q = query.to_lowercase();
        let mut pinned: Vec<ClipEntry> = self
            .entries
            .iter()
            .filter(|e| e.is_pinned() && (q.is_empty() || e.text.to_lowercase().contains(&q)))
            .cloned()
            .collect();
        pinned.sort_by(|a, b| b.pinned_at.cmp(&a.pinned_at));
        let rest: Vec<ClipEntry> = self
            .entries
            .iter()
            .filter(|e| !e.is_pinned() && (q.is_empty() || e.text.to_lowercase().contains(&q)))
            .cloned()
            .collect();
        pinned.into_iter().chain(rest).collect()
    }

    pub fn remove(&mut self, id: Uuid) {
        if let Some(i) = self.entries.iter().position(|e| e.id == id) {
            let old = self.entries.remove(i);
            unlink_image(&old);
            self.save();
        }
    }
}

fn unlink_image(entry: &ClipEntry) {
    if let Some(path) = &entry.image_path {
        let _ = std::fs::remove_file(path); // 只删 images/ 下本应用生成的具体文件
    }
}

/// 图片落盘为 PNG(数据目录 images/ 下,UUID 命名)
fn save_image_png(w: usize, h: usize, rgba: &[u8]) -> Option<String> {
    let dir = crate::settings::data_dir().join("images");
    std::fs::create_dir_all(&dir).ok()?;
    let img = image::RgbaImage::from_raw(w as u32, h as u32, rgba.to_vec())?;
    let name = format!("{}.png", Uuid::new_v4());
    let path = dir.join(name);
    img.save_with_format(&path, image::ImageFormat::Png).ok()?;
    Some(path.to_string_lossy().to_string())
}

/// DPAPI 辅助暴露给 vault(平台无关签名)
pub mod dpapi {
    use base64::Engine as _;
    pub fn protect(plain: &str) -> Result<String, String> {
        crate::platform::protect(plain)
    }
    pub fn unprotect(b64: &str) -> Option<String> {
        crate::platform::unprotect(b64)
    }
    pub fn b64_encode(data: &[u8]) -> String {
        base64::engine::general_purpose::STANDARD.encode(data)
    }
}
