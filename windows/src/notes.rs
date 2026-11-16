// notes.rs — 笔记(对应 macOS 版 NotesStore)
use crate::settings::{load_json, save_json};
use chrono::{DateTime, Local};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Note {
    pub id: Uuid,
    pub text: String,
    pub created_at: DateTime<Local>,
}

impl Note {
    pub fn new(text: String) -> Self {
        Note { id: Uuid::new_v4(), text, created_at: Local::now() }
    }

    /// 首行为标题(渲染证据:标题+摘要+时间卡片)
    pub fn title_line(&self) -> String {
        self.text.lines().next().unwrap_or(&self.text).to_string()
    }

    pub fn body_line(&self) -> String {
        let mut lines = self.text.lines();
        lines.next();
        lines.collect::<Vec<_>>().join(" ")
    }
}

#[derive(Debug, Default)]
pub struct NotesStore {
    pub notes: Vec<Note>,
}

impl NotesStore {
    pub fn load() -> Self {
        NotesStore { notes: load_json::<Vec<Note>>("notes.json").unwrap_or_default() }
    }

    fn save(&self) {
        save_json("notes.json", &self.notes);
    }

    pub fn insert_top(&mut self, text: String) {
        self.notes.insert(0, Note::new(text));
        self.save();
    }

    pub fn remove(&mut self, id: Uuid) {
        self.notes.retain(|n| n.id != id);
        self.save();
    }
}
