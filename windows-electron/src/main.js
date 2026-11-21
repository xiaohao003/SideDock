// main.js — SideDock for Windows(Electron 版)主进程
// 对应 Rust 版 app.rs:无边框透明面板 + 托盘 + 全局热键 + 剪贴板轮询 + 失焦收起
// 数据与 Rust 版同目录同格式(%APPDATA%\SideDock),升级无缝沿用旧数据
'use strict';

const { app, BrowserWindow, Tray, Menu, globalShortcut, clipboard, nativeTheme, nativeImage, ipcMain, screen, shell, safeStorage } = require('electron');
const fs = require('fs');
const path = require('path');
const stores = require('./stores');
const logic = require('./logic');
const { MusicController, displayPosition } = require('./music');
const keys = require('./keys');

// MARK: - 常量 / 全局状态

const isWin = process.platform === 'win32';
const APP_TITLE = 'SideDock';

let settings = stores.loadSettings();
let todos = [];
let notes = [];
let shelf = [];
let vault = [];
let clips = [];
let downloads = []; // { path, name, size, date(ISO), is_partial }
let downloadsReadError = false;
let downloadsRecentOnly = true;

let win = null;
let tray = null;
let quitting = false;
let userMoved = false; // 用户拖过窗口(settings.pos 为准)
let lastAutoHide = 0;

const music = new MusicController();
const imageCache = new Map(); // clip 图片路径 → dataURL

let lastClipText = null;
let lastClipImageKey = '';
let lastDownloadsRefresh = 0;
let pushTimer = null;

// MARK: - 日志(诊断:%APPDATA%\SideDock\run.log,与 Rust 版同文件)

function log(msg) {
  try {
    const line = `${ts()} ${msg}\n`;
    fs.appendFileSync(stores.dataFile('run.log'), line);
  } catch { /* 忽略 */ }
}

function ts() {
  const d = new Date();
  const p = (n, w = 2) => String(n).padStart(w, '0');
  return `${p(d.getMonth() + 1)}-${p(d.getDate())} ${p(d.getHours())}:${p(d.getMinutes())}:${p(d.getSeconds())}.${p(d.getMilliseconds(), 3)}`;
}

// MARK: - 主题

function systemIsDark() {
  return nativeTheme.shouldUseDarkColors;
}

function isDark() {
  return settings.theme_mode === 'Dark' || (settings.theme_mode === 'System' && settings.theme_is_dark);
}

function applyTheme() {
  settings.theme_is_dark = settings.theme_mode === 'System'
    ? systemIsDark()
    : settings.theme_mode === 'Dark';
  if (win && !win.isDestroyed()) {
    if (!isOpaqueForced()) {
      win.setBackgroundColor('#00000000');
    } else {
      win.setBackgroundColor(isDark() ? '#1C1C1F' : '#F7F7F8');
    }
  }
}

// MARK: - 窗口几何(DIP 点坐标,与 Rust v1.1.6+ egui 坐标系一致)

function isOpaqueForced() {
  return process.env.SIDEDOCK_OPAQUE === '1';
}

function isTransparent() {
  return !isOpaqueForced();
}

/** 虚拟桌面包围盒(所有显示器;Electron bounds 即 DIP,无需换算) */
function virtualDesktop() {
  const displays = screen.getAllDisplays();
  let x = Infinity, y = Infinity, r = -Infinity, b = -Infinity;
  for (const d of displays) {
    x = Math.min(x, d.bounds.x);
    y = Math.min(y, d.bounds.y);
    r = Math.max(r, d.bounds.x + d.bounds.width);
    b = Math.max(b, d.bounds.y + d.bounds.height);
  }
  if (!Number.isFinite(x) || r <= x || b <= y) return null;
  return [x, y, r - x, b - y];
}

/** 停靠:光标所在屏(缺省主屏)工作区右缘垂直居中 */
function dockPoint(w, h) {
  const cursor = screen.getCursorScreenPoint();
  const display = screen.getDisplayNearestPoint(cursor) || screen.getPrimaryDisplay();
  const wa = display.workArea;
  return [wa.x + wa.width - w - 8, wa.y + Math.round((wa.height - h) / 2)];
}

