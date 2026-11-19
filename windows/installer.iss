; installer.iss 鈥?SideDock Windows 瀹夎鍚戝(Inno Setup)
; 鏋勫缓:ISCC installer.iss(闇€鍏?cargo build --release)
; 鐗规€?娆㈣繋/璁稿彲 鈫?瀹夎鐩綍鍙€?鈫?寮€濮嬭彍鍗?鈫?妗岄潰蹇嵎鏂瑰紡(鍙€?鈫?鍗歌浇娉ㄥ唽

#define MyAppName "SideDock"
#define MyAppVersion "1.1.10"
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
; 涓枃鍚戝鏂囦欢鐢?CI 浠庡畼鏂逛粨搴撲笅杞藉埌 installer/ 鐩綍(Inno 6.x 榛樿涓嶅甫)
Name: "chinesesimplified"; MessagesFile: "installer\ChineseSimplified.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"
Name: "autostart"; Description: "寮€鏈鸿嚜鍔ㄥ惎鍔?; GroupDescription: "鍏朵粬閫夐」:"

[Files]
Source: "target\release\{#MyAppExeName}"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\{cm:UninstallProgram,{#MyAppName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Registry]
; 寮€鏈鸿嚜鍚?娉ㄥ唽琛?Run 閿?涓庡簲鐢ㄥ唴璁剧疆鍚屼竴浣嶇疆;鍗歌浇鏃舵竻鐞?
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "SideDock"; ValueData: """{app}\{#MyAppExeName}"""; Flags: uninsdeletevalue; Tasks: autostart

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#MyAppName}}"; Flags: nowait postinstall skipifsilent
