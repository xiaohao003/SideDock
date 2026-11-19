; installer.iss — SideDock Windows 安装向导(Inno Setup)
; 构建:ISCC installer.iss(需先 cargo build --release)
; 特性:欢迎/许可 → 安装目录可选 → 开始菜单 → 桌面快捷方式(可选)→ 卸载注册

#define MyAppName "SideDock"
#define MyAppVersion "1.1.9"
#define MyAppPublisher "xiaohao003"
#define MyAppExeName "SideDock.exe"
#define MyAppURL "https://github.com/xiaohao003/SideDock"

[Setup]
AppId={{8C1F0D9E-6B7A-4E5D-9C2B-SIDEDOCK0001}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
AllowNoIcons=yes
OutputDir=dist
OutputBaseFilename=SideDock-windows-setup
SetupIconFile=sidedock.ico
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
PrivilegesRequiredOverridesAllowed=dialog
UninstallDisplayIcon={app}\{#MyAppExeName}

[Languages]
; 中文向导文件由 CI 从官方仓库下载到 installer/ 目录(Inno 6.x 默认不带)
Name: "chinesesimplified"; MessagesFile: "installer\ChineseSimplified.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"
Name: "autostart"; Description: "开机自动启动"; GroupDescription: "其他选项:"

[Files]
Source: "target\release\{#MyAppExeName}"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\{cm:UninstallProgram,{#MyAppName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Registry]
; 开机自启(注册表 Run 键,与应用内设置同一位置;卸载时清理)
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "SideDock"; ValueData: """{app}\{#MyAppExeName}"""; Flags: uninsdeletevalue; Tasks: autostart

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#MyAppName}}"; Flags: nowait postinstall skipifsilent
