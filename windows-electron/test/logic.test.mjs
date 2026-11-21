// logic.test.mjs — 纯逻辑层测试(移植 Rust 版 cargo test 断言)
import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  localDateStr, addDaysISO, dueDateForPreset, bucketOf, countFor,
  generatePassword, formatBytes, downloadGroupOf, clampIntoBounds,
  hotkeyDisplay, hotkeyAccelerator,
} from '../src/logic.js';

const DAY = 24 * 3600 * 1000;

function item(title, due, done = false, doneAt = null) {
  return { id: title, title, due, done, done_at: doneAt, created_at: new Date().toISOString() };
}

test('到期预设:今日/明日/一周落在对应日历日,长期无时间', () => {
  const now = new Date();
  const today = localDateStr(now);
  const d1 = new Date(dueDateForPreset(1, now));
  assert.equal(localDateStr(d1), today, '预设 今日 → 到期在今天');
  assert.equal(d1.getHours(), 18, '预设 今日 → 18:00');
  const d2 = new Date(dueDateForPreset(2, now));
  assert.equal(localDateStr(d2), addDaysISO(today, 1), '预设 明日 → 到期在明天');
  const d3 = new Date(dueDateForPreset(3, now));
  const d3s = localDateStr(d3);
  assert.ok(d3s > addDaysISO(today, 1), '预设 一周 → 至少在明天的开始之后');
  assert.ok(d3s < addDaysISO(today, 8), '预设 一周 → 落在一周视图窗口内(旧算法 now+7×24h 会越界)');
  assert.equal(dueDateForPreset(5, now), null, '预设 长期 → 无到期时间');
});

test('五类样本全部可见:无日期进长期,逾期未完成进一周', () => {
  const now = new Date();
  const today = localDateStr(now);
  const store = [
    item('今日任务', dueDateForPreset(1, now)),
    item('明日任务', dueDateForPreset(2, now)),
    item('一周任务', dueDateForPreset(3, now)),
    item('逾期任务', new Date(today + 'T00:00:00').getTime() - DAY ? new Date(Date.now() - DAY).toISOString() : null),
    item('无日期任务', null),
  ];
  assert.equal(countFor(store, 1, today), 1, '今日计数 = 1(仅今日)');
  assert.equal(countFor(store, 2, today), 1, '明日计数 = 1');
  assert.equal(countFor(store, 3, today), 2, '一周计数 = 2(一周 + 逾期未完成)');
  assert.equal(countFor(store, 5, today), 1, '长期计数 = 1(无日期任务)');
  assert.equal(countFor(store, 4, today), 0, '历史计数 = 0');
  const unfinished = store.filter((it) => !it.done).length;
  const bucketed = [1, 2, 3, 5].reduce((acc, f) => acc + countFor(store, f, today), 0);
  assert.equal(bucketed, unfinished, '每个未完成条目恰好落在一个分组,不存在看不见的任务');
});

test('旧算法(now+7×24h)生成的 7 天后任务在"一周"视图可见', () => {
  const now = new Date();
  const today = localDateStr(now);
  const legacy = item('旧算法一周任务', new Date(now.getTime() + 7 * DAY).toISOString());
  assert.equal(bucketOf(legacy, today), 3);
});

test('完成流转:当天留原分组,次日归档历史', () => {
  const now = new Date();
  const today = localDateStr(now);
  const first = item('今日任务', dueDateForPreset(1, now));
  const store = [first, item('明日任务', dueDateForPreset(2, now))];
  first.done = true;
  first.done_at = now.toISOString();
  assert.equal(countFor(store, 1, today), 1, '当天完成的今日任务仍留在"今日"分组');
  assert.equal(countFor(store, 4, today), 0, '当天完成不立即进历史');
  first.done = false;
  first.done_at = null;
  assert.equal(countFor(store, 1, today), 1, '取消完成恢复正常');

  // 长期任务:当天完成留长期,昨日完成进历史
  const longDone = item('长期任务', null, true, now.toISOString());
  assert.equal(bucketOf(longDone, today), 5);
  const longOld = item('长期任务', null, true, new Date(now.getTime() - DAY).toISOString());
  assert.equal(bucketOf(longOld, today), 4, '昨日完成的长期任务进入历史');

  // done_at 缺失的旧数据 → 保守按历史
  const legacyDone = item('旧数据', dueDateForPreset(2, now), true, null);
  assert.equal(bucketOf(legacyDone, today), 4, '无完成时间的已完成条目按历史处理');
});

test('随机强密码:长度与字符集', () => {
  const pw = generatePassword(20, true);
  assert.equal(pw.length, 20);
  const letters = generatePassword(64, false);
  assert.equal(letters.length, 64);
  assert.ok(!/[!@#$%&*?]/.test(letters), '无符号模式不含符号');
  // 大样本下验证字符集已去除易混淆字符 l / 1 / I / O / 0(与 Rust 同字符集)
  for (let i = 0; i < 50; i++) {
    const s = generatePassword(64, true);
    assert.ok(!/[l1IO0]/.test(s), `不应出现易混淆字符:${s}`);
  }
});

test('文件大小格式(同 Rust format_bytes)', () => {
  assert.equal(formatBytes(512), '512 B');
  assert.equal(formatBytes(2048), '2.0 KB');
  assert.equal(formatBytes(5 * 1024 * 1024), '5.0 MB');
});

test('下载分组:今天/昨天/本周/更早', () => {
  const now = new Date();
  assert.equal(downloadGroupOf(now.toISOString()), '今天');
  assert.equal(downloadGroupOf(new Date(now.getTime() - 6 * DAY).toISOString()), '本周');
  assert.equal(downloadGroupOf(new Date(now.getTime() - 10 * DAY).toISOString()), '更早');
});

test('位置越界夹回(移植 Rust clamp_into_bounds 测试)', () => {
  const W = 472, H = 519;
  assert.deepEqual(clampIntoBounds(100, 80, W, H, 0, 0, 1920, 1080), [100, 80], '合法位置不动');
  assert.deepEqual(clampIntoBounds(3000, 200, W, H, 0, 0, 1920, 1080), [1920 - 160, 200], '右侧越界 → 至少露出左缘 160');
  assert.deepEqual(clampIntoBounds(-1500, 200, W, H, 0, 0, 1920, 1080), [-(W - 160), 200], '左侧越界 → 夹回');
  assert.deepEqual(clampIntoBounds(1200, -800, W, H, -1920, 0, 3840, 1080), [1200, 96 - H], '多屏负坐标:y 落到桌面上方 → 露出上缘 96');
  assert.equal(clampIntoBounds(NaN, 0, W, H, 0, 0, 100, 100), null, '非法输入 → null(回退停靠)');
  assert.equal(clampIntoBounds(0, Infinity, W, H, 0, 0, 100, 100), null);
  const r = clampIntoBounds(50, 50, W, H, 0, 0, 100, 100);
  assert.ok(Number.isFinite(r[0]), '极小虚拟桌面不 panic');
});

test('快捷键显示与加速键', () => {
  const spec = { ctrl: true, alt: true, shift: false, win: false, code: 'KeyS' };
  assert.equal(hotkeyDisplay(spec), 'Ctrl+Alt+S');
  assert.equal(hotkeyAccelerator(spec), 'Control+Alt+S');
  assert.equal(hotkeyDisplay({ ctrl: true, alt: true, shift: false, win: false, code: 'Space' }), 'Ctrl+Alt+空格');
  assert.equal(hotkeyAccelerator({ ctrl: false, alt: false, shift: false, win: true, code: 'Digit5' }), 'Super+5');
});
