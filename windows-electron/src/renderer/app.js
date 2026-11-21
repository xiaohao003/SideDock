// app.js — 渲染层(六面板 + 设置 + 音乐卡;布局对照 Rust 版 ui/views.rs)
// 策略:切 tab 时重建视图骨架(含输入框);数据推送只刷新动态列表,
// 输入框常驻不重建,避免打字时焦点丢失。
'use strict';

const api = window.sidedock;

let S = null;          // 主进程快照 { settings, todos, notes, shelf, vault, clips, downloads, ... }
let music = null;      // SMTC 快照
const UI = {
  settingsOpen: false,
  todoDraft: '', todoPreset: 1, todoFilter: 1,
  notesAdding: false, notesDraft: '',
  vaultAdding: false, vaultSite: '', vaultAccount: '', vaultPhone: '', vaultPassword: '',
  vaultReveal: null,      // { id, text, until }
  vaultEditFor: null, vaultEditPw: '',
  vaultToast: null,       // { msg, until, error }
  downloadsAll: false, downloadsSearch: '',
  clipSearch: '', clipSelected: null, clipToast: null,
  shelfDrop: false,
};

// MARK: - 纯助手(与主进程 logic.js 同规则)

function localDateStr(d) {
  const p = (n) => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}`;
}
function addDaysISO(iso, n) {
  const [y, m, d] = iso.split('-').map(Number);
  return localDateStr(new Date(y, m - 1, d + n));
}
function dueBucket(item, today) {
  if (!item.due) return 5;
  const d = localDateStr(new Date(item.due));
  if (d === today) return 1;
  if (d === addDaysISO(today, 1)) return 2;
  return 3;
}
function bucketOf(item, today) {
  if (item.done) {
    const doneToday = item.done_at ? localDateStr(new Date(item.done_at)) === today : false;
    return doneToday ? dueBucket(item, today) : 4;
  }
  return dueBucket(item, today);
}
function countFor(items, filter, today) {
  return items.filter((it) => bucketOf(it, today) === filter).length;
}
function visibleClips(entries, query) {
  const q = (query || '').toLowerCase();
  const pinned = entries
    .filter((e) => e.pinned === true && (q === '' || e.text.toLowerCase().includes(q)))
    .sort((a, b) => new Date(b.pinned_at || 0) - new Date(a.pinned_at || 0));
  const rest = entries.filter((e) => e.pinned !== true && (q === '' || e.text.toLowerCase().includes(q)));
  return [...pinned, ...rest];
}
function relTime(iso) {
  const t = new Date(iso);
  const secs = Math.max(0, (Date.now() - t.getTime()) / 1000);
  if (secs < 60) return '刚刚';
  if (secs < 3600) return `${Math.floor(secs / 60)} 分钟前`;
  if (secs < 86400) return `${Math.floor(secs / 3600)} 小时前`;
  if (secs < 7 * 86400) return `${Math.floor(secs / 86400)} 天前`;
  const p = (n) => String(n).padStart(2, '0');
  return `${p(t.getMonth() + 1)}月${p(t.getDate())}日`;
}
function formatBytes(bytes) {
  const UNITS = ['B', 'KB', 'MB', 'GB', 'TB', 'PB'];
  let v = bytes;
  let unit = 0;
  while (v >= 1024.0 && unit < UNITS.length - 1) { v /= 1024.0; unit += 1; }
  if (unit === 0) return `${Math.floor(v)} B`;
  return `${v.toFixed(1)} ${UNITS[unit]}`;
}
function downloadGroupOf(iso) {
  const now = new Date();
  const today = localDateStr(now);
  const d = localDateStr(new Date(iso));
  if (d === today) return '今天';
  if (d === addDaysISO(today, -1)) return '昨天';
  if (now.getTime() - new Date(iso).getTime() < 7 * 24 * 3600 * 1000) return '本周';
  return '更早';
}
const PW_FULL = 'abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789!@#$%&*?';
const PW_LETTER = 'abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ';
function generatePassword(length, symbols) {
  const charset = symbols ? PW_FULL : PW_LETTER;
  const buf = new Uint32Array(length);
  crypto.getRandomValues(buf);
  let out = '';
  for (let i = 0; i < length; i++) out += charset[buf[i] % charset.length];
  return out;
}
function sourceColor(name) {
  const palette = [[59, 130, 246], [16, 185, 129], [245, 158, 11], [239, 68, 68], [139, 92, 246], [6, 182, 212], [236, 72, 153], [132, 204, 22]];
  let h = 0;
  for (const b of new TextEncoder().encode(name || '?')) h = (h * 31 + b) >>> 0;
  return palette[h % palette.length];
}
function mmss(secs) {
  const s = Math.max(0, Math.floor(secs || 0));
  return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`;
}
function displayPosition(snap, nowSecs) {
  if (snap.playing) {
    const p = (snap.position_secs || 0) + Math.max(0, nowSecs - (snap.taken_at_secs || 0));
    return snap.duration_secs > 0 ? Math.min(p, snap.duration_secs) : p;
  }
  return snap.position_secs || 0;
}

const WEEKDAYS = ['星期日', '星期一', '星期二', '星期三', '星期四', '星期五', '星期六'];
const TABS = [
  { id: 'Todo', title: '待办', icon: 'todo' },
  { id: 'Notes', title: '笔记', icon: 'note' },
  { id: 'Downloads', title: '下载', icon: 'download' },
  { id: 'Shelf', title: '暂存', icon: 'shelf' },
  { id: 'Passwords', title: '密码', icon: 'lock' },
  { id: 'Clipboard', title: '剪贴板', icon: 'clipboard' },
];

const $view = document.getElementById('view');
const $tabs = document.getElementById('tabbar');
const $music = document.getElementById('music');

// MARK: - toast

function showToast(kind, msg, error = false) {
  const entry = { msg, until: Date.now() + 2000, error };
  if (kind === 'clip') UI.clipToast = entry;
  else UI.vaultToast = entry;
  updateCurrent();
}
function toastActive(t) {
  return t && Date.now() < t.until;
}

// MARK: - 确认弹框(右键删除待办/笔记/密码前的二次确认)

