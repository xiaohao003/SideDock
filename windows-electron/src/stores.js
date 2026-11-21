// stores.js — 数据层(与 Rust 版同目录同名文件同字段,升级无缝沿用旧数据)
// 数据目录:%APPDATA%\SideDock(SIDEDOCK_DATA_DIR 可覆盖,冒烟/测试用)
// settings.json / todos.json / notes.json / shelf.json / vault.json / clipboard.json / images/
'use strict';

const fs = require('fs');
const path = require('path');
const { randomUUID } = require('crypto');
const logic = require('./logic');

let dataDir = '.';
let imagesDir = '.';
let protectFn = null; // (plain) => Promise<string> — safeStorage DPAPI,main 注入
let unprotectFn = null; // (b64) => Promise<string|null>

function setDataDir(dir) {
  dataDir = dir;
  imagesDir = path.join(dir, 'images');
  fs.mkdirSync(dir, { recursive: true });
  fs.mkdirSync(imagesDir, { recursive: true });
}

function setVaultCrypto(protect, unprotect) {
  protectFn = protect;
  unprotectFn = unprotect;
}

function getDataDir() {
  return dataDir;
}

function dataFile(name) {
  return path.join(dataDir, name);
}

function loadJson(name, fallback) {
  try {
    return JSON.parse(fs.readFileSync(dataFile(name), 'utf8'));
  } catch {
    return fallback;
  }
}

function saveJson(name, value) {
  // 原子写(同 Rust:tmp + rename)
  const target = dataFile(name);
  const tmp = target.replace(/(\.[a-z]+)?$/, '.tmp');
  try {
    fs.writeFileSync(tmp, JSON.stringify(value, null, 2));
    fs.renameSync(tmp, target);
  } catch {
    try { fs.unlinkSync(tmp); } catch { /* 忽略 */ }
  }
}

// MARK: - 设置(字段名与 Rust settings.rs 完全一致,serde default 等价缺省回退)

const DEFAULT_HOTKEY = { ctrl: true, alt: true, shift: false, win: false, code: 'KeyS' };

const DEFAULT_SETTINGS = {
  theme_mode: 'System',
  theme_is_dark: false,
  pinned: true,
  auto_paste: true,
  launch_at_login: false,
  hotkey: DEFAULT_HOTKEY,
  tab: 'Todo',
  show_music: true,
  pos: null,
};

const PANEL_W = 472;
const PANEL_H = 519;
const MIN_W = 391;
const MIN_H = 388;
const MAX_W = 751;
const MAX_H = 1052;

function loadSettings() {
  const raw = loadJson('settings.json', {});
  const s = { ...DEFAULT_SETTINGS, ...(raw || {}) };
  if (!s.hotkey || typeof s.hotkey !== 'object') s.hotkey = { ...DEFAULT_HOTKEY };
  else s.hotkey = { ...DEFAULT_HOTKEY, ...s.hotkey };
  if (!Array.isArray(s.pos) || s.pos.length !== 2 || !Number.isFinite(s.pos[0]) || !Number.isFinite(s.pos[1])) {
    s.pos = null;
  }
  return s;
}

let saveTimer = null;
let dirtySettings = null;
function saveSettings(settings) {
  dirtySettings = settings;
  if (saveTimer) return;
  // 轻量去抖(拖动窗口结束/连点开关时避免高频写盘;最长 300ms)
  saveTimer = setTimeout(() => {
    saveTimer = null;
    if (dirtySettings) saveJson('settings.json', dirtySettings);
    dirtySettings = null;
  }, 120);
}

// MARK: - 待办

function loadTodos() {
  const items = loadJson('todos.json', []);
  return Array.isArray(items) ? items : [];
}

function saveTodos(items) {
  saveJson('todos.json', items);
}

function addTodo(items, title, due) {
  const item = {
    id: randomUUID(),
    title,
    due: due || null,
    done: false,
    done_at: null,
    created_at: new Date().toISOString(),
  };
  items.push(item);
  saveTodos(items);
  return item;
}

