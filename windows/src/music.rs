// music.rs — 正在播放(Windows SMTC:GlobalSystemMediaTransportControlsSession 轮询)
// macOS 版走 MediaRemote;Windows 公开 API 无跨应用控制命令,
// 播放/上下曲通过模拟媒体键(send_media_key)实现
use serde::{Deserialize, Serialize};
use std::sync::{Arc, Mutex};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MusicSnapshot {
    pub title: String,
    pub artist: String,
    pub duration_secs: f64,
    pub position_secs: f64,
    pub playing: bool,
    #[serde(skip)]
    pub art: Option<(u32, u32, Vec<u8>)>, // rgba(缩略图,已缩放)
    pub taken_at_secs: f64, // std::time::UNIX_EPOCH 起秒,用于位置插值
}

impl MusicSnapshot {
    pub fn display_position(&self, now_secs: f64) -> f64 {
        if self.playing {
            let p = self.position_secs + (now_secs - self.taken_at_secs).max(0.0);
            if self.duration_secs > 0.0 {
                p.min(self.duration_secs)
            } else {
                p
            }
        } else {
            self.position_secs
        }
    }
}

#[derive(Clone)]
pub struct MusicController {
    shared: Arc<Mutex<Option<MusicSnapshot>>>,
}

impl MusicController {
    pub fn new() -> Self {
        let shared = Arc::new(Mutex::new(None));
        spawn_worker(shared.clone());
        MusicController { shared }
    }

    pub fn snapshot(&self) -> Option<MusicSnapshot> {
        self.shared.lock().ok().and_then(|g| g.clone())
    }

    pub fn control(&self, key: crate::platform::MediaKey) {
        crate::platform::send_media_key(key);
    }
}

impl Default for MusicController {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(windows)]
fn spawn_worker(shared: Arc<Mutex<Option<MusicSnapshot>>>) {
    std::thread::spawn(move || {
        use windows::Win32::System::Com::{CoInitializeEx, COINIT_MULTITHREADED};
        unsafe {
            // WinRT 需要线程初始化 COM(MTA 即可)
            let _ = CoInitializeEx(None, COINIT_MULTITHREADED);
        }
        loop {
            std::thread::sleep(std::time::Duration::from_secs(3));
            let snap = poll_smtc();
            if let Ok(mut g) = shared.lock() {
                *g = snap;
            }
        }
    });
}

#[cfg(not(windows))]
fn spawn_worker(_shared: Arc<Mutex<Option<MusicSnapshot>>>) {}

// MARK: - SMTC 轮询(仅 Windows)

#[cfg(windows)]
fn poll_smtc() -> Option<MusicSnapshot> {
    use windows::Foundation::TimeSpan;
    use windows::Media::Control::{
        GlobalSystemMediaTransportControlsSessionManager,
        GlobalSystemMediaTransportControlsSessionPlaybackStatus,
    };

    unsafe {
        let mgr = GlobalSystemMediaTransportControlsSessionManager::RequestAsync()
            .ok()?
            .get()
            .ok()?;
        let session = mgr.GetCurrentSession().ok()?;

        let props = session.TryGetMediaPropertiesAsync().ok()?.get().ok()?;
        let title = props.Title().ok()?.to_string_lossy().to_string();
        let artist = props.Artist().ok()?.to_string_lossy().to_string();
        if title.is_empty() && artist.is_empty() {
            return None;
        }

        let playback = session.GetPlaybackInfo().ok()?;
        let status = playback.PlaybackStatus().ok()?;
        let playing = status == GlobalSystemMediaTransportControlsSessionPlaybackStatus::Playing;

        let timeline = session.GetTimelineProperties().ok()?;
        let to_secs = |t: TimeSpan| t.Duration as f64 / 1e7;
        let position_secs = to_secs(timeline.Position().ok()?);
        let duration_secs = to_secs(timeline.EndTime().ok()?);

        let art = thumbnail_rgba(&props);

        Some(MusicSnapshot {
            title,
            artist,
            duration_secs,
            position_secs,
            playing,
            art,
            taken_at_secs: std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .map(|d| d.as_secs_f64())
                .unwrap_or(0.0),
        })
    }
}

/// 缩略图:RandomAccessStreamReference → DataReader 读字节 → 解码并缩到 104×104
#[cfg(windows)]
fn thumbnail_rgba(
    props: &windows::Media::Control::GlobalSystemMediaTransportControlsSessionMediaProperties,
) -> Option<(u32, u32, Vec<u8>)> {
    use windows::Storage::Streams::DataReader;

    let stream_ref = props.Thumbnail().ok()?;
    let stream = stream_ref.OpenReadAsync().ok()?.get().ok()?;
    let size = stream.Size().ok()? as u32;
    if size == 0 || size > 8 * 1024 * 1024 {
        return None;
    }
    use windows::core::Interface;
    let input: windows::Storage::Streams::IInputStream = stream.cast().ok()?;
    let reader = DataReader::CreateDataReader(&input).ok()?;
    reader.LoadAsync(size).ok()?.get().ok()?;
    let mut bytes = vec![0u8; size as usize];
    reader.ReadBytes(&mut bytes).ok()?;
    let img = image::load_from_memory(&bytes).ok()?;
    let img = img.resize(104, 104, image::imageops::FilterType::Triangle);
    let rgba = img.to_rgba8();
    Some((rgba.width(), rgba.height(), rgba.into_raw()))
}
