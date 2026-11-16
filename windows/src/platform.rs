// platform.rs — 平台抽象层
// Windows: 真实实现(注册表/DPAPI/SendInput/Explorer/SMTC 辅助)
// 非 Windows: 编译可过的替身,保证核心逻辑可在任意平台 cargo test
use std::path::Path;

// MARK: - 剪贴板序号(对应 NSPasteboard.changeCount 轮询)

#[cfg(windows)]
pub fn clipboard_sequence() -> u64 {
    unsafe { windows::Win32::System::DataExchange::GetClipboardSequenceNumber() as u64 }
}

#[cfg(not(windows))]
pub fn clipboard_sequence() -> u64 {
    0
}

// MARK: - 剪贴板读写(arboard,跨平台)

pub fn clipboard_text() -> Option<String> {
    let mut cb = arboard::Clipboard::new().ok()?;
    cb.get_text().ok()
}

pub fn clipboard_image_rgba() -> Option<(usize, usize, Vec<u8>)> {
    let mut cb = arboard::Clipboard::new().ok()?;
    let img = cb.get_image().ok()?;
    Some((img.width as usize, img.height as usize, img.bytes.into_owned()))
}

pub fn clipboard_set_text(text: &str) -> bool {
    match arboard::Clipboard::new() {
        Ok(mut cb) => cb.set_text(text.to_string()).is_ok(),
        Err(_) => false,
    }
}

pub fn clipboard_set_image(w: usize, h: usize, rgba: Vec<u8>) -> bool {
    match arboard::Clipboard::new() {
        Ok(mut cb) => cb
            .set_image(arboard::ImageData {
                width: w,
                height: h,
                bytes: std::borrow::Cow::Owned(rgba),
            })
            .is_ok(),
        Err(_) => false,
    }
}

// MARK: - 前台应用名(对应 NSWorkspace.frontmostApplication)

#[cfg(windows)]
pub fn foreground_app() -> Option<String> {
    use windows::Win32::Foundation::CloseHandle;
    use windows::Win32::System::Threading::{
        OpenProcess, QueryFullProcessImageNameW, PROCESS_NAME_WIN32,
        PROCESS_QUERY_LIMITED_INFORMATION,
    };
    use windows::Win32::UI::WindowsAndMessaging::{GetForegroundWindow, GetWindowThreadProcessId};
    use windows::core::PWSTR;

    unsafe {
        let hwnd = GetForegroundWindow();
        if hwnd.is_invalid() {
            return None;
        }
        let mut pid = 0u32;
        GetWindowThreadProcessId(hwnd, Some(&mut pid));
        if pid == 0 {
            return None;
        }
        let Ok(handle) = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, false, pid) else {
            return None;
        };
        let mut buf = [0u16; 1024];
        let mut len = buf.len() as u32;
        let ok = QueryFullProcessImageNameW(
            handle,
            PROCESS_NAME_WIN32,
            PWSTR(buf.as_mut_ptr()),
            &mut len,
        )
        .is_ok();
        let _ = CloseHandle(handle);
        if !ok || len == 0 {
            return None;
        }
        let path = String::from_utf16_lossy(&buf[..len as usize]);
        let exe = std::path::Path::new(&path)
            .file_stem()
            .map(|s| s.to_string_lossy().to_string());
        exe
    }
}

#[cfg(not(windows))]
pub fn foreground_app() -> Option<String> {
    None
}

// MARK: - DPAPI(对应 macOS 钥匙串:仅本机可解密)

#[cfg(windows)]
pub fn protect(plain: &str) -> Result<String, String> {
    use base64::Engine;
    use windows::Win32::Foundation::{LocalFree, HLOCAL};
    use windows::Win32::Security::Cryptography::{
        CryptProtectData, CRYPTPROTECT_UI_FORBIDDEN, CRYPT_INTEGER_BLOB,
    };
    use windows::core::w;

    let data = plain.as_bytes();
    let blob_in = CRYPT_INTEGER_BLOB {
        cbData: data.len() as u32,
        pbData: data.as_ptr() as *mut u8,
    };
    let mut blob_out = CRYPT_INTEGER_BLOB::default();
    unsafe {
        CryptProtectData(
            &blob_in,
            w!("SideDock"),
            None,
            None,
            None,
            CRYPTPROTECT_UI_FORBIDDEN,
            &mut blob_out,
        )
        .map_err(|e| format!("DPAPI 加密失败: {e}"))?;
        let out = std::slice::from_raw_parts(blob_out.pbData, blob_out.cbData as usize).to_vec();
        let _ = LocalFree(HLOCAL(blob_out.pbData.cast()));
        Ok(base64::engine::general_purpose::STANDARD.encode(out))
    }
}

