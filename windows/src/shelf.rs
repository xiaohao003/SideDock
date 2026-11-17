// shelf.rs — 暂存(对应 macOS 版 ShelfStore:只记录文件位置,不复制文件)
use crate::settings::{load_json, save_json};
use chrono::{DateTime, Local};
use serde::{Deserialize, Serialize};
use std::path::PathBuf;
use uuid::Uuid;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ShelfItem {
    pub id: Uuid,
    pub path: PathBuf,
    pub added_at: DateTime<Local>,
}

#[derive(Debug, Default)]
pub struct ShelfStore {
    pub items: Vec<ShelfItem>,
}

impl ShelfStore {
    pub fn load() -> Self {
        ShelfStore { items: load_json::<Vec<ShelfItem>>("shelf.json").unwrap_or_default() }
    }

    fn save(&self) {
        save_json("shelf.json", &self.items);
    }

    pub fn add(&mut self, path: PathBuf) {
        if self.items.iter().any(|it| it.path == path) {
            return;
        }
        self.items.insert(0, ShelfItem { id: Uuid::new_v4(), path, added_at: Local::now() });
        self.save();
    }

    /// 多文件批量暂存(保持拖入顺序,逐个去重;对应 macOS 版同名修复)
    pub fn add_many(&mut self, paths: Vec<PathBuf>) {
        for path in paths.into_iter().rev() {
            if self.items.iter().any(|it| it.path == path) {
                continue;
            }
            self.items.insert(0, ShelfItem { id: Uuid::new_v4(), path, added_at: Local::now() });
        }
        self.save();
    }

    pub fn remove(&mut self, id: Uuid) {
        self.items.retain(|it| it.id != id);
        self.save();
    }

    pub fn clear(&mut self) {
        self.items.clear();
        self.save();
    }
}