const confirmState = { open: false, resolve: null };
let confirmBox = null;

function ensureConfirmBox() {
  if (confirmBox) return;
  confirmBox = el(`<div class="confirm-overlay">
    <div class="confirm-card">
      <div class="confirm-icon">${Icon('trash', 20)}</div>
      <div class="confirm-title"></div>
      <div class="confirm-msg"></div>
      <div class="confirm-hint">删除后无法恢复。</div>
      <div class="confirm-btns">
        <span class="confirm-btn cancel">取消</span>
        <span class="confirm-btn danger">删除</span>
      </div>
    </div>
  </div>`);
  confirmBox.querySelector('.confirm-btn.cancel').addEventListener('click', () => closeConfirm(false));
  confirmBox.querySelector('.confirm-btn.danger').addEventListener('click', () => closeConfirm(true));
  confirmBox.addEventListener('click', (e) => { if (e.target === confirmBox) closeConfirm(false); });
  document.body.appendChild(confirmBox);
}

function confirmDialog({ title, message, confirmText = '删除' }) {
  ensureConfirmBox();
  confirmBox.querySelector('.confirm-title').textContent = title;
  confirmBox.querySelector('.confirm-msg').textContent = message;
  confirmBox.querySelector('.confirm-btn.danger').textContent = confirmText;
  confirmBox.classList.add('open');
  confirmState.open = true;
  return new Promise((resolve) => {
    confirmState.resolve = resolve;
    confirmBox.querySelector('.confirm-btn.danger').focus();
  });
}

function closeConfirm(result) {
  if (!confirmState.open) return;
  confirmState.open = false;
  confirmBox.classList.remove('open');
  const resolve = confirmState.resolve;
  confirmState.resolve = null;
  if (resolve) resolve(result);
}

document.addEventListener('keydown', (e) => {
  if (!confirmState.open) return;
  if (e.key === 'Escape') { e.preventDefault(); closeConfirm(false); }
  else if (e.key === 'Enter') { e.preventDefault(); closeConfirm(true); }
});

// MARK: - 头部 / 日期

function renderHeaderDate() {
  const now = new Date();
  document.getElementById('weekday').textContent = WEEKDAYS[now.getDay()];
  document.getElementById('datestr').textContent = `${now.getMonth() + 1}月${now.getDate()}日`;
}

function applyTheme() {
  const dark = S && (S.settings.theme_mode === 'Dark' || (S.settings.theme_mode === 'System' && S.settings.theme_is_dark));
  document.body.dataset.theme = dark ? 'dark' : 'light';
}

// MARK: - Tab 条

function renderTabs() {
  if (!S) return;
  const today = localDateStr(new Date());
  const counts = [
    S.todos.filter((it) => !it.done).length,
    null, null,
    S.shelf.length,
    S.vault.length,
    S.clips.length,
  ];
  $tabs.innerHTML = '';
  TABS.forEach((tab, i) => {
    const el = document.createElement('div');
    el.className = 'capsule' + (S.settings.tab === tab.id && !UI.settingsOpen ? ' selected' : '');
    el.innerHTML = `${Icon(tab.icon, 14)}<span>${tab.title}</span>` + (counts[i] !== null && counts[i] !== undefined ? `<span class="badge">${counts[i]}</span>` : '');
    el.addEventListener('click', () => {
      UI.settingsOpen = false;
      api.setTab(tab.id);
      S.settings.tab = tab.id;
      buildView();
      renderTabs();
    });
    $tabs.appendChild(el);
  });
}

// MARK: - 通用片段

function el(html) {
  const d = document.createElement('div');
  d.innerHTML = html;
  return d.firstElementChild;
}
function topStrip(countText, rightHtml) {
  const s = document.createElement('div');
  s.className = 'top-strip';
  s.innerHTML = `<span class="count-text">${countText}</span><span class="spacer"></span>${rightHtml || ''}`;
  return s;
}
function searchCapsule(placeholder, value, onInput, onClear) {
  const w = el(`<div class="search-capsule"><span class="s-icon">${Icon('search', 12)}</span><input class="text-input" placeholder="${placeholder}" /></div>`);
  const input = w.querySelector('input');
  input.value = value || '';
  const clear = document.createElement('span');
  clear.className = 'search-clear';
  clear.innerHTML = Icon('x', 12);
  clear.style.display = input.value ? 'flex' : 'none';
  clear.addEventListener('click', () => { input.value = ''; onInput(''); onClear && onClear(); });
  w.appendChild(clear);
  input.addEventListener('input', () => {
    clear.style.display = input.value ? 'flex' : 'none';
    onInput(input.value);
  });
  return w;
}

// MARK: - 视图构建

function buildView() {
  if (!S) return;
  $view.innerHTML = '';
  if (UI.settingsOpen) { buildSettings(); return; }
  switch (S.settings.tab) {
    case 'Todo': buildTodo(); break;
    case 'Notes': buildNotes(); break;
    case 'Downloads': buildDownloads(); break;
    case 'Shelf': buildShelf(); break;
    case 'Passwords': buildVault(); break;
    case 'Clipboard': buildClip(); break;
    default: buildTodo();
  }
}

function updateCurrent() {
  if (!S) return;
  if (UI.settingsOpen) { updateSettings(); return; }
  switch (S.settings.tab) {
    case 'Todo': updateTodo(); break;
    case 'Notes': updateNotes(); break;
    case 'Downloads': updateDownloads(); break;
    case 'Shelf': updateShelf(); break;
    case 'Passwords': updateVault(); break;
    case 'Clipboard': updateClip(); break;
  }
}

function updateAll() {
  renderTabs();
  updateCurrent();
  renderMusic();
}

// MARK: - 待办

let todoPresetsBox = null;
let todoFiltersBox = null;
let todoListBox = null;

