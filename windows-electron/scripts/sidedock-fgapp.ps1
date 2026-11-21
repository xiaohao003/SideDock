# sidedock-fgapp.ps1 — 输出当前前台应用进程名(一次性;剪贴板记录来源用)
# 对应 Rust 版 platform.rs foreground_app():GetForegroundWindow → 进程名
$ErrorActionPreference = 'SilentlyContinue'
$sig = @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class Fg {
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);
  [DllImport("kernel32.dll")] public static extern IntPtr OpenProcess(uint access, bool inherit, uint pid);
  [DllImport("kernel32.dll")] public static extern bool CloseHandle(IntPtr h);
  [DllImport("kernel32.dll", CharSet=CharSet.Unicode)] public static extern uint QueryFullProcessImageNameW(IntPtr h, uint flags, StringBuilder name, ref uint len);
}
"@
Add-Type -TypeDefinition $sig

$h = [Fg]::GetForegroundWindow()
if ($h -eq [IntPtr]::Zero) { exit }
$pid2 = 0
[void][Fg]::GetWindowThreadProcessId($h, [ref]$pid2)
if ($pid2 -eq 0) { exit }
$proc = [Fg]::OpenProcess(0x1000, $false, $pid2) # PROCESS_QUERY_LIMITED_INFORMATION
if ($proc -eq [IntPtr]::Zero) { exit }
$sb = New-Object System.Text.StringBuilder 1024
$len = [UInt32]1024
if ([Fg]::QueryFullProcessImageNameW($proc, 0, $sb, [ref]$len)) {
    $exe = [System.IO.Path]::GetFileNameWithoutExtension($sb.ToString())
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    Write-Output $exe
}
[void][Fg]::CloseHandle($proc)
