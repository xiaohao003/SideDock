// downloads.rs — 下载文件夹监控(对应 macOS 版 DownloadsStore)
// 证据: 最近=3 天 / 今天、昨天、本周、更早 分组 / .crdownload/.part 进行中 / 大小+相对时间
use crate::platform;
use chrono::{DateTime, Duration, Local};
use serde::{Deserialize, Serialize};
use std::path::PathBuf;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DownloadFile {
    pub path: PathBuf,
    pub name: String,
    pub size: i64,   // 文件夹 = -1
    pub date: DateTime<Local>,
    pub is_partial: bool, // .crdownload / .download / .part
}

impl DownloadFile {
    pub fn size_text(&self) -> String {
        if self.size < 0 {
            return "文件夹".into();
        }
        format_bytes(self.size as f64)
    }
}

fn format_bytes(bytes: f64) -> String {
    const UNITS: [&str; 6] = ["B", "KB", "MB", "GB", "TB", "PB"];
    let mut v = bytes;
    let mut unit = 0;
    while v >= 1024.0 && unit < UNITS.len() - 1 {
        v /= 1024.0;
        unit += 1;
    }
    if unit == 0 {
        format!("{} B", v as i64)
    } else {
        format!("{:.1} {}", v, UNITS[unit])
    }
}

/// 今天 / 昨天 / 本周 / 更早(渲染证据分组)
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
pub enum DownloadGroup {
    Today,
    Yesterday,
    Week,
    Earlier,
}

impl DownloadGroup {
    pub fn title(self) -> &'static str {
        match self {
            DownloadGroup::Today => "今天",
            DownloadGroup::Yesterday => "昨天",
            DownloadGroup::Week => "本周",
            DownloadGroup::Earlier => "更早",
        }
    }

    pub fn of(date: &DateTime<Local>) -> DownloadGroup {
        let today = Local::now().date_naive();
        let d = date.date_naive();
        if d == today {
            DownloadGroup::Today
        } else if d == today - Duration::days(1) {
            DownloadGroup::Yesterday
        } else if (Local::now() - *date).num_hours() < 7 * 24 {
            DownloadGroup::Week
        } else {
            DownloadGroup::Earlier
        }
    }
}

#[derive(Debug, Default)]
pub struct DownloadsStore {
    pub files: Vec<DownloadFile>,
    pub read_error: bool,
    pub recent_only: bool, // 渲染证据:分段「最近 | 全部」— 最近 = 3 天
}

pub const RECENT_DAYS: i64 = 3;

impl DownloadsStore {
    pub fn new() -> Self {
        let mut s = DownloadsStore { recent_only: true, ..Default::default() };
        s.refresh();
        s
    }

    pub fn downloads_dir() -> PathBuf {
        dirs::download_dir().unwrap_or_else(|| {
            dirs::home_dir().unwrap_or_else(|| PathBuf::from(".")).join("Downloads")
        })
    }

    pub fn refresh(&mut self) {
        let dir = Self::downloads_dir();
        let Ok(entries) = std::fs::read_dir(&dir) else {
            self.read_error = true;
            return;
        };
        self.read_error = false;
        let cutoff = Local::now() - Duration::days(RECENT_DAYS);
        let mut result: Vec<DownloadFile> = Vec::new();
        for entry in entries.flatten() {
            let Ok(meta) = entry.metadata() else { continue };
            let name = entry.file_name().to_string_lossy().to_string();
            if name.starts_with('.') {
                continue;
            }
            let date: DateTime<Local> = meta
                .modified()
                .ok()
                .map(DateTime::from)
                .unwrap_or_else(Local::now);
            if self.recent_only && date <= cutoff {
                continue;
            }
            let is_dir = meta.is_dir();
            let size = if is_dir { -1 } else { meta.len() as i64 };
            let lower = name.to_lowercase();
            let partial = lower.ends_with(".crdownload")
                || lower.ends_with(".download")
                || lower.ends_with(".part");
            result.push(DownloadFile {
                path: entry.path(),
                name,
                size,
                date,
                is_partial: partial,
            });
        }
        result.sort_by(|a, b| b.date.cmp(&a.date));
        result.truncate(60);
        self.files = result;
    }

    pub fn open(&self, f: &DownloadFile) {
        platform::open_path(&f.path);
    }

    pub fn reveal(&self, f: &DownloadFile) {
        platform::reveal_in_explorer(&f.path);
    }

    pub fn trash(&mut self, f: &DownloadFile) {
        platform::trash_path(&f.path);
        self.refresh();
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn byte_formatting() {
        assert_eq!(format_bytes(512.0), "512 B");
        assert_eq!(format_bytes(2048.0), "2.0 KB");
        assert_eq!(format_bytes(5.0 * 1024.0 * 1024.0), "5.0 MB");
    }

    #[test]
    fn group_ordering() {
        let now = Local::now();
        assert!(DownloadGroup::of(&now) == DownloadGroup::Today);
        let week_window = DownloadGroup::of(&(now - Duration::days(6)));
        assert_eq!(week_window, DownloadGroup::Week);
        let earlier = DownloadGroup::of(&(now - Duration::days(10)));
        assert_eq!(earlier, DownloadGroup::Earlier);
    }
}