function buildTodo() {
  $view.innerHTML = '';
  const card = el(`<div class="card todo-input-card">
    <button class="plus-btn grad" title="添加">${Icon('plus', 14)}</button>
    <input class="text-input todo-input" placeholder="添加待办，回车保存" />
    <div class="preset-row">
      <span class="preset-label">到期：</span>
      <span data-idx="1" class="preset-pill">今日</span>
      <span data-idx="2" class="preset-pill">明日</span>
      <span data-idx="3" class="preset-pill">一周</span>
      <span data-idx="5" class="preset-pill">长期</span>
      <span data-idx="4" class="preset-pill">历史</span>
    </div>
  </div>`);
  const input = card.querySelector('.todo-input');
  input.value = UI.todoDraft;
  input.addEventListener('input', () => { UI.todoDraft = input.value; });
  input.addEventListener('keydown', (e) => { if (e.key === 'Enter') submitTodo(); });
  card.querySelector('.plus-btn').addEventListener('click', submitTodo);
  card.querySelectorAll('.preset-pill').forEach((pill) => {
    pill.addEventListener('click', () => {
      const idx = Number(pill.dataset.idx);
      if (idx === 4) {
        UI.todoFilter = 4; // 历史:跳到历史分组
      } else {
        UI.todoPreset = idx;
      }
      updateTodo();
    });
  });
  $view.appendChild(card);
  todoPresetsBox = card;

  todoFiltersBox = el('<div class="todo-filters"></div>');
  $view.appendChild(todoFiltersBox);

  todoListBox = el('<div class="list"></div>');
  $view.appendChild(todoListBox);
  updateTodo();
}

function submitTodo() {
  const text = UI.todoDraft.trim();
  if (!text) return;
  api.addTodo(text, UI.todoPreset).then((r) => {
    UI.todoDraft = '';
    const input = $view.querySelector('.todo-input');
    if (input) input.value = '';
    if (r && r.bucket) UI.todoFilter = r.bucket; // 新增后跳到所在分组,立刻可见
    updateTodo();
  });
}

function updateTodo() {
  const today = localDateStr(new Date());
  if (todoPresetsBox) {
    todoPresetsBox.querySelectorAll('.preset-pill').forEach((pill) => {
      const idx = Number(pill.dataset.idx);
      pill.classList.toggle('on', idx !== 4 && UI.todoPreset === idx);
    });
  }
  if (todoFiltersBox) {
    todoFiltersBox.innerHTML = '';
    for (const [label, idx] of [['今日', 1], ['明日', 2], ['一周', 3], ['长期', 5], ['历史', 4]]) {
      const n = countFor(S.todos, idx, today);
      const pill = el(`<span class="filter-pill${UI.todoFilter === idx ? ' selected' : ''}">${label} ${n}</span>`);
      pill.addEventListener('click', () => { UI.todoFilter = idx; updateTodo(); });
      todoFiltersBox.appendChild(pill);
    }
  }
  if (todoListBox) {
    todoListBox.innerHTML = '';
    const rows = S.todos.filter((it) => bucketOf(it, today) === UI.todoFilter);
    if (rows.length === 0) {
      todoListBox.appendChild(el('<div class="empty-hint">暂无待办</div>'));
      return;
    }
    const now = new Date();
    for (const item of rows) {
      const row = el(`<div class="todo-row">
        <span class="check-circle${item.done ? ' done' : ''}">${item.done ? Icon('check', 11) : ''}</span>
        <span class="todo-title${item.done ? ' done' : ''}"></span>
        <span class="todo-meta"></span>
        <span class="row-del">${Icon('x', 13)}</span>
      </div>`);
      row.querySelector('.todo-title').textContent = item.title;
      const meta = row.querySelector('.todo-meta');
      if (item.done) {
        const undo = el('<span class="undo-link">标记为未完成</span>');
        undo.addEventListener('click', () => api.toggleTodo(item.id).then(updateCurrent));
        meta.appendChild(undo);
      } else if (item.due) {
        const due = new Date(item.due);
        if (due < now) {
          meta.appendChild(el('<span class="overdue">已逾期</span>'));
        } else if (due - now < 2 * 3600 * 1000) {
          const p = (n) => String(n).padStart(2, '0');
          meta.appendChild(el(`<span class="soon">${Icon('bell', 11)}${p(due.getHours())}:${p(due.getMinutes())}</span>`));
        }
      }
      row.querySelector('.check-circle').addEventListener('click', () => api.toggleTodo(item.id).then(updateCurrent));
      row.querySelector('.row-del').addEventListener('click', (e) => { e.stopPropagation(); api.removeTodo(item.id).then(updateCurrent); });
      row.addEventListener('contextmenu', async (ev) => { // 右键删除:先弹确认
        ev.preventDefault();
        if (await confirmDialog({ title: '删除待办', message: `确定删除「${item.title}」吗?` })) {
          api.removeTodo(item.id).then(updateCurrent);
        }
      });
      todoListBox.appendChild(row);
    }
  }
}

// MARK: - 笔记

let notesCountBox = null;
let notesFormBox = null;
let notesListBox = null;

function buildNotes() {
  $view.innerHTML = '';
  const strip = topStrip('', `<span class="grad-btn" id="notes-add">＋ 新建</span>`);
  notesCountBox = strip.querySelector('.count-text');
  strip.querySelector('#notes-add').addEventListener('click', () => {
    UI.notesAdding = !UI.notesAdding;
    renderNotesForm();
  });
  $view.appendChild(strip);
  notesFormBox = el('<div></div>');
  $view.appendChild(notesFormBox);
  notesListBox = el('<div class="list"></div>');
  $view.appendChild(notesListBox);
  renderNotesForm();
  updateNotes();
}

function renderNotesForm() {
  notesFormBox.innerHTML = '';
  if (!UI.notesAdding) return;
  const form = el(`<div class="card notes-form">
    <input class="text-input" placeholder="回车保存,首行为标题" />
    <span class="notes-save">${Icon('arrowUp', 20)}</span>
  </div>`);
  const input = form.querySelector('input');
  input.value = UI.notesDraft;
  input.addEventListener('input', () => { UI.notesDraft = input.value; });
  const submit = () => {
    const text = UI.notesDraft.trim();
    if (!text) return;
    api.addNote(text).then(() => {
      UI.notesDraft = '';
      UI.notesAdding = false;
      renderNotesForm();
      updateNotes();
      renderTabs();
    });
  };
  input.addEventListener('keydown', (e) => { if (e.key === 'Enter') submit(); });
  form.querySelector('.notes-save').addEventListener('click', submit);
  notesFormBox.appendChild(form);
}