/** 恢复位置:用户移动过 → 存储位置(越界夹回);否则停靠右缘(对应 Rust restore_window_placement) */
function restorePlacement() {
  if (!win) return;
  const b = win.getBounds();
  const [dw, dh] = dockPoint(b.width, b.height);
  let target = [dw, dh];
  if (settings.pos) {
    const vd = virtualDesktop();
    if (!vd) {
      target = settings.pos; // 判断不了就越界放行,保持旧行为
    } else {
      const clamped = logic.clampIntoBounds(settings.pos[0], settings.pos[1], b.width, b.height, vd[0], vd[1], vd[2], vd[3]);
      if (clamped) {
        if (Math.abs(clamped[0] - settings.pos[0]) > 0.5 || Math.abs(clamped[1] - settings.pos[1]) > 0.5) {
          log(`restore: saved pos (${settings.pos[0]},${settings.pos[1]}) 越界 → 夹回 (${clamped[0]},${clamped[1]})`);
        }
        target = clamped;
      } else {
        log(`restore: saved pos (${settings.pos[0]},${settings.pos[1]}) 无效 → 停靠右缘`);
      }
    }
  }
  win.setPosition(Math.round(target[0]), Math.round(target[1]));
}

function persistPos() {
  if (!win || win.isDestroyed()) return;
  const b = win.getBounds();
  settings.pos = [b.x, b.y];
  userMoved = true;
  stores.saveSettings(settings);
}

let posSaveTimer = null;
function onWindowMoved() {
  if (posSaveTimer) clearTimeout(posSaveTimer);
  posSaveTimer = setTimeout(persistPos, 400);
}

// MARK: - 显示 / 隐藏

function hidePanel() {
  if (win && !win.isDestroyed() && win.isVisible()) win.hide();
}

function showPanel(openSettings = false) {
  if (!win || win.isDestroyed()) return;
  restorePlacement();
  win.show();
  win.focus();
  if (openSettings) {
    win.webContents.send('ui', { settings_open: true });
  }
}

function toggleVisible() {
  const visible = win && !win.isDestroyed() && win.isVisible() && win.isFocused();
  if (visible && Date.now() - lastAutoHide > 600) {
    hidePanel();
  } else {
    showPanel();
  }
}

// MARK: - 托盘 / 热键(仅 Windows;与 Rust 版同菜单)

function setupTray() {
  if (!isWin) return;
  try {
    const iconPath = path.join(process.resourcesPath || __dirname, 'icon.ico');
    const icon = fs.existsSync(iconPath) ? nativeImage.createFromPath(iconPath) : null;
    tray = icon ? new Tray(icon) : new Tray(nativeImage.createEmpty());
    tray.setToolTip(APP_TITLE);
    const menu = Menu.buildFromTemplate([
      { label: '显示面板', click: () => showPanel() },
      { label: '设置', click: () => showPanel(true) },
      { type: 'separator' },
      { label: '退出', click: () => app.quit() },
    ]);
    tray.setContextMenu(menu);
    tray.on('click', () => toggleVisible());
  } catch (e) {
    log(`tray setup failed: ${e.message}`);
    tray = null;
  }
}

function setupHotkey() {
  if (!isWin) return;
  const accelerator = logic.hotkeyAccelerator(settings.hotkey);
  try {
    const ok = globalShortcut.register(accelerator, () => toggleVisible());
    log(`hotkey ${accelerator} registered=${ok}`);
  } catch (e) {
    log(`hotkey register failed: ${e.message}`);
  }
}

// MARK: - 剪贴板轮询(600ms;文本优先,图片落盘 PNG;对应 Rust ClipboardStore.poll)

