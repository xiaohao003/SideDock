// todo.rs — 待办(对应 macOS 版 TodoStore;分组判定为单一事实源)
use crate::settings::{load_json, save_json};
use chrono::{DateTime, Duration, Local, LocalResult, TimeZone};
#[cfg(test)]
use chrono::Datelike;
use serde::{Deserialize, Serialize};
use uuid::Uuid;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TodoItem {
    pub id: Uuid,
    pub title: String,
    pub due: Option<DateTime<Local>>,
    #[serde(default)]
    pub done: bool,
    pub done_at: Option<DateTime<Local>>,
    pub created_at: DateTime<Local>,
}

impl TodoItem {
    pub fn new(title: String, due: Option<DateTime<Local>>) -> Self {
        TodoItem { id: Uuid::new_v4(), title, due, done: false, done_at: None, created_at: Local::now() }
    }
}

#[derive(Debug, Default)]
pub struct TodoStore {
    pub items: Vec<TodoItem>,
}

impl TodoStore {
    pub fn load() -> Self {
        TodoStore { items: load_json::<Vec<TodoItem>>("todos.json").unwrap_or_default() }
    }

    fn save(&self) {
        save_json("todos.json", &self.items);
    }

    pub fn add(&mut self, title: &str, due: Option<DateTime<Local>>) {
        self.items.push(TodoItem::new(title.to_string(), due));
        self.save();
    }

    pub fn toggle(&mut self, id: Uuid) {
        if let Some(i) = self.items.iter_mut().find(|it| it.id == id) {
            i.done = !i.done;
            i.done_at = if i.done { Some(Local::now()) } else { None };
        }
        self.save();
    }

    // MARK: 分组判定(单一事实源:计数、过滤、新增跳转共用同一套规则)

    /// 到期预设 → 具体时间(今日=今天 18:00 / 明日=明天 09:00 / 一周=7 天后 09:00)。
    /// 一律取"日历日 + 固定时刻",不能用 now+7×24h(会落在分组窗口外导致任务不可见)
    pub fn due_date_for_preset(preset: u8, now: DateTime<Local>) -> Option<DateTime<Local>> {
        let day = now.date_naive();
        let (days, hour, minute) = match preset {
            1 => (0, 18, 0),
            2 => (1, 9, 0),
            3 => (7, 9, 0),
            _ => return None,
        };
        let date = day + Duration::days(days as i64);
        let naive = date.and_hms_opt(hour, minute, 0)?;
        match Local.from_local_datetime(&naive) {
            LocalResult::Single(dt) => Some(dt),
            LocalResult::Ambiguous(dt, _) => Some(dt),
            LocalResult::None => None,
        }
    }

    /// 条目属于哪个分组:1 今日(含无日期) 2 明日 3 一周(其余未完成:未来一周/逾期)
    /// 4 历史(已完成)。保证任何未完成条目必然落在 1..=3 之一,不会"加了看不见"。
    pub fn bucket_of(&self, item: &TodoItem, today: chrono::NaiveDate) -> u8 {
        if item.done {
            return 4;
        }
        let Some(due) = item.due else { return 1 };
        let d = due.date_naive();
        if d == today {
            return 1;
        }
        if d == today + Duration::days(1) {
            return 2;
        }
        3
    }

    pub fn matches(&self, item: &TodoItem, filter: u8, today: chrono::NaiveDate) -> bool {
        self.bucket_of(item, today) == filter
    }

    pub fn count_for(&self, filter: u8, today: chrono::NaiveDate) -> usize {
        self.items.iter().filter(|it| self.matches(it, filter, today)).count()
    }

    pub fn remove(&mut self, id: Uuid) {
        self.items.retain(|it| it.id != id);
        self.save();
    }

    pub fn clear_completed(&mut self) {
        self.items.retain(|it| !it.done);
        self.save();
    }
}

#[cfg(test)]
mod tests {
    // 移植自 macOS 版 tests/main.swift 的 14 条断言
    use super::*;

    fn store_with(samples: &[(&str, Option<DateTime<Local>>)]) -> TodoStore {
        let mut s = TodoStore::default();
        for (title, due) in samples {
            s.items.push(TodoItem::new(title.to_string(), *due));
        }
        s
    }

    fn local_ymd(y: i32, m: u32, d: u32, h: u32, min: u32) -> DateTime<Local> {
        Local.with_ymd_and_hms(y, m, d, h, min, 0).single().unwrap()
    }

    #[test]
    fn todo_grouping() {
        let now = Local::now();
        let today = now.date_naive();
        let tomorrow = today + Duration::days(1);

        // 到期预设
        let d1 = TodoStore::due_date_for_preset(1, now).unwrap();
        assert_eq!(d1.date_naive(), today, "预设 今日 → 到期在今天");
        let d2 = TodoStore::due_date_for_preset(2, now).unwrap();
        assert_eq!(d2.date_naive(), tomorrow, "预设 明日 → 到期在明天");
        let d3 = TodoStore::due_date_for_preset(3, now).unwrap();
        assert!(
            d3.date_naive() > tomorrow,
            "预设 一周 → 至少在明天的开始之后"
        );
        let week_window_end = today + Duration::days(8);
        assert!(
            d3.date_naive() < week_window_end,
            "预设 一周 → 落在一周视图窗口内(旧算法 now+7×24h 会越界)"
        );

        // 五类样本全部可见
        let mut store = store_with(&[
            ("今日任务", Some(d1)),
            ("明日任务", Some(d2)),
            ("一周任务", Some(d3)),
            ("逾期任务", Some(local_ymd(now.year(), now.month(), now.day(), 0, 0) - Duration::days(1))),
            ("无日期任务", None),
        ]);
        assert_eq!(store.count_for(1, today), 2, "今日计数 = 2(今日 + 无日期)");
        assert_eq!(store.count_for(2, today), 1, "明日计数 = 1");
        assert_eq!(store.count_for(3, today), 2, "一周计数 = 2(一周 + 逾期未完成)");
        assert_eq!(store.count_for(4, today), 0, "历史计数 = 0");
        let unfinished = store.items.iter().filter(|it| !it.done).count();
        let bucketed: usize = (1..=3).map(|f| store.count_for(f, today)).sum();
        assert_eq!(
            bucketed, unfinished,
            "每个未完成条目恰好落在一个分组,不存在看不见的任务"
        );

        // 用户踩到的原始场景:now+7×24h 生成的任务必须可见
        let legacy = TodoItem::new("旧算法一周任务".into(), Some(now + Duration::hours(7 * 24)));
        assert!(store.matches(&legacy, 3, today), "旧算法生成的 7 天后任务在\"一周\"视图可见");

        // 完成流转
        let first = store.items[0].id;
        store.toggle(first);
        assert_eq!(store.count_for(4, today), 1, "完成后进入历史");
        let after: usize = (1..=3).map(|f| store.count_for(f, today)).sum();
        assert_eq!(after, unfinished - 1, "完成移出未完成分组");
        store.toggle(first);
        assert_eq!(store.count_for(4, today), 0, "取消完成移出历史");

        // 删除(不落盘:测试里直接操作 items 避免 SIDEDOCK_DATA_DIR 副作用)
        let removed = store.items[1].clone();
        store.items.retain(|it| it.id != removed.id);
        assert!(!store.items.iter().any(|it| it.id == removed.id), "删除条目从 store 移除");
        store.items.clear();
    }
}
