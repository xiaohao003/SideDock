// music.js — 正在播放(Windows SMTC,经 PowerShell 轮询;对应 Rust 版 music.rs)
// 常驻 powershell 进程每 2s 输出一行 JSON;封面随曲目缓存(base64 PNG)。
// 非 Windows(本机 mac 开发/冒烟)为空实现,卡片自动隐藏。
'use strict';

const { spawn } = require('child_process');
const path = require('path');

class MusicController {
  constructor() {
    this.snapshot = null; // { title, artist, duration_secs, position_secs, playing, taken_at_secs, art_b64 }
    this.child = null;
    this.buf = '';
    this.artCache = new Map(); // key "title|artist" → art_b64
    this.stopped = false;
  }

  /** scriptPath:已在磁盘上的 ps1(主进程启动时从 asar 解出) */
  start(scriptPath) {
    if (process.platform !== 'win32' || this.child) return;
    try {
      this.child = spawn('powershell.exe', [
        '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', scriptPath,
      ], { windowsHide: true, stdio: ['ignore', 'pipe', 'ignore'] });
      this.child.stdout.setEncoding('utf8');
      this.child.stdout.on('data', (chunk) => this.#onData(chunk));
      this.child.on('exit', () => {
        this.child = null;
        // 意外退出则 5s 后重启(音乐卡消失比崩溃好;上限交给进程自身稳定性)
        if (!this.stopped) {
          setTimeout(() => {
            if (!this.stopped) this.start(scriptPath);
          }, 5000).unref();
        }
      });
    } catch {
      this.child = null;
    }
  }

  #onData(chunk) {
    this.buf += chunk;
    let idx;
    while ((idx = this.buf.indexOf('\n')) >= 0) {
      const line = this.buf.slice(0, idx).trim();
      this.buf = this.buf.slice(idx + 1);
      if (!line) continue;
      if (line === 'NONE') {
        this.snapshot = null;
        continue;
      }
      try {
        const o = JSON.parse(line);
        if (o.art_b64) this.artCache.set(`${o.title}|${o.artist}`, o.art_b64);
        else o.art_b64 = this.artCache.get(`${o.title}|${o.artist}`) || '';
        this.snapshot = o;
      } catch { /* 半行/坏行忽略 */ }
    }
  }

  stop() {
    this.stopped = true;
    if (this.child) {
      try { this.child.kill(); } catch { /* 忽略 */ }
      this.child = null;
    }
    this.snapshot = null;
  }
}

/** 位置插值(渲染时调用,与 Rust MusicSnapshot::display_position 同规则) */
function displayPosition(snap, nowSecs) {
  if (!snap) return 0;
  if (snap.playing) {
    const p = (snap.position_secs || 0) + Math.max(0, nowSecs - (snap.taken_at_secs || 0));
    if (snap.duration_secs > 0) return Math.min(p, snap.duration_secs);
    return p;
  }
  return snap.position_secs || 0;
}

module.exports = { MusicController, displayPosition, scriptSourcePath: () => path.join(__dirname, '..', 'scripts', 'sidedock-music.ps1') };