function pollClipboard() {
  try {
    const formats = clipboard.availableFormats();
    const text = clipboard.readText();
    if (text && text.trim() !== '') {
      if (text !== lastClipText) {
        lastClipText = text;
        const clipped = [...text.trim()].slice(0, 4000).join('');
        const entry = {
          id: crypto.randomUUID(),
          text: clipped,
          copied_at: new Date().toISOString(),
          pinned: null,
          pinned_at: null,
          source_name: null,
          image_path: null,
        };
        stores.recordClip(clips, entry);
        attachSourceName(entry);
      }
      return;
    }
    // 无文本 → 尝试图片(尺寸变化作为变化判据)
    if (formats.some((f) => f.startsWith('image/'))) {
      const img = clipboard.readImage();
      if (!img.isEmpty()) {
        const size = img.getSize();
        const key = `${size.width}x${size.height}`;
        if (key !== lastClipImageKey) {
          const png = img.toPNG();
          lastClipImageKey = key;
          const imagePath = stores.saveClipImagePng(png);
          const entry = {
            id: crypto.randomUUID(),
            text: '图片',
            copied_at: new Date().toISOString(),
            pinned: null,
            pinned_at: null,
            source_name: null,
            image_path: imagePath,
          };
          stores.recordClip(clips, entry);
          attachSourceName(entry);
        }
      }
    }
  } catch { /* 剪贴板被占用等,忽略本轮 */ }
}

/** 异步补来源应用名(对应 Rust foreground_app;PowerShell 一次性进程,延迟可接受) */
function attachSourceName(entry) {
  keys.fetchForegroundApp((name) => {
    if (!name) return;
    const target = clips.find((e) => e.id === entry.id);
    if (target && !target.source_name) {
      target.source_name = name;
      stores.saveClips(clips);
      schedulePush();
    }
  });
}

/** 回写系统剪贴板(选中剪贴板历史;对应 Rust copy_back) */
function copyClipBack(entry) {
  let ok = false;
  try {
    if (entry.image_path && fs.existsSync(entry.image_path)) {
      const img = nativeImage.createFromPath(entry.image_path);
      if (!img.isEmpty()) {
        clipboard.writeImage(img);
        ok = true;
      }
    } else {
      clipboard.writeText(entry.text);
      ok = true;
    }
  } catch { ok = false; }
  if (ok) {
    // 序号对齐避免自记:让下一轮轮询看到"无变化"
    lastClipText = clipboard.readText();
    const img = clipboard.readImage();
    if (!img.isEmpty()) {
      const size = img.getSize();
      lastClipImageKey = `${size.width}x${size.height}`;
    }
  }
  return ok;
}

// MARK: - 下载目录监控(2s;对应 Rust DownloadsStore.refresh)

function refreshDownloads() {
  const dir = app.getPath('downloads');
  let entries;
  try {
    entries = fs.readdirSync(dir, { withFileTypes: true });
    downloadsReadError = false;
  } catch {
    downloadsReadError = true;
    return;
  }
  const now = new Date();
  const cutoff = now.getTime() - 3 * 24 * 3600 * 1000;
  const result = [];
  for (const e of entries) {
    if (e.name.startsWith('.')) continue;
    let stat;
    try { stat = fs.statSync(path.join(dir, e.name)); } catch { continue; }
    const date = stat.mtime;
    if (downloadsRecentOnly && date.getTime() <= cutoff) continue;
    const lower = e.name.toLowerCase();
    const partial = lower.endsWith('.crdownload') || lower.endsWith('.download') || lower.endsWith('.part');
    result.push({
      path: path.join(dir, e.name),
      name: e.name,
      size: stat.isDirectory() ? -1 : stat.size,
      date: date.toISOString(),
      is_partial: partial,
    });
  }
  result.sort((a, b) => new Date(b.date) - new Date(a.date));
  downloads = result.slice(0, 60);
}

// MARK: - 状态推送(150ms 去抖)

function snapshot() {
  return {
    settings,
    todos,
    notes,
    shelf,
    vault: vault.map((e) => ({
      id: e.id, site: e.site, account: e.account, phone: e.phone, note: e.note,
      created_at: e.created_at, has_password: !!e.pw,
    })),
    clips: clips.map((e) => ({
      id: e.id, text: e.text, copied_at: e.copied_at, pinned: e.pinned,
      source_name: e.source_name, image_path: e.image_path,
      image_data: e.image_path ? clipImageData(e.image_path) : null,
    })),
    downloads,
    downloads_read_error: downloadsReadError,
    downloads_recent_only: downloadsRecentOnly,
  };
}

