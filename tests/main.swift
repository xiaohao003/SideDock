// main.swift — 待办分组逻辑无头测试(不启动 App)
// 运行: SIDEDOCK_PROMOSHOT=1 SIDEDOCK_DATA_DIR=<空目录> \
//   swiftc Sources/{AppState,Stores,Downloads,PasteHelper,MusicController,ShelfBarController,Panel,Views}.swift tests/main.swift -o /tmp/todo-test && /tmp/todo-test
import Foundation

var failures = 0
func expect(_ cond: Bool, _ name: String) {
    print((cond ? "PASS  " : "FAIL  ") + name)
    if !cond { failures += 1 }
}

let cal = Calendar.current
let today = cal.startOfDay(for: Date())

// 到期预设
let d1 = TodoStore.dueDate(forPreset: 1)!
expect(cal.isDateInToday(d1), "预设 今日 → 到期在今天")
let d2 = TodoStore.dueDate(forPreset: 2)!
expect(cal.isDateInTomorrow(d2), "预设 明日 → 到期在明天")
let d3 = TodoStore.dueDate(forPreset: 3)!
expect(d3 > cal.date(byAdding: .day, value: 1, to: today)!, "预设 一周 → 至少在明天的开始之后")
let weekWindowEnd = cal.date(byAdding: .day, value: 8, to: today)!
expect(d3 < weekWindowEnd, "预设 一周 → 落在一周视图窗口内(旧算法 now+7×24h 会越界)")

// 五类样本全部可见
let store = TodoStore()
store.add("今日任务", due: d1)
store.add("明日任务", due: d2)
store.add("一周任务", due: d3)
store.add("逾期任务", due: cal.date(byAdding: .day, value: -1, to: today))
store.add("无日期任务", due: nil)
expect(store.count(for: 1) == 2, "今日计数 = 2(今日 + 无日期)")
expect(store.count(for: 2) == 1, "明日计数 = 1")
expect(store.count(for: 3) == 2, "一周计数 = 2(一周 + 逾期未完成)")
expect(store.count(for: 4) == 0, "历史计数 = 0")
let unfinished = store.items.filter { !$0.done }.count
let bucketed = (1...3).reduce(0) { $0 + store.count(for: $1) }
expect(bucketed == unfinished, "每个未完成条目恰好落在一个分组(\(bucketed)/\(unfinished)),不存在看不见的任务")

// 用户踩到的原始场景:now+7×24h 生成的任务必须可见
let legacy = TodoItem(title: "旧算法一周任务", due: Date().addingTimeInterval(7 * 86400))
expect(store.matches(legacy, filter: 3), "旧算法生成的 7 天后任务在\"一周\"视图可见")

// 完成流转:当天完成留在原分组,次日归档历史
let first = store.items[0]
store.toggle(first.id)
expect(store.count(for: 1) == 2, "当天完成的今日任务仍留在\"今日\"分组(计数不变)")
expect(store.count(for: 4) == 0, "当天完成不立即进历史")
let after = store.count(for: 1) + store.count(for: 2) + store.count(for: 3)
expect(after == unfinished, "完成未归档仍计入分组计数")
store.toggle(first.id)
expect(store.count(for: 1) == 2 && store.count(for: 4) == 0, "取消完成移出历史状态")
// 昨天完成的 → 历史
var oldDone = store.items[0]
oldDone.done = true
oldDone.doneAt = cal.date(byAdding: .day, value: -1, to: Date())
expect(store.bucket(of: oldDone) == 4, "昨日完成的任务进入历史")
// doneAt 缺失的旧数据 → 保守按历史
var legacyDone = store.items[1]
legacyDone.done = true
legacyDone.doneAt = nil
expect(store.bucket(of: legacyDone) == 4, "无完成时间的已完成条目按历史处理")

// 删除
let removed = store.items[1]
store.remove(removed.id)
expect(!store.items.contains(removed), "删除条目从 store 移除")

if failures == 0 {
    print("ALL PASS")
    exit(0)
}
print("\(failures) FAILURES")
exit(1)
