# sidedock-keys.ps1 — 常驻按键模拟服务:stdin 逐行读命令,收到即模拟按键
# 命令:KEY <2位16进制VK>  /  PASTE(向前台应用 Ctrl+V)
# 对应 Rust 版 platform.rs 的 SendInput(send_paste / send_media_key)
# 常驻进程避免每次按键重新启动 PowerShell(启动延迟约 0.5-1s)
$ErrorActionPreference = 'SilentlyContinue'
$sig = @"
using System;
using System.Runtime.InteropServices;
public static class Kb {
  [DllImport("user32.dll")] public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtra);
}
"@
Add-Type -TypeDefinition $sig

function Send-Vk([byte]$vk) {
    [Kb]::keybd_event($vk, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 25
    [Kb]::keybd_event($vk, 0, 2, [UIntPtr]::Zero)
}

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Write-Output 'READY'
while ($true) {
    $line = [Console]::In.ReadLine()
    if ($null -eq $line) { break }
    if ($line -match '^KEY ([0-9A-Fa-f]{2})$') {
        Send-Vk ([Convert]::ToByte($Matches[1], 16))
    }
    elseif ($line -eq 'PASTE') {
        # Ctrl 按下 → V 按下抬起 → Ctrl 抬起(Rust 版 send_key_combo 同序)
        [Kb]::keybd_event(0x11, 0, 0, [UIntPtr]::Zero)
        Start-Sleep -Milliseconds 30
        Send-Vk 0x56
        Start-Sleep -Milliseconds 30
        [Kb]::keybd_event(0x11, 0, 2, [UIntPtr]::Zero)
    }
}