function clipImageData(p) {
  if (imageCache.has(p)) return imageCache.get(p);
  try {
    const b64 = fs.readFileSync(p).toString('base64');
    const url = `data:image/png;base64,${b64}`;
    imageCache.set(p, url);
    return url;
  } catch {
    return null;
  }
}

function schedulePush() {
  if (pushTimer) return;
  pushTimer = setTimeout(() => {
    pushTimer = null;
    if (win && !win.isDestroyed()) {
      win.webContents.send('state', snapshot());
    }
  }, 150);
}

// MARK: - 设置动作

function setThemeMode(mode) {
  settings.theme_mode = mode;
  applyTheme();
  stores.saveSettings(settings);
  schedulePush();
}

function setLaunchAtLogin(enable) {
  try {
    app.setLoginItemSettings({ openAtLogin: enable });
    return app.getLoginItemSettings().openAtLogin === enable;
  } catch {
    return false;
  }
}

// MARK: - 自动粘贴(先收起面板,再向前台应用模拟 Ctrl+V;对应 Rust one_shots)

function requestAutoPaste() {
  hidePanel();
  setTimeout(() => keys.sendPaste(), 250);
}

// MARK: - IPC

function registerIpc() {
  ipcMain.handle('app:getState', () => snapshot());
  ipcMain.handle('app:setTab', (_e, tab) => { settings.tab = tab; stores.saveSettings(settings); schedulePush(); });
  ipcMain.handle('app:setPinned', (_e, b) => { settings.pinned = !!b; stores.saveSettings(settings); schedulePush(); });
  ipcMain.handle('app:setThemeMode', (_e, mode) => setThemeMode(mode));
  ipcMain.handle('app:setAutoPaste', (_e, b) => { settings.auto_paste = !!b; stores.saveSettings(settings); schedulePush(); });
  ipcMain.handle('app:setShowMusic', (_e, b) => { settings.show_music = !!b; stores.saveSettings(settings); schedulePush(); });
  ipcMain.handle('app:setLaunchAtLogin', (_e, b) => setLaunchAtLogin(!!b));
  ipcMain.handle('app:resetPlacement', () => { settings.pos = null; userMoved = false; stores.saveSettings(settings); restorePlacement(); schedulePush(); });
  ipcMain.handle('app:hide', () => { lastAutoHide = Date.now(); hidePanel(); });

  ipcMain.handle('store:addTodo', (_e, title, preset) => {
    const text = String(title || '').trim();
    if (!text) return { bucket: null };
    const now = new Date();
    const due = logic.dueDateForPreset(preset, now);
    const today = logic.localDateStr(now);
    const item = stores.addTodo(todos, text, due);
    const bucket = logic.bucketOf(item, today);
    schedulePush();
    return { bucket };
  });
  ipcMain.handle('store:toggleTodo', (_e, id) => { stores.toggleTodo(todos, id); schedulePush(); });
  ipcMain.handle('store:removeTodo', (_e, id) => { stores.removeTodo(todos, id); schedulePush(); });

  ipcMain.handle('notes:add', (_e, text) => { stores.addNote(notes, String(text || '').trim()); schedulePush(); });
  ipcMain.handle('notes:remove', (_e, id) => { stores.removeNote(notes, id); schedulePush(); });

  ipcMain.handle('shelf:remove', (_e, id) => { stores.removeShelf(shelf, id); schedulePush(); });
  ipcMain.handle('shelf:clear', () => { stores.clearShelf(shelf); schedulePush(); });
  ipcMain.handle('shelf:revealAll', () => { for (const it of shelf) shell.showItemInFolder(it.path); });
  ipcMain.handle('shelf:addMany', (_e, paths) => {
    if (Array.isArray(paths) && paths.length) {
      stores.addShelfMany(shelf, paths.filter((p) => typeof p === 'string' && p));
      schedulePush();
    }
  });
  ipcMain.handle('downloads:setRecent', (_e, b) => {
    downloadsRecentOnly = !!b;
    refreshDownloads();
    schedulePush();
  });

  ipcMain.handle('fs:openPath', (_e, p) => { if (typeof p === 'string' && p) shell.openPath(p); });
  ipcMain.handle('fs:revealPath', (_e, p) => { if (typeof p === 'string' && p) shell.showItemInFolder(p); });
  ipcMain.handle('fs:trashPath', async (_e, p) => {
    if (typeof p !== 'string' || !p) return;
    try { await shell.trashItem(p); } catch { /* 忽略 */ }
    refreshDownloads();
    schedulePush();
  });

  ipcMain.handle('vault:add', async (_e, payload) => {
    const site = String(payload.site || '').trim();
    const account = String(payload.account || '').trim();
    if (!site || !account) return { ok: false, error: '站点与账号必填' };
    try {
      await stores.addVaultEntry(vault, {
        site,
        account,
        phone: String(payload.phone || '').trim(),
        password: payload.password ? String(payload.password) : null,
      });
      schedulePush();
      return { ok: true };
    } catch (e) {
      return { ok: false, error: `加密失败: ${e.message}` };
    }
  });
  ipcMain.handle('vault:remove', (_e, id) => { stores.removeVault(vault, id); schedulePush(); });
  ipcMain.handle('vault:updatePassword', async (_e, id, pw) => {
    if (!pw) return { ok: false };
    try {
      await stores.updateVaultPassword(vault, id, String(pw));
      schedulePush();
      return { ok: true };
    } catch (e) {
      return { ok: false, error: e.message };
    }
  });
  ipcMain.handle('vault:reveal', async (_e, id) => {
    const e = vault.find((x) => x.id === id);
    if (!e) return null;
    return stores.revealVault(e);
  });

  ipcMain.handle('clip:remove', (_e, id) => { stores.removeClip(clips, id); schedulePush(); });
  ipcMain.handle('clip:togglePin', (_e, id) => { stores.toggleClipPin(clips, id); schedulePush(); });
  ipcMain.handle('clip:clearUnpinned', () => { stores.clearClipsUnpinned(clips); schedulePush(); });
  ipcMain.handle('clip:clearAll', () => { stores.clearClipsAll(clips); schedulePush(); });
  ipcMain.handle('clip:copy', (_e, id) => {
    const entry = clips.find((x) => x.id === id);
    if (!entry) return { ok: false, autoPaste: false };
    const ok = copyClipBack(entry);
    if (ok && settings.auto_paste) {
      requestAutoPaste();
    }
    schedulePush();
    return { ok, autoPaste: ok && settings.auto_paste };
  });

  ipcMain.handle('downloads:openFolder', () => { shell.openPath(app.getPath('downloads')); });
  ipcMain.handle('music:control', (_e, kind) => { keys.sendMediaKey(String(kind || '')); });
}