function updateNotes() {
  if (notesCountBox) notesCountBox.textContent = `${S.notes.length} 张`;
  if (notesListBox) {
    notesListBox.innerHTML = '';
    if (S.notes.length === 0) {
      notesListBox.appendChild(el('<div class="empty-hint">还没有笔记</div>'));
      return;
    }
    for (const note of S.notes) {
      const lines = String(note.text || '').split('\n');
      const title = lines[0] || '';
      const body = lines.slice(1).join(' ');
      const card = el(`<div class="note-card">
        <div class="note-title"></div>
        ${body ? '<div class="note-body"></div>' : ''}
        <div class="note-time">${relTime(note.created_at)}</div>
        <span class="note-del">${Icon('x', 13)}</span>
      </div>`);
      card.querySelector('.note-title').textContent = title;
      if (body) card.querySelector('.note-body').textContent = body;
      card.querySelector('.note-del').addEventListener('click', (e) => {
        e.stopPropagation();
        api.removeNote(note.id).then(updateCurrent);
      });
      card.addEventListener('contextmenu', async (ev) => { // 右键删除:先弹确认
        ev.preventDefault();
        if (await confirmDialog({ title: '删除笔记', message: `确定删除「${title}」吗?` })) {
          api.removeNote(note.id).then(updateCurrent);
        }
      });
      notesListBox.appendChild(card);
    }
  }
}

// MARK: - 下载

let dlCountList = null;
let dlSearchBox = null;

function buildDownloads() {
  $view.innerHTML = '';
  const strip = topStrip('', `<div class="seg" id="dl-seg">
      <span class="seg-cell" data-v="0">最近</span>
      <span class="seg-cell" data-v="1">全部</span>
    </div>
    <button class="icon-btn" id="dl-folder" title="打开下载文件夹">${Icon('folder', 20)}</button>`);
  strip.querySelector('#dl-folder').addEventListener('click', () => api.openDownloadsFolder());
  strip.querySelectorAll('.seg-cell').forEach((cell) => {
    cell.addEventListener('click', () => {
      const all = cell.dataset.v === '1';
      UI.downloadsAll = all;
      api.setDownloadsRecent(!all);
      S.downloads_recent_only = !all;
      updateDownloads();
    });
  });
  $view.appendChild(strip);

  dlSearchBox = searchCapsule('搜索', UI.downloadsSearch, (v) => { UI.downloadsSearch = v; updateDownloads(); });
  $view.appendChild(dlSearchBox);

  dlCountList = el('<div class="list"></div>');
  $view.appendChild(dlCountList);
  updateDownloads();
}

function updateDownloads() {
  const seg = document.getElementById('dl-seg');
  if (seg) {
    seg.querySelectorAll('.seg-cell').forEach((c) => c.classList.toggle('selected', (c.dataset.v === '1') === UI.downloadsAll));
  }
  if (!dlCountList) return;
  dlCountList.innerHTML = '';
  if (S.downloads_read_error) {
    dlCountList.appendChild(el('<div class="empty-hint">无法读取“下载”文件夹</div>'));
    return;
  }
  const q = UI.downloadsSearch.toLowerCase();
  const shown = S.downloads.filter((f) => q === '' || f.name.toLowerCase().includes(q));
  if (shown.length === 0) {
    dlCountList.appendChild(el(`<div class="empty-hint">${S.downloads_recent_only ? '最近 3 天没有新下载' : '没有匹配的文件'}</div>`));
    return;
  }
  let lastGroup = null;
  for (const f of shown) {
    const group = downloadGroupOf(f.date);
    if (group !== lastGroup) {
      dlCountList.appendChild(el(`<div class="dl-group">${group}</div>`));
      lastGroup = group;
    }
    const row = el(`<div class="dl-row">
      <span class="dl-icon">${Icon('file', 24)}</span>
      <div style="flex:1;min-width:0">
        <div class="dl-name"></div>
        <div class="dl-meta${f.is_partial ? ' partial' : ''}"></div>
      </div>
      <div class="dl-actions">
        <span class="act" data-a="0" title="打开">${Icon('file', 16)}</span>
        <span class="act" data-a="1" title="在资源管理器中显示">${Icon('folder', 16)}</span>
        <span class="act" data-a="2" title="移到回收站">${Icon('trash', 16)}</span>
      </div>
    </div>`);
    row.querySelector('.dl-name').textContent = f.name;
    row.querySelector('.dl-meta').textContent = `${f.is_partial ? '下载中… ' : ''}${f.size < 0 ? '文件夹' : formatBytes(f.size)} · ${relTime(f.date)}`;
    row.querySelectorAll('.act').forEach((a) => {
      a.addEventListener('click', (e) => {
        e.stopPropagation();
        const act = a.dataset.a;
        if (act === '0') api.openPath(f.path);
        else if (act === '1') api.revealPath(f.path);
        else api.trashPath(f.path);
      });
    });
    row.addEventListener('dblclick', () => api.openPath(f.path));
    dlCountList.appendChild(row);
  }
}

// MARK: - 暂存

let shelfStrip = null;
let shelfContentBox = null;

function buildShelf() {
  $view.innerHTML = '';
  shelfStrip = topStrip('', `<div class="links">
      <span class="action-link" id="shelf-reveal">在资源管理器中显示</span>
      <span class="action-link" id="shelf-clear">清空</span>
    </div>`);
  shelfStrip.querySelector('#shelf-clear').addEventListener('click', () => api.clearShelf().then(updateCurrent));
  shelfStrip.querySelector('#shelf-reveal').addEventListener('click', () => api.revealAllShelf());
  $view.appendChild(shelfStrip);
  shelfContentBox = el('<div style="flex:none"></div>');
  $view.appendChild(shelfContentBox);
  updateShelf();
}