function toggleTodo(items, id) {
  const it = items.find((x) => x.id === id);
  if (it) {
    it.done = !it.done;
    it.done_at = it.done ? new Date().toISOString() : null;
    saveTodos(items);
  }
}

function removeTodo(items, id) {
  const idx = items.findIndex((x) => x.id === id);
  if (idx >= 0) {
    items.splice(idx, 1);
    saveTodos(items);
  }
}

// MARK: - 笔记

function loadNotes() {
  const notes = loadJson('notes.json', []);
  return Array.isArray(notes) ? notes : [];
}

function saveNotes(notes) {
  saveJson('notes.json', notes);
}

function addNote(notes, text) {
  notes.unshift({ id: randomUUID(), text, created_at: new Date().toISOString() });
  saveNotes(notes);
}

function removeNote(notes, id) {
  const idx = notes.findIndex((n) => n.id === id);
  if (idx >= 0) {
    notes.splice(idx, 1);
    saveNotes(notes);
  }
}

// MARK: - 暂存(只记录文件位置,不复制文件)

function loadShelf() {
  const items = loadJson('shelf.json', []);
  return Array.isArray(items) ? items : [];
}

function saveShelf(items) {
  saveJson('shelf.json', items);
}

function addShelfMany(items, paths) {
  // 多文件批量暂存:保持拖入顺序(与 Rust add_many 同:倒序逐个插顶)
  for (const p of [...paths].reverse()) {
    if (items.some((it) => it.path === p)) continue;
    items.unshift({ id: randomUUID(), path: p, added_at: new Date().toISOString() });
  }
  saveShelf(items);
}

function removeShelf(items, id) {
  const idx = items.findIndex((it) => it.id === id);
  if (idx >= 0) {
    items.splice(idx, 1);
    saveShelf(items);
  }
}

function clearShelf(items) {
  items.length = 0;
  saveShelf(items);
}

// MARK: - 密码保险库(vault.json;密码经 DPAPI 加密为 base64,仅本机可解)

function loadVault() {
  const entries = loadJson('vault.json', []);
  return Array.isArray(entries) ? entries : [];
}

function saveVault(entries) {
  saveJson('vault.json', entries);
}

async function addVaultEntry(entries, { site, account, phone, note, password }) {
  const entry = {
    id: randomUUID(),
    site,
    account,
    phone: phone || null,
    note: note || null,
    created_at: new Date().toISOString(),
    pw: null,
  };
  if (password) {
    entry.pw = await protectFn(password);
  }
  entries.unshift(entry);
  saveVault(entries);
  return entry;
}

async function updateVaultPassword(entries, id, plain) {
  const e = entries.find((x) => x.id === id);
  if (!e) return;
  e.pw = await protectFn(plain);
  saveVault(entries);
}

async function revealVault(entry) {
  if (!entry.pw) return null;
  try {
    return await unprotectFn(entry.pw);
  } catch {
    return null;
  }
}

function removeVault(entries, id) {
  const idx = entries.findIndex((e) => e.id === id);
  if (idx >= 0) {
    entries.splice(idx, 1);
    saveVault(entries);
  }
}

// MARK: - 剪贴板历史(上限 200;固定区+未固定;文本优先,图片落盘 PNG)

const CLIP_CAP = 200;

function loadClips() {
  const entries = loadJson('clipboard.json', []);
  return Array.isArray(entries) ? entries : [];
}

function saveClips(entries) {
  saveJson('clipboard.json', entries);
}

function clipIsPinned(e) {
  return e.pinned === true;
}

/** 去重记录:相同文本 → 移到顶部(固定项留固定区并刷新时间) */
function recordClip(entries, entry) {
  const idx = entries.findIndex((e) => e.text === entry.text && !e.image_path && !entry.image_path);
  if (idx >= 0) {
    const wasPinned = clipIsPinned(entries[idx]);
    entries.splice(idx, 1);
    if (wasPinned) {
      entry.pinned = true;
      entry.pinned_at = new Date().toISOString();
      entries.push(entry);
    } else {
      entries.unshift(entry);
    }
  } else {
    entries.unshift(entry);
  }
  normalizeClips(entries);
  saveClips(entries);
}