// MARK: - 窗口创建

function createWindow() {
  const transparent = isTransparent();
  win = new BrowserWindow({
    width: stores.PANEL_W,
    height: stores.PANEL_H,
    useContentSize: true,
    minWidth: stores.MIN_W,
    minHeight: stores.MIN_H,
    maxWidth: stores.MAX_W,
    maxHeight: stores.MAX_H,
    frame: false,
    transparent,
    resizable: true,
    maximizable: false, // 双击拖拽区不得最大化(面板固定形态)
    fullscreenable: false,
    alwaysOnTop: true,
    skipTaskbar: true, // WS_EX_TOOLWINDOW:去任务栏条 + Alt-Tab
    show: false,
    backgroundColor: transparent ? '#00000000' : (isDark() ? '#1C1C1F' : '#F7F7F8'),
    title: APP_TITLE,
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: true,
      spellcheck: false,
    },
  });

  // 拖拽文件/链接进窗口不得触发导航
  win.webContents.on('will-navigate', (e) => e.preventDefault());
  win.webContents.setWindowOpenHandler(() => ({ action: 'deny' }));
  win.webContents.on('render-process-gone', (_e, details) => log(`renderer gone: ${details.reason}`));

  // Ctrl +/- 禁缩放(保布局)
  win.webContents.on('before-input-event', (e, input) => {
    if ((input.control || input.meta) && ['=', '-', '0', '+'].includes(input.key)) {
      e.preventDefault();
    }
  });

  // 失焦自动收起(常驻模式除外;对应 Rust update 的失焦分支)
  win.on('blur', () => {
    if (!settings.pinned && win.isVisible()) {
      lastAutoHide = Date.now();
      win.hide();
    }
  });

  // 拖动结束持久化位置('moved' 在 Windows 拖动中多次触发,去抖)
  win.on('moved', onWindowMoved);

  // 关闭 → 隐藏(退出走托盘;对应托盘常驻应用惯例)
  win.on('close', (e) => {
    if (!quitting) {
      e.preventDefault();
      hidePanel();
    }
  });

  win.loadFile(path.join(__dirname, 'renderer', 'index.html'));
  win.once('ready-to-show', () => {
    restorePlacement();
    win.show();
    log('window shown');
    schedulePush();
  });
}

