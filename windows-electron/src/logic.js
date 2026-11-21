// logic.js — 纯逻辑层(不依赖 electron,可被 node:test 直接测试)
// 移植自 Rust 版 todo.rs / downloads.rs / stores.rs / app.rs 的判定函数
'use strict';

// MARK: - 本地日期(与 chrono date_naive 对齐;ISO 'YYYY-MM-DD',本地时区)

function localDateStr(d) {
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, '0');
  const day = String(d.getDate()).padStart(2, '0');
  return `${y}-${m}-${day}`;
}

function addDaysISO(iso, n) {
  const [y, m, d] = iso.split('-').map(Number);
  const dt = new Date(y, m - 1, d + n);
  return localDateStr(dt);
}

// MARK: - 待办分组(单一事实源,与 Rust todo.rs 同规则)

/** 到期预设 → 到期时间(ISO 字符串):今日=今天 18:00 / 明日=明天 09:00 /
 *  一周=7 天后 09:00 / 长期=null。一律"日历日+固定时刻",不能用 now+7×24h。 */
function dueDateForPreset(preset, now) {
  const base = new Date(now);
  const make = (days, hour, minute) => {
    const dt = new Date(base.getFullYear(), base.getMonth(), base.getDate() + days, hour, minute, 0);
    return dt.toISOString();
  };
  switch (preset) {
    case 1: return make(0, 18, 0);
    case 2: return make(1, 9, 0);
    case 3: return make(7, 9, 0);
    default: return null; // 5 长期:没有时间
  }
}

/** 按到期时间分组:无时间 = 5(长期);今天 = 1;明天 = 2;其余 = 3(一周) */
function dueBucket(item, today) {
  if (!item.due) return 5;
  const d = localDateStr(new Date(item.due));
  if (d === today) return 1;
  if (d === addDaysISO(today, 1)) return 2;
  return 3;
}

/** 条目分组:完成当天仍留原分组(划线可恢复),次日归档历史(4);
 *  done_at 缺失的旧数据保守按历史。 */
function bucketOf(item, today) {
  if (item.done) {
    const doneToday = item.done_at ? localDateStr(new Date(item.done_at)) === today : false;
    if (doneToday) return dueBucket(item, today);
    return 4;
  }
  return dueBucket(item, today);
}

function countFor(items, filter, today) {
  return items.filter((it) => bucketOf(it, today) === filter).length;
}

// MARK: - 随机强密码(与 Rust stores.rs 同字符集:去除易混淆字符)

const FULL_CHARSET = 'abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789!@#$%&*?';
const LETTER_CHARSET = 'abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ';

function generatePassword(length, symbols) {
  const charset = symbols ? FULL_CHARSET : LETTER_CHARSET;
  let out = '';
  const buf = new Uint32Array(length);
  require('crypto').webcrypto.getRandomValues(buf);
  for (let i = 0; i < length; i++) out += charset[buf[i] % charset.length];
  return out;
}

// MARK: - 文件大小(与 Rust downloads.rs format_bytes 同格式)

function formatBytes(bytes) {
  const UNITS = ['B', 'KB', 'MB', 'GB', 'TB', 'PB'];
  let v = bytes;
  let unit = 0;
  while (v >= 1024.0 && unit < UNITS.length - 1) {
    v /= 1024.0;
    unit += 1;
  }
  if (unit === 0) return `${Math.floor(v)} B`;
  return `${v.toFixed(1)} ${UNITS[unit]}`;
}

// MARK: - 下载分组:今天 / 昨天 / 本周(168h 内)/ 更早

function downloadGroupOf(date, now = new Date()) {
  const d0 = date instanceof Date ? date : new Date(date);
  const today = localDateStr(now);
  const d = localDateStr(d0);
  if (d === today) return '今天';
  if (d === addDaysISO(today, -1)) return '昨天';
  if (now.getTime() - d0.getTime() < 7 * 24 * 3600 * 1000) return '本周';
  return '更早';
}

// MARK: - 位置越界夹回(移植自 Rust app.rs clamp_into_bounds,含同款测试)

/** 把窗口左上角 (x,y) 夹到与虚拟桌面 (vx,vy,vw,vh) 至少相交 160×96 的位置。
 *  先 max 后 min,范围反转时不 panic;返回 null 表示输入非有限值应回退停靠。 */
function clampIntoBounds(x, y, w, h, vx, vy, vw, vh) {
  if (!Number.isFinite(x) || !Number.isFinite(y) || !(w > 0) || !(h > 0)) return null;
  const minW = Math.min(160, w);
  const minH = Math.min(96, h);
  const right = vx + vw;
  const bottom = vy + vh;
  const cx = Math.max(vx + minW - w, Math.min(right - minW, x));
  const cy = Math.max(vy + minH - h, Math.min(bottom - minH, y));
  return [cx, cy];
}

// MARK: - 全局快捷键(与 Rust settings.rs HotkeySpec/display 对齐)

function hotkeyDisplay(spec) {
  if (!spec) spec = { ctrl: true, alt: true, shift: false, win: false, code: 'KeyS' };
  const parts = [];
  if (spec.ctrl) parts.push('Ctrl');
  if (spec.alt) parts.push('Alt');
  if (spec.shift) parts.push('Shift');
  if (spec.win) parts.push('Win');
  let key = spec.code;
  if (key === 'Space') key = '空格';
  else if (key.startsWith('Key')) key = key.slice(3);
  else if (key.startsWith('Digit')) key = key.slice(5);
  parts.push(key);
  return parts.join('+');
}

/** HotkeySpec → Electron globalShortcut accelerator */
function hotkeyAccelerator(spec) {
  if (!spec) return 'Control+Alt+S';
  const parts = [];
  if (spec.ctrl) parts.push('Control');
  if (spec.alt) parts.push('Alt');
  if (spec.shift) parts.push('Shift');
  if (spec.win) parts.push('Super');
  let key = spec.code;
  if (key.startsWith('Key')) key = key.slice(3);
  else if (key.startsWith('Digit')) key = key.slice(5);
  parts.push(key);
  return parts.join('+');
}

module.exports = {
  localDateStr,
  addDaysISO,
  dueDateForPreset,
  dueBucket,
  bucketOf,
  countFor,
  generatePassword,
  formatBytes,
  downloadGroupOf,
  clampIntoBounds,
  hotkeyDisplay,
  hotkeyAccelerator,
};
