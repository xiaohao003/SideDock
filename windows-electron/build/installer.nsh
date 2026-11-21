; installer.nsh — electron-builder NSIS 自定义钩子
!macro customInstall
  ; 覆盖升级后强制系统刷新图标缓存(SHCNE_ASSOCCHANGED),
  ; 否则桌面/开始菜单快捷方式可能一直显示旧版(默认 Electron)图标
  System::Call 'Shell32::SHChangeNotify(i 0x08000000, i 0, i 0, i 0)'
!macroend