function updateShelf() {
  if (!S || !shelfContentBox) return;
  const has = S.shelf.length > 0;
  shelfStrip.querySelectorAll('.action-link').forEach((l) => l.classList.toggle('enabled', has));
  shelfStrip.querySelector('.count-text').textContent = `${S.shelf.length} 个文件`;
  shelfContentBox.innerHTML = '';
  if (!has) {
    const dz = el(`<div class="dropzone${UI.shelfDrop ? ' hover' : ''}">
      <div class="d1">把文件拖到这里暂存</div>
      <div class="d2">暂存只记录文件位置,不会复制文件</div>
    </div>`);
    shelfContentBox.appendChild(dz);
    return;
  }
  const grid = el('<div class="shelf-grid"></div>');
  for (const it of S.shelf) {
    const name = it.path.split(/[\\/]/).pop() || it.path;
    const cell = el(`<div class="shelf-cell">
      ${Icon('file', 36)}
      <div class="shelf-name"></div>
      <span class="shelf-del">${Icon('x', 13)}</span>
    </div>`);
    cell.querySelector('.shelf-name').textContent = name;
    cell.querySelector('.shelf-del').addEventListener('click', (e) => {
      e.stopPropagation();
      api.removeShelf(it.id).then(updateCurrent);
    });
    cell.addEventListener('click', () => api.openPath(it.path));
    grid.appendChild(cell);
  }
  shelfContentBox.appendChild(grid);
}

// MARK: - 密码

let vaultCountBox = null;
let vaultFormBox = null;
let vaultToastBox = null;
let vaultListBox = null;

function buildVault() {
  $view.innerHTML = '';
  const strip = topStrip('', `<span class="grad-btn" id="vault-add">＋ 添加</span>`);
  vaultCountBox = strip.querySelector('.count-text');
  strip.querySelector('#vault-add').addEventListener('click', () => {
    UI.vaultAdding = !UI.vaultAdding;
    renderVaultForm();
  });
  $view.appendChild(strip);
  vaultFormBox = el('<div></div>');
  $view.appendChild(vaultFormBox);
  vaultToastBox = el('<div style="font-size:11px;margin-bottom:4px;flex:none"></div>');
  $view.appendChild(vaultToastBox);
  vaultListBox = el('<div class="list"></div>');
  $view.appendChild(vaultListBox);
  renderVaultForm();
  updateVault();
}

function renderVaultForm() {
  vaultFormBox.innerHTML = '';
  if (!UI.vaultAdding) return;
  const form = el(`<div class="card vault-form">
    <div class="vault-field"><input class="text-input" data-f="site" placeholder="网站 / 用途" /></div>
    <div class="vault-field"><input class="text-input" data-f="account" placeholder="手机号 / 邮箱 / 用户名" /></div>
    <div class="vault-field"><input class="text-input" data-f="phone" placeholder="绑定的手机号(可选)" /></div>
    <div class="vault-field"><input class="text-input" data-f="password" type="password" placeholder="密码(留空 = 稍后补填)" /><span class="wand" title="生成强密码">${Icon('wand', 18)}</span></div>
    <div class="vault-btns">
      <span class="grad-btn square" id="vault-save">保存</span>
      <span class="action-link enabled" id="vault-cancel">取消</span>
    </div>
  </div>`);
  const inputs = {};
  form.querySelectorAll('input').forEach((inp) => {
    inputs[inp.dataset.f] = inp;
    inp.value = UI[`vault${inp.dataset.f[0].toUpperCase()}${inp.dataset.f.slice(1)}`] || '';
    inp.addEventListener('input', () => {
      const key = `vault${inp.dataset.f[0].toUpperCase()}${inp.dataset.f.slice(1)}`;
      UI[key] = inp.value;
    });
  });
  form.querySelector('.wand').addEventListener('click', () => {
    const pw = generatePassword(20, true);
    UI.vaultPassword = pw;
    inputs.password.value = pw;
  });
  form.querySelector('#vault-cancel').addEventListener('click', () => {
    UI.vaultAdding = false;
    UI.vaultSite = UI.vaultAccount = UI.vaultPhone = UI.vaultPassword = '';
    renderVaultForm();
  });
  form.querySelector('#vault-save').addEventListener('click', () => {
    const site = UI.vaultSite.trim();
    const account = UI.vaultAccount.trim();
    if (!site || !account) return;
    api.addVault({ site, account, phone: UI.vaultPhone.trim(), password: UI.vaultPassword }).then((r) => {
      if (r && r.ok) {
        UI.vaultAdding = false;
        UI.vaultSite = UI.vaultAccount = UI.vaultPhone = UI.vaultPassword = '';
        renderVaultForm();
        updateVault();
        renderTabs();
      } else {
        showToast('vault', (r && r.error) || '保存失败', true);
      }
    });
  });
  vaultFormBox.appendChild(form);
}

