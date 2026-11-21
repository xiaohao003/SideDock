// preload.js — 渲染层安全桥(contextBridge;sandbox 下 webUtils 可用)
'use strict';

const { contextBridge, ipcRenderer, webUtils } = require('electron');

contextBridge.exposeInMainWorld('sidedock', {
  // 状态
  getState: () => ipcRenderer.invoke('app:getState'),
  onState: (cb) => ipcRenderer.on('state', (_e, s) => cb(s)),
  onMusic: (cb) => ipcRenderer.on('music', (_e, m) => cb(m)),
  onUi: (cb) => ipcRenderer.on('ui', (_e, u) => cb(u)),

  // 待办
  addTodo: (title, preset) => ipcRenderer.invoke('store:addTodo', title, preset),
  toggleTodo: (id) => ipcRenderer.invoke('store:toggleTodo', id),
  removeTodo: (id) => ipcRenderer.invoke('store:removeTodo', id),

  // 笔记
  addNote: (text) => ipcRenderer.invoke('notes:add', text),
  removeNote: (id) => ipcRenderer.invoke('notes:remove', id),

  // 暂存
  removeShelf: (id) => ipcRenderer.invoke('shelf:remove', id),
  clearShelf: () => ipcRenderer.invoke('shelf:clear'),
  revealAllShelf: () => ipcRenderer.invoke('shelf:revealAll'),
  addShelfMany: (paths) => ipcRenderer.invoke('shelf:addMany', paths),
  setDownloadsRecent: (b) => ipcRenderer.invoke('downloads:setRecent', b),
  openPath: (p) => ipcRenderer.invoke('fs:openPath', p),
  revealPath: (p) => ipcRenderer.invoke('fs:revealPath', p),
  trashPath: (p) => ipcRenderer.invoke('fs:trashPath', p),

  // 密码
  addVault: (payload) => ipcRenderer.invoke('vault:add', payload),
  removeVault: (id) => ipcRenderer.invoke('vault:remove', id),
  updateVaultPassword: (id, pw) => ipcRenderer.invoke('vault:updatePassword', id, pw),
  revealVault: (id) => ipcRenderer.invoke('vault:reveal', id),

  // 剪贴板
  removeClip: (id) => ipcRenderer.invoke('clip:remove', id),
  toggleClipPin: (id) => ipcRenderer.invoke('clip:togglePin', id),
  clearClipsUnpinned: () => ipcRenderer.invoke('clip:clearUnpinned'),
  clearClipsAll: () => ipcRenderer.invoke('clip:clearAll'),
  copyClip: (id) => ipcRenderer.invoke('clip:copy', id),

  // 下载
  openDownloadsFolder: () => ipcRenderer.invoke('downloads:openFolder'),

  // 音乐(媒体键经按键服务模拟;对应 Rust send_media_key)
  musicControl: (kind) => ipcRenderer.invoke('music:control', kind),

  // 设置 / 窗口
  setTab: (tab) => ipcRenderer.invoke('app:setTab', tab),
  setPinned: (b) => ipcRenderer.invoke('app:setPinned', b),
  setThemeMode: (mode) => ipcRenderer.invoke('app:setThemeMode', mode),
  setAutoPaste: (b) => ipcRenderer.invoke('app:setAutoPaste', b),
  setShowMusic: (b) => ipcRenderer.invoke('app:setShowMusic', b),
  setLaunchAtLogin: (b) => ipcRenderer.invoke('app:setLaunchAtLogin', b),
  resetPlacement: () => ipcRenderer.invoke('app:resetPlacement'),
  hidePanel: () => ipcRenderer.invoke('app:hide'),

  // 拖放文件 → 本地路径(Electron ≥32 移除了 File.path,统一走 webUtils)
  pathForFile: (file) => webUtils.getPathForFile(file),
});
