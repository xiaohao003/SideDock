// keys.js — 按键模拟 + 前台应用名(Windows;对应 Rust 版 platform.rs SendInput/foreground_app)
// keyserver:常驻 powershell 进程,stdin 收命令(KEY xx / PASTE)即时模拟按键,
//   避免每次动作重启 PowerShell 的 0.5-1s 延迟。
// fgapp:一次性进程取当前前台应用进程名(剪贴板记录来源;调用频率低,按需拉起)。
'use strict';

const { spawn } = require('child_process');
const fs = require('fs');
const os = require('os');
const path = require('path');

// MARK: - 脚本解出(scripts/ 打进 asar,子进程不能直接 -File asar 内路径)

function extractScript(name) {
  const src = path.join(__dirname, '..', 'scripts', name);
  const out = path.join(os.tmpdir(), `sidedock-${name}`);
  try {
    fs.copyFileSync(src, out);
    return out;
  } catch {
    return null;
  }
}

// MARK: - 常驻按键服务

let keyChild = null;
let keyBuf = '';
let keyReady = false;
const keyQueue = [];

function ensureKeys(scriptPath) {
  if (process.platform !== 'win32') return;
  if (keyChild) return;
  try {
    keyChild = spawn('powershell.exe', [
      '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', scriptPath,
    ], { windowsHide: true, stdio: ['pipe', 'pipe', 'ignore'] });
    keyChild.stdout.setEncoding('utf8');
    keyChild.stdout.on('data', (chunk) => {
      keyBuf += chunk;
      let idx;
      while ((idx = keyBuf.indexOf('\n')) >= 0) {
        const line = keyBuf.slice(0, idx).trim();
        keyBuf = keyBuf.slice(idx + 1);
        if (line === 'READY') {
          keyReady = true;
          while (keyQueue.length) keyChild.stdin.write(keyQueue.shift());
        }
      }
    });
    keyChild.on('exit', () => {
      keyChild = null;
      keyReady = false;
      keyQueue.length = 0;
    });
  } catch {
    keyChild = null;
  }
}

function sendKeyLine(line) {
  if (!keyChild) return false;
  const payload = `${line}\n`;
  if (!keyReady) {
    keyQueue.push(payload);
    return true; // 已排队,READY 后发出
  }
  keyChild.stdin.write(payload);
  return true;
}

/** 媒体键:Prev=B1 Next=B2 PlayPause=B3(VK_MEDIA_*,与 Rust send_media_key 同) */
function sendMediaKey(kind) {
  const vk = { prev: 'B1', next: 'B2', playpause: 'B3' }[String(kind).toLowerCase()];
  if (!vk) return;
  sendKeyLine(`KEY ${vk}`);
}

/** 向前台应用模拟 Ctrl+V(调用前应先隐藏本面板;对应 Rust send_paste) */
function sendPaste() {
  sendKeyLine('PASTE');
}

function stopKeys() {
  if (keyChild) {
    try { keyChild.stdin.end(); } catch { /* 忽略 */ }
    try { keyChild.kill(); } catch { /* 忽略 */ }
    keyChild = null;
    keyReady = false;
  }
}

// MARK: - 前台应用名(一次性,异步)

/** 回调 (name|null);失败/超时 2s 给 null */
function fetchForegroundApp(cb) {
  if (process.platform !== 'win32') {
    cb(null);
    return;
  }
  const script = extractScript('sidedock-fgapp.ps1');
  if (!script) {
    cb(null);
    return;
  }
  let done = false;
  const finish = (name) => {
    if (done) return;
    done = true;
    clearTimeout(timer);
    cb(name);
  };
  const timer = setTimeout(() => finish(null), 2500);
  let out = '';
  try {
    const child = spawn('powershell.exe', [
      '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', script,
    ], { windowsHide: true, stdio: ['ignore', 'pipe', 'ignore'] });
    child.stdout.setEncoding('utf8');
    child.stdout.on('data', (c) => { out += c; });
    child.on('close', () => {
      const name = out.trim().split('\n')[0];
      finish(name || null);
    });
    child.on('error', () => finish(null));
  } catch {
    finish(null);
  }
}

module.exports = {
  extractScript,
  ensureKeys,
  sendMediaKey,
  sendPaste,
  stopKeys,
  fetchForegroundApp,
  keyScriptPath: () => path.join(__dirname, '..', 'scripts', 'sidedock-keys.ps1'),
};