function updateVault() {
  if (vaultCountBox) vaultCountBox.textContent = `共 ${S.vault.length} 条`;
  if (vaultToastBox) {
    const t = UI.vaultToast;
    vaultToastBox.textContent = toastActive(t) ? t.msg : '';
    vaultToastBox.className = `toast vault ${t && t.error ? 'error' : ''}`.trim();
    vaultToastBox.style.fontSize = '11px';
    vaultToastBox.style.marginBottom = '4px';
    if (toastActive(t)) vaultToastBox.style.color = t.error ? 'var(--danger)' : 'var(--green)';
    else vaultToastBox.style.color = '';
    void vaultToastBox;
  }
  // 揭示超时
  if (UI.vaultReveal && Date.now() > UI.vaultReveal.until) UI.vaultReveal = null;

  if (!vaultListBox) return;
  // 保留正在编辑密码的行(内联输入不重建,防丢焦点)
  const editingEl = vaultListBox.querySelector('[data-editing="1"]');
  vaultListBox.innerHTML = '';
  if (S.vault.length === 0) {
    vaultListBox.appendChild(el('<div class="empty-hint">暂无保存的密码</div>'));
    return;
  }
  for (const e of S.vault) {
    if (editingEl && editingEl.dataset.id === e.id) {
      vaultListBox.appendChild(editingEl);
      continue;
    }
    const revealing = UI.vaultReveal && UI.vaultReveal.id === e.id;
    const row = el(`<div class="vault-row">
      <span class="vault-keyblock">${Icon('lock', 20)}</span>
      <div class="vault-main">
        <div class="vault-site"></div>
        <div class="vault-account${revealing ? ' revealed' : ''}"></div>
      </div>
      <div class="vault-right">
        <div class="vault-acts">
          <span class="act" data-a="del" title="删除">${Icon('trash', 16)}</span>
          <span class="act" data-a="edit" title="修改密码">${Icon('pencil', 16)}</span>
        </div>
        ${e.has_password ? '' : '<span class="no-pw-label">未保存密码</span>'}
        <span class="act vault-eye-btn">${Icon('eye', 16)}</span>
      </div>
      ${UI.vaultEditFor === e.id ? `<div class="vault-edit"><input class="text-input" type="password" placeholder="重新输入密码" /><span class="grad-btn">保存</span></div>` : ''}
    </div>`);
    row.dataset.id = e.id;
    row.querySelector('.vault-site').textContent = e.site;
    const acc = row.querySelector('.vault-account');
    acc.textContent = revealing ? (UI.vaultReveal.text || e.account) : e.account;
    row.querySelector('.vault-eye-btn').addEventListener('click', () => {
      if (revealing) {
        UI.vaultReveal = null;
        updateVault();
      } else {
        api.revealVault(e.id).then((pw) => {
          if (pw) {
            UI.vaultReveal = { id: e.id, text: pw, until: Date.now() + 12000 }; // 12s 后自动隐藏
            updateVault();
          } else {
            showToast('vault', '未找到保存的密码');
          }
        });
      }
    });
    row.querySelector('[data-a="del"]').addEventListener('click', () => api.removeVault(e.id).then(updateCurrent));
    row.addEventListener('contextmenu', async (ev) => { // 右键删除:先弹确认
      ev.preventDefault();
      if (await confirmDialog({ title: '删除密码', message: `确定删除「${e.site}」的密码记录吗?` })) {
        api.removeVault(e.id).then(updateCurrent);
      }
    });
    row.querySelector('[data-a="edit"]').addEventListener('click', () => {
      UI.vaultEditFor = e.id;
      UI.vaultEditPw = '';
      updateVault();
    });
    if (UI.vaultEditFor === e.id) {
      row.dataset.editing = '1';
      const inp = row.querySelector('.vault-edit input');
      inp.value = UI.vaultEditPw;
      inp.addEventListener('input', () => { UI.vaultEditPw = inp.value; });
      const save = () => {
        if (!UI.vaultEditPw) return;
        api.updateVaultPassword(e.id, UI.vaultEditPw).then(() => {
          UI.vaultEditFor = null;
          UI.vaultEditPw = '';
          updateVault();
        });
      };
      inp.addEventListener('keydown', (ev) => { if (ev.key === 'Enter') save(); });
      row.querySelector('.vault-edit .grad-btn').addEventListener('click', save);
    }
    vaultListBox.appendChild(row);
  }
}

// MARK: - 剪贴板

let clipSearchBox = null;
let clipCountBox = null;
let clipToastSpan = null;
let clipListBox = null;

function buildClip() {
  $view.innerHTML = '';
  clipSearchBox = searchCapsule('搜索…', UI.clipSearch, (v) => { UI.clipSearch = v; UI.clipSelected = null; updateClip(); });
  $view.appendChild(clipSearchBox);
  const strip = topStrip('', `<div class="links">
      <span class="action-link" id="clip-clear-all">全部清除</span>
      <span class="action-link" id="clip-clear">清除</span>
    </div>`);
  clipCountBox = strip.querySelector('.count-text');
  clipToastSpan = el('<span class="toast clip"></span>');
  strip.insertBefore(clipToastSpan, strip.querySelector('.spacer'));
  strip.querySelector('#clip-clear').addEventListener('click', () => api.clearClipsUnpinned().then(updateCurrent));
  strip.querySelector('#clip-clear-all').addEventListener('click', () => {
    UI.clipSearch = '';
    UI.clipSelected = null;
    const input = clipSearchBox.querySelector('input');
    if (input) input.value = '';
    api.clearClipsAll().then(updateCurrent);
  });
  $view.appendChild(strip);
  clipListBox = el('<div class="list"></div>');
  $view.appendChild(clipListBox);
  updateClip();
}

function updateClip() {
  if (!clipListBox || !S) return;
  const rows = visibleClips(S.clips, UI.clipSearch);
  if (clipCountBox) clipCountBox.textContent = `${S.clips.length} 条 · 纯本地保存`;
  if (clipToastSpan) {
    clipToastSpan.textContent = toastActive(UI.clipToast) ? UI.clipToast.msg : '';
  }
  if (UI.clipSelected !== null && rows.length === 0) UI.clipSelected = null;
  if (UI.clipSelected !== null) UI.clipSelected = Math.min(UI.clipSelected, rows.length - 1);

  clipListBox.innerHTML = '';
  if (rows.length === 0) {
    if (UI.clipSearch === '') {
      clipListBox.appendChild(el(`<div class="clip-empty">
        ${Icon('clipboard', 24)}
        <div class="t1">剪贴板还是空的</div>
        <div class="t2">在任何应用里复制文字,都会自动记录到这里</div>
      </div>`));
    } else {
      clipListBox.appendChild(el(`<div class="clip-empty">
        ${Icon('search', 24)}
        <div class="t1" style="margin-top:8px">没有匹配的复制记录</div>
      </div>`));
    }
    return;
  }
  const pinnedCount = rows.filter((e) => e.pinned === true).length;
  rows.forEach((e, i) => {
    if (i === pinnedCount && pinnedCount > 0 && pinnedCount < rows.length) {
      clipListBox.appendChild(el('<div class="clip-divider"></div>'));
    }
    const selected = UI.clipSelected === i;
    const row = el(`<div class="clip-row${selected ? ' selected' : ''}">
      ${e.image_path
        ? `${e.image_data ? `<img class="clip-thumb" src="${e.image_data}" />` : `<span class="clip-thumb" style="display:flex;align-items:center;justify-content:center;color:var(--text3)">${Icon('file', 14)}</span>`}<span class="clip-img-label">图片</span>`
        : `<span class="clip-src" style="background:rgb(${sourceColor(e.source_name).join(',')})">${(e.source_name || '?').charAt(0).toUpperCase()}</span><span class="clip-text"></span>`}
      ${e.pinned === true ? `<span class="clip-pin-static">${Icon('pinSmall', 12)}</span>` : ''}
      <div class="clip-acts">
        <span class="act" data-a="pin" title="${e.pinned === true ? '取消固定' : '固定'}">${Icon('pinSmall', 14)}</span>
        <span class="act" data-a="del" title="删除">${Icon('trash', 14)}</span>
      </div>
    </div>`);
    if (!e.image_path) row.querySelector('.clip-text').textContent = String(e.text || '').replace(/\n/g, ' ');
    row.addEventListener('click', () => {
      api.copyClip(e.id).then((r) => {
        UI.clipSelected = null;
        if (r && r.ok) {
          showToast('clip', r.autoPaste ? '已复制并粘贴' : '已复制');
          if (r.autoPaste) api.hidePanel();
        }
      });
    });
    row.querySelector('[data-a="pin"]').addEventListener('click', (ev) => { ev.stopPropagation(); api.toggleClipPin(e.id).then(updateCurrent); });
    row.querySelector('[data-a="del"]').addEventListener('click', (ev) => { ev.stopPropagation(); api.removeClip(e.id).then(updateCurrent); });
    clipListBox.appendChild(row);
  });
}