#[cfg(windows)]
pub fn unprotect(encoded: &str) -> Option<String> {
    use base64::Engine;
    use windows::Win32::Foundation::{LocalFree, HLOCAL};
    use windows::Win32::Security::Cryptography::{
        CryptUnprotectData, CRYPTPROTECT_UI_FORBIDDEN, CRYPT_INTEGER_BLOB,
    };

    let data = base64::engine::general_purpose::STANDARD.decode(encoded).ok()?;
    let blob_in = CRYPT_INTEGER_BLOB {
        cbData: data.len() as u32,
        pbData: data.as_ptr() as *mut u8,
    };
    let mut blob_out = CRYPT_INTEGER_BLOB::default();
    unsafe {
        CryptUnprotectData(
            &blob_in,
            None,
            None,
            None,
            None,
            CRYPTPROTECT_UI_FORBIDDEN,
            &mut blob_out,
        )
        .ok()?;
        let out = std::slice::from_raw_parts(blob_out.pbData, blob_out.cbData as usize).to_vec();
        let _ = LocalFree(HLOCAL(blob_out.pbData.cast()));
        String::from_utf8(out).ok()
    }
}

#[cfg(not(windows))]
pub fn protect(plain: &str) -> Result<String, String> {
    use base64::Engine;
    Ok(base64::engine::general_purpose::STANDARD.encode(plain.as_bytes()))
}

#[cfg(not(windows))]
pub fn unprotect(encoded: &str) -> Option<String> {
    use base64::Engine;
    String::from_utf8(base64::engine::general_purpose::STANDARD.decode(encoded).ok()?).ok()
}

// MARK: - SendInput(自动粘贴 / 媒体键)

#[cfg(windows)]
fn send_key(vk: u16, extended: bool) {
    use windows::Win32::UI::Input::KeyboardAndMouse::{
        SendInput, INPUT, INPUT_0, KEYBDINPUT, KEYBD_EVENT_FLAGS, KEYEVENTF_KEYUP, VIRTUAL_KEY,
    };
    let make = |vk: u16, up: bool| INPUT {
        r#type: windows::Win32::UI::Input::KeyboardAndMouse::INPUT_KEYBOARD,
        Anonymous: INPUT_0 {
            ki: KEYBDINPUT {
                wVk: VIRTUAL_KEY(vk),
                wScan: 0,
                dwFlags: if up { KEYBD_EVENT_FLAGS(KEYEVENTF_KEYUP.0) } else { KEYBD_EVENT_FLAGS(0) },
                time: 0,
                dwExtraInfo: 0,
            },
        },
    };
    let _ = extended; // 暂无需要扩展键位的调用
    let inputs = [make(vk, false), make(vk, true)];
    unsafe {
        SendInput(&inputs, std::mem::size_of::<INPUT>() as i32);
    }
}

#[cfg(windows)]
fn send_key_combo(keys: [u16; 2]) {
    use windows::Win32::UI::Input::KeyboardAndMouse::{
        SendInput, INPUT, INPUT_0, KEYBDINPUT, KEYBD_EVENT_FLAGS, KEYEVENTF_KEYUP, VIRTUAL_KEY,
    };
    let make = |vk: u16, up: bool| INPUT {
        r#type: windows::Win32::UI::Input::KeyboardAndMouse::INPUT_KEYBOARD,
        Anonymous: INPUT_0 {
            ki: KEYBDINPUT {
                wVk: VIRTUAL_KEY(vk),
                wScan: 0,
                dwFlags: if up { KEYBD_EVENT_FLAGS(KEYEVENTF_KEYUP.0) } else { KEYBD_EVENT_FLAGS(0) },
                time: 0,
                dwExtraInfo: 0,
            },
        },
    };
    let inputs = [
        make(keys[0], false),
        make(keys[1], false),
        make(keys[1], true),
        make(keys[0], true),
    ];
    unsafe {
        SendInput(&inputs, std::mem::size_of::<INPUT>() as i32);
    }
}