/** 规范化:固定项(新→旧)+ 未固定(新→旧),未固定超过 cap 裁剪 */
function normalizeClips(entries) {
  const pinned = entries
    .filter((e) => clipIsPinned(e))
    .sort((a, b) => new Date(b.pinned_at || 0) - new Date(a.pinned_at || 0));
  const rest = entries.filter((e) => !clipIsPinned(e)).slice(0, CLIP_CAP);
  entries.length = 0;
  entries.push(...pinned, ...rest);
}

function toggleClipPin(entries, id) {
  const e = entries.find((x) => x.id === id);
  if (!e) return;
  if (clipIsPinned(e)) {
    e.pinned = null;
    e.pinned_at = null;
  } else {
    e.pinned = true;
    e.pinned_at = new Date().toISOString();
  }
  normalizeClips(entries);
  saveClips(entries);
}

/** 搜索可见列表(固定区在前,包含匹配) */
function visibleClips(entries, query) {
  const q = (query || '').toLowerCase();
  const pinned = entries
    .filter((e) => clipIsPinned(e) && (q === '' || e.text.toLowerCase().includes(q)))
    .sort((a, b) => new Date(b.pinned_at || 0) - new Date(a.pinned_at || 0));
  const rest = entries.filter((e) => !clipIsPinned(e) && (q === '' || e.text.toLowerCase().includes(q)));
  return [...pinned, ...rest];
}

function removeClip(entries, id) {
  const idx = entries.findIndex((e) => e.id === id);
  if (idx >= 0) {
    const [old] = entries.splice(idx, 1);
    unlinkClipImage(old);
    saveClips(entries);
  }
}

function clearClipsUnpinned(entries) {
  const kept = entries.filter((e) => {
    if (clipIsPinned(e)) return true;
    unlinkClipImage(e);
    return false;
  });
  entries.length = 0;
  entries.push(...kept);
  saveClips(entries);
}

function clearClipsAll(entries) {
  entries.forEach(unlinkClipImage);
  entries.length = 0;
  saveClips(entries);
}

function unlinkClipImage(entry) {
  // 只删 images/ 下本应用生成的具体文件(防路径注入,同 Rust)
  if (!entry || !entry.image_path) return;
  try {
    const abs = path.resolve(entry.image_path);
    if (path.resolve(imagesDir) === path.dirname(abs)) fs.unlinkSync(abs);
  } catch { /* 忽略 */ }
}

function saveClipImagePng(pngBuffer) {
  const name = `${randomUUID()}.png`;
  const abs = path.join(imagesDir, name);
  fs.writeFileSync(abs, pngBuffer);
  return abs;
}

module.exports = {
  setDataDir,
  setVaultCrypto,
  getDataDir,
  dataFile,
  loadJson,
  saveJson,
  DEFAULT_SETTINGS,
  PANEL_W,
  PANEL_H,
  MIN_W,
  MIN_H,
  MAX_W,
  MAX_H,
  loadSettings,
  saveSettings,
  loadTodos,
  saveTodos,
  addTodo,
  toggleTodo,
  removeTodo,
  loadNotes,
  saveNotes,
  addNote,
  removeNote,
  loadShelf,
  saveShelf,
  addShelfMany,
  removeShelf,
  clearShelf,
  loadVault,
  saveVault,
  addVaultEntry,
  updateVaultPassword,
  revealVault,
  removeVault,
  CLIP_CAP,
  loadClips,
  saveClips,
  clipIsPinned,
  recordClip,
  normalizeClips,
  toggleClipPin,
  visibleClips,
  removeClip,
  clearClipsUnpinned,
  clearClipsAll,
  saveClipImagePng,
  logic,
};