// MARK: - 设置

let settingsBoxes = {};

function buildSettings() {
  $view.innerHTML = '';
  const strip = topStrip('设置', `<span class="action-link enabled" id="settings-back">返回</span>`);
  strip.querySelector('#settings-back').addEventListener('click', () => {
    UI.settingsOpen = false;
    buildView();
    renderTabs();
  });
  $view.appendChild(strip);

  const scroll = el('<div class="list"></div>');

  // 主题
  const themeCard = el(`<div class="card settings-card">
    <div class="row-line" style="height:auto">
      <span class="label" style="font-size:13px">主题</span>
      <span class="spacer"></span>
      <div class="seg" id="theme-seg">
        <span class="seg-cell" data-v="System">跟随系统</span>
        <span class="seg-cell" data-v="Light">浅色</span>
        <span class="seg-cell" data-v="Dark">深色</span>
      </div>
    </div>
    <div class="settings-hint">跟随系统:随 Windows 浅色/深色模式自动切换</div>
  </div>`);
  themeCard.querySelectorAll('.seg-cell').forEach((c) => {
    c.addEventListener('click', () => api.setThemeMode(c.dataset.v).then(() => { S.settings.theme_mode = c.dataset.v; updateSettings(); }));
  });
  scroll.appendChild(themeCard);

  // 行为开关
  const togglesCard = el(`<div class="card settings-card" id="toggles-card"></div>`);
  const toggleDefs = [
    ['pinned', '常驻模式(失焦不收起)'],
    ['auto_paste', '选中剪贴板后自动粘贴'],
    ['show_music', '显示底部"正在播放"卡片'],
    ['launch_at_login', '开机自启'],
  ];
  for (const [key, label] of toggleDefs) {
    const line = el(`<div class="row-line"><span class="label">${label}</span><span class="switch"><span class="knob"></span></span></div>`);
    line.querySelector('.switch').addEventListener('click', () => {
      const next = !S.settings[key];
      if (key === 'launch_at_login') {
        api.setLaunchAtLogin(next).then((ok) => {
          if (ok) { S.settings[key] = next; }
          else showToast('vault', '写入注册表失败', true);
          updateSettings();
        });
      } else {
        S.settings[key] = next;
        if (key === 'pinned') api.setPinned(next);
        if (key === 'auto_paste') api.setAutoPaste(next);
        if (key === 'show_music') { api.setShowMusic(next); renderMusic(); }
        updateSettings();
      }
    });
    togglesCard.appendChild(line);
  }
  scroll.appendChild(togglesCard);

  // 快捷键 + 恢复默认
  const hotkeyCard = el(`<div class="card settings-card">
    <div class="row-line" style="height:26px">
      <span class="label" style="font-size:13px">显示/隐藏快捷键</span>
      <span class="spacer"></span>
      <span class="hotkey-display"></span>
    </div>
    <span class="reset-link">恢复默认大小与位置</span>
  </div>`);
  hotkeyCard.querySelector('.reset-link').addEventListener('click', () => api.resetPlacement());
  scroll.appendChild(hotkeyCard);

  // 说明
  const infoCard = el(`<div class="card settings-card">
    <div class="info-line">· 剪贴板历史纯本地保存,图片条目落盘为 PNG</div>
    <div class="info-line">· 密码经 DPAPI 加密,仅本机可解密</div>
    <div class="info-line">· 拖拽文件到「暂存」页即可快速收纳</div>
  </div>`);
  scroll.appendChild(infoCard);

  $view.appendChild(scroll);
  settingsBoxes = { themeSeg: themeCard.querySelector('#theme-seg'), togglesCard, hotkeyDisplay: hotkeyCard.querySelector('.hotkey-display') };
  updateSettings();
}

function updateSettings() {
  if (!settingsBoxes.themeSeg || !S) return;
  settingsBoxes.themeSeg.querySelectorAll('.seg-cell').forEach((c) => c.classList.toggle('selected', c.dataset.v === S.settings.theme_mode));
  settingsBoxes.togglesCard.querySelectorAll('.row-line').forEach((line) => {
    const label = line.querySelector('.label').textContent;
    const key = { '常驻模式(失焦不收起)': 'pinned', '选中剪贴板后自动粘贴': 'auto_paste', '显示底部"正在播放"卡片': 'show_music', '开机自启': 'launch_at_login' }[label];
    if (key) line.querySelector('.switch').classList.toggle('on', !!S.settings[key]);
  });
  const hk = S.settings.hotkey || { ctrl: true, alt: true, shift: false, win: false, code: 'KeyS' };
  const parts = [];
  if (hk.ctrl) parts.push('Ctrl');
  if (hk.alt) parts.push('Alt');
  if (hk.shift) parts.push('Shift');
  if (hk.win) parts.push('Win');
  let keyName = hk.code;
  if (keyName === 'Space') keyName = '空格';
  else if (keyName.startsWith('Key')) keyName = keyName.slice(3);
  else if (keyName.startsWith('Digit')) keyName = keyName.slice(5);
  parts.push(keyName);
  settingsBoxes.hotkeyDisplay.textContent = parts.join('+');
}