/// 向前台应用模拟 Ctrl+V(调用前应先隐藏本面板)
#[cfg(windows)]
pub fn send_paste() {
    const VK_CONTROL: u16 = 0x11;
    const VK_V: u16 = 0x56;
    std::thread::sleep(std::time::Duration::from_millis(150));
    send_key_combo([VK_CONTROL, VK_V]);
}

#[cfg(not(windows))]
pub fn send_paste() {}

#[cfg(windows)]
pub fn send_media_key(kind: MediaKey) {
    let vk: u16 = match kind {
        MediaKey::PlayPause => 0xB3, // VK_MEDIA_PLAY_PAUSE
        MediaKey::Next => 0xB2,      // VK_MEDIA_NEXT_TRACK
        MediaKey::Prev => 0xB1,      // VK_MEDIA_PREV_TRACK
    };
    send_key(vk, true);
}

#[cfg(not(windows))]
pub fn send_media_key(_kind: MediaKey) {}

#[derive(Clone, Copy)]
pub enum MediaKey {
    PlayPause,
    Next,
    Prev,
}

// MARK: - 文件操作(打开 / 在资源管理器中显示 / 移到回收站)

pub fn open_path(path: &Path) {
    #[cfg(windows)]
    {
        use windows::core::{HSTRING, PCWSTR};
        use windows::Win32::UI::Shell::ShellExecuteW;
        use windows::Win32::UI::WindowsAndMessaging::SW_SHOWNORMAL;
        let file = HSTRING::from(path.as_os_str().to_string_lossy().as_ref());
        unsafe {
            ShellExecuteW(None, windows::core::w!("open"), PCWSTR(file.as_ptr()), None, None, SW_SHOWNORMAL);
        }
    }
    #[cfg(not(windows))]
    {
        let _ = std::process::Command::new("open").arg(path).spawn();
    }
}

pub fn reveal_in_explorer(path: &Path) {
    #[cfg(windows)]
    {
        let _ = std::process::Command::new("explorer")
            .arg(format!("/select,{}", path.display()))
            .spawn();
    }
    #[cfg(not(windows))]
    {
        let _ = std::process::Command::new("open").arg("-R").arg(path).spawn();
    }
}

#[cfg(windows)]
pub fn trash_path(path: &Path) -> bool {
    use windows::core::PCWSTR;
    use windows::Win32::Foundation::HWND;
    use windows::Win32::UI::Shell::{
        SHFileOperationW, FOF_ALLOWUNDO, FOF_NOCONFIRMATION, FOF_NOERRORUI, FOF_SILENT,
        SHFILEOPSTRUCTW,
    };

    use std::os::windows::ffi::OsStrExt;
    let mut from: Vec<u16> = path.as_os_str().encode_wide().collect();
    from.push(0);
    from.push(0); // 双 NUL 结尾(路径列表约定)
    let mut op = SHFILEOPSTRUCTW {
        hwnd: HWND::default(),
        wFunc: windows::Win32::UI::Shell::FO_DELETE,
        pFrom: PCWSTR(from.as_ptr()),
        pTo: PCWSTR::null(),
        fFlags: (FOF_ALLOWUNDO | FOF_NOCONFIRMATION | FOF_SILENT | FOF_NOERRORUI).0 as u16,
        fAnyOperationsAborted: windows::Win32::Foundation::BOOL(0),
        hNameMappings: std::ptr::null_mut(),
        lpszProgressTitle: PCWSTR::null(),
    };
    unsafe { SHFileOperationW(&mut op) == 0 }
}

#[cfg(not(windows))]
pub fn trash_path(_path: &Path) -> bool {
    false
}

// MARK: - 开机自启(HKCU ...\CurrentVersion\Run)

#[cfg(windows)]
const RUN_KEY: &str = r"Software\Microsoft\Windows\CurrentVersion\Run";

#[cfg(windows)]
pub fn set_launch_at_login(enable: bool) -> bool {
    use winreg::enums::{HKEY_CURRENT_USER, KEY_QUERY_VALUE, KEY_SET_VALUE};
    use winreg::RegKey;
    let hk = RegKey::predef(HKEY_CURRENT_USER);
    let Ok(key) = hk.open_subkey_with_flags(RUN_KEY, KEY_SET_VALUE | KEY_QUERY_VALUE) else {
        return false;
    };
    if enable {
        let Some(exe) = std::env::current_exe().ok() else { return false };
        let val = format!("\"{}\"", exe.display());
        key.set_value("SideDock", &val).is_ok()
    } else {
        key.delete_value("SideDock").is_ok()
    }
}

