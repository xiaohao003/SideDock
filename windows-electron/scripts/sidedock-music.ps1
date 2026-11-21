# sidedock-music.ps1 — SMTC(系统媒体传输控制)轮询 → 每次输出一行 JSON
# 对应 Rust 版 music.rs:GlobalSystemMediaTransportControlsSessionManager 轮询,
# 封面缩到 104px 内,base64 PNG;无会话/无标题时输出 NONE
# 运行环境:Windows PowerShell 5.1(WinRT 投影 + System.Runtime.WindowsRuntime)
$ErrorActionPreference = 'SilentlyContinue'
Add-Type -AssemblyName System.Runtime.WindowsRuntime
Add-Type -AssemblyName System.Drawing
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# WinRT IAsyncOperation → 同步等待(PS 5 反射 AsTask)
$asTaskGeneric = ([System.WindowsRuntimeSystemExtensions].GetMethods() |
    Where-Object { $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' })[0]
function Await($WinRtTask, $ResultType) {
    $asTask = $asTaskGeneric.MakeGenericMethod($ResultType)
    $netTask = $asTask.Invoke($null, @($WinRtTask))
    $netTask.Wait(-1) | Out-Null
    $netTask.Result
}

$manager = Await ([Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager]::RequestAsync()) ([Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager])

$lastKey = ''
while ($true) {
    Start-Sleep -Seconds 2
    try {
        $s = $manager.GetCurrentSession()
        if ($null -eq $s) { if ($lastKey -ne 'NONE') { $lastKey = 'NONE'; Write-Output 'NONE' }; continue }

        $props = Await ($s.TryGetMediaPropertiesAsync()) ([Windows.Media.Control.GlobalSystemMediaTransportControlsSessionMediaProperties])
        $title = $props.Title
        $artist = $props.Artist
        if (-not $title -and -not $artist) { if ($lastKey -ne 'NONE') { $lastKey = 'NONE'; Write-Output 'NONE' }; continue }

        $playing = $false
        try {
            $pb = $s.GetPlaybackInfo()
            $playing = ($pb.PlaybackStatus -eq [Windows.Media.Control.GlobalSystemMediaTransportControlsSessionPlaybackStatus]::Playing)
        } catch {}

        $pos = 0.0; $dur = 0.0
        try {
            $tl = $s.GetTimelineProperties()
            $pos = $tl.Position.TotalSeconds
            $dur = $tl.EndTime.TotalSeconds
        } catch {}

        # 封面只在曲目变化时解码(避免每 2s 重复解码)
        $key = "$title|$artist"
        $artB64 = ''
        if ($key -ne $lastKey) {
            try {
                $ref = $props.Thumbnail
                if ($ref) {
                    $stream = Await ($ref.OpenReadAsync()) ([Windows.Storage.Streams.IRandomAccessStreamWithContentType])
                    if ($stream -and $stream.Size -gt 0 -and $stream.Size -lt 8388608) {
                        $input = $stream.GetInputStreamAt(0)
                        $reader = New-Object Windows.Storage.Streams.DataReader($input)
                        Await ($reader.LoadAsync([UInt32]$stream.Size)) ([System.UInt32]) | Out-Null
                        $bytes = New-Object byte[] $stream.Size
                        $reader.ReadBytes($bytes)
                        $ms = New-Object System.IO.MemoryStream (,$bytes)
                        $bmp = [System.Drawing.Image]::FromStream($ms)
                        if ($bmp) {
                            $w = 104; $h = [int](104 * $bmp.Height / $bmp.Width)
                            if ($h -lt 1) { $h = 104 }
                            if ($h -gt 104) { $h = 104; $w = [int](104 * $bmp.Width / $bmp.Height) }
                            if ($w -lt 1) { $w = 104 }
                            $thumb = New-Object System.Drawing.Bitmap ($w, $h)
                            $g = [System.Drawing.Graphics]::FromImage($thumb)
                            $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
                            $g.DrawImage($bmp, 0, 0, $w, $h)
                            $ms2 = New-Object System.IO.MemoryStream
                            $thumb.Save($ms2, [System.Drawing.Imaging.ImageFormat]::Png)
                            $artB64 = [Convert]::ToBase64String($ms2.ToArray())
                            $g.Dispose(); $thumb.Dispose(); $bmp.Dispose(); $ms2.Dispose(); $ms.Dispose()
                        }
                    }
                }
            } catch { $artB64 = '' }
            $lastKey = $key
        }

        $taken = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() / 1000.0
        $obj = [ordered]@{
            title         = "$title"
            artist        = "$artist"
            duration_secs = $dur
            position_secs = $pos
            playing       = [bool]$playing
            taken_at_secs = $taken
            art_b64       = $artB64
        }
        Write-Output (ConvertTo-Json -Compress -InputObject $obj)
    } catch {
        Start-Sleep -Seconds 2
    }
}