// MARK: - 音乐卡

function renderMusic() {
  if (!S || !S.settings.show_music || !music || (!music.title && !music.artist)) {
    $music.innerHTML = '';
    $music.style.display = 'none';
    return;
  }
  $music.style.display = '';
  const pos = displayPosition(music, Date.now() / 1000);
  const dur = music.duration_secs || 0;
  const frac = dur > 0 ? Math.min(1, Math.max(0, pos / dur)) : 0;
  $music.innerHTML = `
    <div class="music-card">
      ${music.art_b64
        ? `<img class="music-art" src="data:image/png;base64,${music.art_b64}" />`
        : `<div class="music-art ph grad">${Icon('musicnote', 26)}</div>`}
      <div class="music-title"></div>
      <div class="music-artist"></div>
      <div class="music-bar"><div class="fill" style="width:${(frac * 100).toFixed(1)}%"></div></div>
      <div class="music-time cur">${mmss(pos)}</div>
      <div class="music-time dur">${mmss(dur)}</div>
      <div class="music-transport">
        <span class="tbtn" data-k="prev">${Icon('prev', 16)}</span>
        <span class="tbtn" data-k="playpause">${Icon(music.playing ? 'pause' : 'play', 18)}</span>
        <span class="tbtn" data-k="next">${Icon('next', 16)}</span>
      </div>
    </div>`;
  $music.querySelector('.music-title').textContent = music.title;
  $music.querySelector('.music-artist').textContent = music.artist;
  $music.querySelectorAll('.tbtn').forEach((b) => {
    b.addEventListener('click', () => api.musicControl(b.dataset.k));
  });
}

// MARK: - 拖放(暂存;仅暂存页接受)

window.addEventListener('dragover', (e) => {
  e.preventDefault();
  if (S && S.settings.tab === 'Shelf' && !UI.settingsOpen) {
    if (!UI.shelfDrop) {
      UI.shelfDrop = true;
      const dz = $view.querySelector('.dropzone');
      if (dz) dz.classList.add('hover');
    }
  }
});
window.addEventListener('dragleave', (e) => {
  if (e.relatedTarget === null || e.relatedTarget === document.documentElement) {
    UI.shelfDrop = false;
    const dz = $view.querySelector('.dropzone');
    if (dz) dz.classList.remove('hover');
  }
});
window.addEventListener('drop', (e) => {
  e.preventDefault();
  UI.shelfDrop = false;
  const dz = $view.querySelector('.dropzone');
  if (dz) dz.classList.remove('hover');
  if (!S || S.settings.tab !== 'Shelf' || UI.settingsOpen) return;
  const paths = [];
  for (const f of e.dataTransfer.files) {
    try {
      const p = api.pathForFile(f);
      if (p) paths.push(p);
    } catch { /* 忽略 */ }
  }
  if (paths.length) api.addShelfMany(paths).then(updateCurrent); // 多文件保持拖入顺序
});

// MARK: - 键盘导航(剪贴板页:↑↓/↩/Esc,Maccy 同)

document.addEventListener('keydown', (e) => {
  if (!S || UI.settingsOpen || S.settings.tab !== 'Clipboard') return;
  const typing = e.target && e.target.tagName === 'INPUT';
  const rows = visibleClips(S.clips, UI.clipSearch);
  if (rows.length === 0) return;
  if (e.key === 'ArrowDown') {
    UI.clipSelected = UI.clipSelected === null ? 0 : Math.min(UI.clipSelected + 1, rows.length - 1);
    updateClip();
    e.preventDefault();
  } else if (e.key === 'ArrowUp') {
    UI.clipSelected = UI.clipSelected === null ? rows.length - 1 : Math.max(UI.clipSelected - 1, 0);
    updateClip();
    e.preventDefault();
  } else if (e.key === 'Escape') {
    if (UI.clipSelected !== null) { UI.clipSelected = null; updateClip(); }
  } else if (e.key === 'Enter' && (!typing || e.target.closest('.search-capsule'))) {
    const idx = UI.clipSelected === null ? 0 : UI.clipSelected;
    const entry = rows[Math.min(idx, rows.length - 1)];
    if (entry) {
      api.copyClip(entry.id).then((r) => {
        UI.clipSelected = null;
        if (r && r.ok) {
          showToast('clip', r.autoPaste ? '已复制并粘贴' : '已复制');
          if (r.autoPaste) api.hidePanel();
        }
      });
    }
  }
});

// MARK: - 启动

function init() {
  document.getElementById('btn-hide').innerHTML = Icon('chevron', 18);
  document.getElementById('btn-pin').innerHTML = Icon('pin', 18);
  document.getElementById('btn-gear').innerHTML = Icon('gear', 18);
  document.getElementById('btn-hide').addEventListener('click', () => api.hidePanel());
  document.getElementById('btn-pin').addEventListener('click', () => {
    S.settings.pinned = !S.settings.pinned;
    api.setPinned(S.settings.pinned);
    updateHeaderPin();
  });
  document.getElementById('btn-gear').addEventListener('click', () => {
    UI.settingsOpen = !UI.settingsOpen;
    buildView();
    renderTabs();
  });
  renderHeaderDate();
  setInterval(renderHeaderDate, 30000);

  api.getState().then((s) => {
    S = s;
    applyTheme();
    updateHeaderPin();
    renderTabs();
    buildView();
    renderMusic();
  });
  api.onState((s) => { S = s; applyTheme(); updateHeaderPin(); updateAll(); });
  api.onMusic((m) => { music = m; renderMusic(); });
  api.onUi((u) => {
    if (u && u.settings_open) {
      UI.settingsOpen = true;
      buildView();
      renderTabs();
    }
  });

  // 音乐进度插值 / toast 过期 / 揭示超时
  setInterval(() => {
    renderMusic();
    if (S) updateCurrent();
  }, 500);
}

function updateHeaderPin() {
  const btn = document.getElementById('btn-pin');
  if (btn && S) btn.classList.toggle('active', !!S.settings.pinned);
}

init();