#[cfg(windows)]
pub fn is_launch_at_login() -> bool {
    use winreg::enums::{HKEY_CURRENT_USER, KEY_QUERY_VALUE};
    use winreg::RegKey;
    let hk = RegKey::predef(HKEY_CURRENT_USER);
    hk.open_subkey_with_flags(RUN_KEY, KEY_QUERY_VALUE)
        .and_then(|k| k.get_value::<String, _>("SideDock"))
        .is_ok()
}

#[cfg(not(windows))]
pub fn set_launch_at_login(_enable: bool) -> bool {
    false
}

#[cfg(not(windows))]
pub fn is_launch_at_login() -> bool {
    false
}

// MARK: - 系统深色外观(注册表 AppsUseLightTheme,跟随系统用;UI 层每 2s 轮询)

#[cfg(windows)]
pub fn system_is_dark() -> bool {
    use winreg::enums::{HKEY_CURRENT_USER, KEY_READ};
    use winreg::RegKey;
    let hk = RegKey::predef(HKEY_CURRENT_USER);
    hk.open_subkey_with_flags(
        r"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize",
        KEY_READ,
    )
    .and_then(|k| k.get_value::<u32, _>("AppsUseLightTheme"))
    .map(|v| v == 0)
    .unwrap_or(false)
}

#[cfg(not(windows))]
pub fn system_is_dark() -> bool {
    false
}

// MARK: - 面板窗口修饰(去任务栏条 + 贴右缘 + 置顶)

#[cfg(windows)]
pub fn fixup_panel_window(title: &str, dock_right: bool) {
    use windows::core::PCWSTR;
    use windows::Win32::Foundation::RECT;
    use windows::Win32::UI::WindowsAndMessaging::{
        FindWindowW, GetSystemMetrics, GetWindowLongPtrW, GetWindowRect, SetWindowLongPtrW,
        SetWindowPos, GWL_EXSTYLE, HWND_TOPMOST, SM_CXSCREEN, SM_CYSCREEN, SWP_NOACTIVATE,
        SWP_NOMOVE, SWP_NOSIZE, WS_EX_APPWINDOW, WS_EX_TOOLWINDOW,
    };

    let title16: Vec<u16> = title.encode_utf16().chain(std::iter::once(0)).collect();
    unsafe {
        let Ok(hwnd) = FindWindowW(PCWSTR::null(), PCWSTR(title16.as_ptr())) else {
            return;
        };
        // 去任务栏条(WS_EX_TOOLWINDOW + 移除 WS_EX_APPWINDOW)
        let ex = GetWindowLongPtrW(hwnd, GWL_EXSTYLE);
        let ex = (ex | WS_EX_TOOLWINDOW.0 as isize) & !(WS_EX_APPWINDOW.0 as isize);
        SetWindowLongPtrW(hwnd, GWL_EXSTYLE, ex);
        let _ = SetWindowPos(
            hwnd,
            HWND_TOPMOST,
            0,
            0,
            0,
            0,
            SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE,
        );
        if dock_right {
            let sw = GetSystemMetrics(SM_CXSCREEN);
            let sh = GetSystemMetrics(SM_CYSCREEN);
            let mut rect = RECT::default();
            if GetWindowRect(hwnd, &mut rect).is_ok() {
                let w = rect.right - rect.left;
                let h = rect.bottom - rect.top;
                let x = sw - w - 8;
                let y = (sh - h) / 2;
                let _ = SetWindowPos(
                    hwnd,
                    HWND_TOPMOST,
                    x,
                    y,
                    w,
                    h,
                    SWP_NOACTIVATE,
                );
            }
        }
    }
}

#[cfg(not(windows))]
pub fn fixup_panel_window(_title: &str, _dock_right: bool) {}

// MARK: - 中文字体(egui 默认字库无 CJK,优先微软雅黑)

#[cfg(windows)]
pub fn load_cjk_font() -> Option<Vec<u8>> {
    const CANDIDATES: [&str; 4] = ["msyh.ttc", "Deng.ttf", "simhei.ttf", "simsun.ttc"];
    for f in CANDIDATES {
        if let Ok(bytes) = std::fs::read(format!("C:\\Windows\\Fonts\\{f}")) {
            return Some(bytes);
        }
    }
    None
}

#[cfg(not(windows))]
pub fn load_cjk_font() -> Option<Vec<u8>> {
    None
}
