// icons.js — 矢量图标(24 viewBox stroke 图形,对应 Rust 版 widgets.rs 手绘图标)
'use strict';

(function () {
  const S = 'fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round"';

  function svg(inner, size) {
    return `<svg width="${size}" height="${size}" viewBox="0 0 24 24" ${S}>${inner}</svg>`;
  }

  const ICONS = {
    todo: (s) => svg(`<line x1="8" y1="7" x2="20" y2="7"/><line x1="8" y1="15" x2="20" y2="15"/><circle cx="4.5" cy="7" r="1.4" fill="currentColor" stroke="none"/><circle cx="4.5" cy="15" r="1.4" fill="currentColor" stroke="none"/>`, s),
    note: (s) => svg(`<path d="M4 5.5 A1.5 1.5 0 0 1 5.5 4 H14 L20 10 V18.5 A1.5 1.5 0 0 1 18.5 20 H5.5 A1.5 1.5 0 0 1 4 18.5 Z"/><path d="M14 4 V10 H20"/><line x1="8" y1="15" x2="15.5" y2="15"/>`, s),
    download: (s) => svg(`<circle cx="12" cy="12" r="9"/><line x1="12" y1="7.5" x2="12" y2="15.5"/><polyline points="8.8 12.3 12 15.5 15.2 12.3"/>`, s),
    shelf: (s) => svg(`<path d="M4 13 V19 H20 V13"/><line x1="12" y1="4" x2="12" y2="15.5"/><polyline points="9.2 12.7 12 15.5 14.8 12.7"/>`, s),
    key: (s) => svg(`<circle cx="8" cy="12" r="4"/><line x1="12" y1="12" x2="20" y2="12"/><line x1="17" y1="12" x2="17" y2="15.5"/><line x1="14.3" y1="12" x2="14.3" y2="14.5"/>`, s),
    clipboard: (s) => svg(`<rect x="5" y="4" width="14" height="17" rx="2"/><rect x="9" y="2.5" width="6" height="3.5" rx="1" fill="currentColor" stroke="none"/><line x1="9" y1="14" x2="15" y2="14"/>`, s),
    gear: (s) => svg(`<circle cx="12" cy="12" r="4.6"/><line x1="12" y1="2.8" x2="12" y2="5.6"/><line x1="12" y1="18.4" x2="12" y2="21.2"/><line x1="2.8" y1="12" x2="5.6" y2="12"/><line x1="18.4" y1="12" x2="21.2" y2="12"/><line x1="5.5" y1="5.5" x2="7.5" y2="7.5"/><line x1="16.5" y1="16.5" x2="18.5" y2="18.5"/><line x1="18.5" y1="5.5" x2="16.5" y2="7.5"/><line x1="7.5" y1="16.5" x2="5.5" y2="18.5"/>`, s),
    pin: (s) => svg(`<line x1="8.5" y1="6" x2="15.5" y2="6"/><line x1="12" y1="6" x2="12" y2="18.5"/><line x1="9.2" y1="18.5" x2="14.8" y2="18.5"/>`, s),
    chevron: (s) => svg(`<polyline points="9.5 6 15.5 12 9.5 18"/>`, s),
    plus: (s) => svg(`<line x1="12" y1="5" x2="12" y2="19"/><line x1="5" y1="12" x2="19" y2="12"/>`, s),
    x: (s) => svg(`<line x1="6.5" y1="6.5" x2="17.5" y2="17.5"/><line x1="17.5" y1="6.5" x2="6.5" y2="17.5"/>`, s),
    check: (s) => svg(`<polyline points="5.5 12.5 10 17 18.5 7.5"/>`, s),
    bell: (s) => svg(`<path d="M12 4.5 A5.5 5.5 0 0 1 17.5 10 V15.5 H6.5 V10 A5.5 5.5 0 0 1 12 4.5"/><line x1="4.8" y1="15.5" x2="19.2" y2="15.5"/><circle cx="12" cy="18.6" r="1.3" fill="currentColor" stroke="none"/>`, s),
    search: (s) => svg(`<circle cx="10.5" cy="10.5" r="5.8"/><line x1="14.8" y1="14.8" x2="19.5" y2="19.5"/>`, s),
    folder: (s) => svg(`<path d="M3 6.5 A1.5 1.5 0 0 1 4.5 5 H9 L11 7.5 H19.5 A1.5 1.5 0 0 1 21 9 V18 A1.5 1.5 0 0 1 19.5 19.5 H4.5 A1.5 1.5 0 0 1 3 18 Z"/>`, s),
    trash: (s) => svg(`<line x1="4.5" y1="6.5" x2="19.5" y2="6.5"/><line x1="12" y1="3.8" x2="12" y2="6.5"/><path d="M6.5 6.5 L7.5 20 H16.5 L17.5 6.5"/><line x1="10.2" y1="10" x2="10.2" y2="16"/><line x1="13.8" y1="10" x2="13.8" y2="16"/>`, s),
    pinSmall: (s) => svg(`<circle cx="11" cy="7" r="3.4" fill="currentColor" stroke="none"/><line x1="12" y1="9.5" x2="14.5" y2="19"/>`, s),
    eye: (s) => svg(`<line x1="3.5" y1="12" x2="20.5" y2="12"/><circle cx="12" cy="12" r="3.8"/>`, s),
    wand: (s) => svg(`<line x1="5" y1="19" x2="16.5" y2="7.5"/><circle cx="19.5" cy="4.8" r="1.2" fill="currentColor" stroke="none"/><circle cx="5.5" cy="5" r="1" fill="currentColor" stroke="none"/><circle cx="17.5" cy="18.5" r="1" fill="currentColor" stroke="none"/>`, s),
    musicnote: (s) => svg(`<line x1="9.2" y1="18" x2="9.2" y2="5.8"/><polyline points="9.2 5.8 17 7.6 17 13.4"/><circle cx="7" cy="18.4" r="2.3" fill="currentColor" stroke="none"/><circle cx="15" cy="14" r="2.3" fill="currentColor" stroke="none"/>`, s),
    file: (s) => svg(`<path d="M6 3 H14 L18 7 V21 H6 Z"/><path d="M14 3 V7 H18"/><line x1="9" y1="14.5" x2="15" y2="14.5"/>`, s),
    play: (s) => svg(`<polygon points="8.5 5 19 12 8.5 19" fill="currentColor" stroke="none"/>`, s),
    pause: (s) => svg(`<rect x="7.5" y="5.5" width="3.4" height="13" rx="1.2" fill="currentColor" stroke="none"/><rect x="13.1" y="5.5" width="3.4" height="13" rx="1.2" fill="currentColor" stroke="none"/>`, s),
    prev: (s) => svg(`<rect x="5" y="5.5" width="3" height="13" rx="1.2" fill="currentColor" stroke="none"/><polygon points="19 5.5 10 12 19 18.5" fill="currentColor" stroke="none"/>`, s),
    next: (s) => svg(`<polygon points="5 5.5 14 12 5 18.5" fill="currentColor" stroke="none"/><rect x="16" y="5.5" width="3" height="13" rx="1.2" fill="currentColor" stroke="none"/>`, s),
    arrowUp: (s) => svg(`<line x1="12" y1="19" x2="12" y2="6.5"/><polyline points="7 11 12 6 17 11"/>`, s),
    pencil: (s) => svg(`<line x1="5.5" y1="18.5" x2="17" y2="7"/><polyline points="14.5 4.5 19.5 4.5 19.5 9.5"/>`, s),
  };

  window.Icon = function (name, size = 16) {
    const fn = ICONS[name];
    return fn ? fn(size) : '';
  };
})();