// MARK: - 启动

function loadAllStores() {
  todos = stores.loadTodos();
  notes = stores.loadNotes();
  shelf = stores.loadShelf();
  vault = stores.loadVault();
  clips = stores.loadClips();
}

const gotLock = app.requestSingleInstanceLock();
if (!gotLock) {
  app.quit();
} else {
  app.on('second-instance', () => showPanel());

  app.whenReady().then(() => {
    // 数据目录:%APPDATA%\SideDock(与 Rust 版一致);SIDEDOCK_DATA_DIR 覆盖
    if (process.env.SIDEDOCK_DATA_DIR) {
      stores.setDataDir(process.env.SIDEDOCK_DATA_DIR);
    } else {
      stores.setDataDir(path.join(app.getPath('appData'), 'SideDock'));
    }

    // 密码加密注入(safeStorage = Windows DPAPI;与 Rust 版 CryptProtectData 同源)
    stores.setVaultCrypto(
      (plain) => {
        const buf = safeStorage.encryptString(plain);
        return Promise.resolve(buf.toString('base64'));
      },
      async (b64) => {
        try {
          if (!safeStorage.isEncryptionAvailable()) return null;
          return safeStorage.decryptString(Buffer.from(b64, 'base64'));
        } catch {
          return null; // 旧版 DPAPI 密文不兼容等情况:按"未找到保存的密码"处理
        }
      },
    );

    loadAllStores();
    applyTheme();
    log(`=== SideDock 启动 (v${app.getVersion()}) electron=${process.versions.electron} transparent=${isTransparent()}`);

    // 旧设置里开了自启但登录项未登记 → 补登记(沿用用户选择)
    if (settings.launch_at_login && !app.getLoginItemSettings().openAtLogin) {
      setLaunchAtLogin(true);
    }

    // 平台服务:按键服务 + 音乐轮询(脚本从 asar 解到临时目录,-File 不能指向 asar 内路径)
    const musicScript = keys.extractScript('sidedock-music.ps1');
    if (musicScript) music.start(musicScript);
    const keysScript = keys.extractScript('sidedock-keys.ps1');
    if (keysScript) keys.ensureKeys(keysScript);

    nativeTheme.on('updated', () => {
      if (settings.theme_mode === 'System') {
        applyTheme();
        schedulePush();
      }
    });

    registerIpc();
    createWindow();
    setupTray();
    setupHotkey();

    // 轮询:剪贴板 600ms / 下载 2s / 音乐推送 1s(位置插值由渲染层做)
    setInterval(pollClipboard, 600);
    setInterval(() => {
      refreshDownloads();
      schedulePush();
    }, 2000);
    setInterval(() => {
      if (win && !win.isDestroyed() && music.snapshot) {
        win.webContents.send('music', music.snapshot);
      }
    }, 1000);

    // 冒烟模式:启动 3s 后自动退出(CI/本机验证用)
    if (process.env.SIDEDOCK_SMOKE === '1') {
      setTimeout(() => {
        log(`smoke: ok clips=${clips.length} todos=${todos.length} notes=${notes.length} shelf=${shelf.length} vault=${vault.length} dl=${downloads.length}`);
        app.quit();
      }, 3000);
    }
  });

  app.on('before-quit', () => {
    quitting = true;
    music.stop();
    keys.stopKeys();
  });

  app.on('window-all-closed', () => {
    // 托盘常驻:不退出(Windows);mac 开发环境退出便于冒烟
    if (!isWin) app.quit();
  });

  process.on('uncaughtException', (e) => {
    log(`[uncaught] ${e.stack || e.message}`);
  });
}
