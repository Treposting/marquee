//! The few clipboard and focus calls that need the operating system directly. On Windows they
//! use Win32; elsewhere (when running the app on a Mac for UI work) they do the simplest thing.

use marquee_core::clip::SourceApp;

/// A number that changes every time anything is copied, so watching it is cheap.
#[cfg(windows)]
pub fn clipboard_sequence() -> u32 {
    // SAFETY: no arguments, no preconditions.
    unsafe { windows_sys::Win32::System::DataExchange::GetClipboardSequenceNumber() }
}

/// Elsewhere there's no counter; a hash of the text stands in for one.
#[cfg(not(windows))]
pub fn clipboard_sequence() -> u32 {
    use std::hash::{Hash, Hasher};
    let text = arboard::Clipboard::new().and_then(|mut c| c.get_text()).unwrap_or_default();
    let mut h = std::collections::hash_map::DefaultHasher::new();
    text.hash(&mut h);
    h.finish() as u32
}

/// Whether the app that copied asked to keep it out of clipboard history and clipboard
/// managers, as password managers do (the formats Windows' own clipboard history honors).
#[cfg(windows)]
pub fn is_private() -> bool {
    use windows_sys::Win32::System::DataExchange::{
        CloseClipboard, GetClipboardData, IsClipboardFormatAvailable, OpenClipboard, RegisterClipboardFormatW,
    };
    use windows_sys::Win32::System::Memory::{GlobalLock, GlobalUnlock};

    let format = |name: &str| {
        let wide: Vec<u16> = name.encode_utf16().chain(Some(0)).collect();
        // SAFETY: a NUL-terminated UTF-16 string.
        unsafe { RegisterClipboardFormatW(wide.as_ptr()) }
    };
    // SAFETY: plain queries; the clipboard is opened and closed around the one read, and the
    // locked memory is only read while locked.
    unsafe {
        for name in ["ExcludeClipboardContentFromMonitorProcessing", "Clipboard Viewer Ignore"] {
            if IsClipboardFormatAvailable(format(name)) != 0 {
                return true;
            }
        }
        // CanIncludeInClipboardHistory holds a DWORD; 0 means "keep me out of history".
        let can_include = format("CanIncludeInClipboardHistory");
        if IsClipboardFormatAvailable(can_include) == 0 || OpenClipboard(std::ptr::null_mut()) == 0 {
            return false;
        }
        let mut private = false;
        let handle = GetClipboardData(can_include);
        if !handle.is_null() {
            let data = GlobalLock(handle) as *const u32;
            if !data.is_null() {
                private = *data == 0;
                GlobalUnlock(handle);
            }
        }
        CloseClipboard();
        private
    }
}

#[cfg(not(windows))]
pub fn is_private() -> bool {
    false
}

/// The app that put the current content on the clipboard (or, failing that, the app in front),
/// by executable: "notepad.exe" shows as "Notepad".
#[cfg(windows)]
pub fn source_app() -> Option<SourceApp> {
    use windows_sys::Win32::Foundation::CloseHandle;
    use windows_sys::Win32::System::DataExchange::GetClipboardOwner;
    use windows_sys::Win32::System::Threading::{
        OpenProcess, QueryFullProcessImageNameW, PROCESS_NAME_WIN32, PROCESS_QUERY_LIMITED_INFORMATION,
    };
    use windows_sys::Win32::UI::WindowsAndMessaging::{GetForegroundWindow, GetWindowThreadProcessId};

    // SAFETY: plain queries with valid out-pointers; the process handle is closed.
    unsafe {
        let mut hwnd = GetClipboardOwner();
        if hwnd.is_null() {
            hwnd = GetForegroundWindow();
        }
        let mut pid = 0u32;
        GetWindowThreadProcessId(hwnd, &mut pid);
        if pid == 0 || pid == std::process::id() {
            return None;
        }
        let process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, 0, pid);
        if process.is_null() {
            return None;
        }
        let mut buffer = [0u16; 1024];
        let mut len = buffer.len() as u32;
        let ok = QueryFullProcessImageNameW(process, PROCESS_NAME_WIN32, buffer.as_mut_ptr(), &mut len);
        CloseHandle(process);
        if ok == 0 {
            return None;
        }
        let path = String::from_utf16_lossy(&buffer[..len as usize]);
        let exe = path.rsplit(['\\', '/']).next()?.to_string();
        Some(SourceApp { name: marquee_core::clip::app_display_name(&exe), id: exe })
    }
}

#[cfg(not(windows))]
pub fn source_app() -> Option<SourceApp> {
    None
}

/// The window in front, to return to after the clipboard panel closes.
#[cfg(windows)]
pub fn foreground_window() -> isize {
    // SAFETY: no arguments, no preconditions.
    unsafe { windows_sys::Win32::UI::WindowsAndMessaging::GetForegroundWindow() as isize }
}

#[cfg(not(windows))]
pub fn foreground_window() -> isize {
    0
}

/// Brings back the window that was in front and presses Ctrl+V in it.
#[cfg(windows)]
pub fn paste_into(window: isize) {
    use windows_sys::Win32::UI::Input::KeyboardAndMouse::{
        SendInput, INPUT, INPUT_0, INPUT_KEYBOARD, KEYBDINPUT, KEYEVENTF_KEYUP, VK_CONTROL,
    };
    use windows_sys::Win32::UI::WindowsAndMessaging::SetForegroundWindow;

    const VK_V: u16 = 0x56;
    let key = |vk: u16, up: bool| INPUT {
        r#type: INPUT_KEYBOARD,
        Anonymous: INPUT_0 {
            ki: KEYBDINPUT {
                wVk: vk,
                wScan: 0,
                dwFlags: if up { KEYEVENTF_KEYUP } else { 0 },
                time: 0,
                dwExtraInfo: 0,
            },
        },
    };
    // SAFETY: a window handle we got from Windows (it may be gone, which is harmless), and an
    // array of fully initialized inputs.
    unsafe {
        if window != 0 {
            SetForegroundWindow(window as _);
        }
        std::thread::sleep(std::time::Duration::from_millis(90));
        let inputs = [key(VK_CONTROL, false), key(VK_V, false), key(VK_V, true), key(VK_CONTROL, true)];
        SendInput(inputs.len() as u32, inputs.as_ptr(), std::mem::size_of::<INPUT>() as i32);
    }
}

#[cfg(not(windows))]
pub fn paste_into(_window: isize) {}
