//! GET /api/file/metadata?path= — per-file media metadata (by absolute path).
//! Optional fields are omitted from JSON when absent so clients can hide missing rows.

use actix_web::{web, HttpResponse, Result};
use serde::Serialize;
use serde_json::Value;
use std::collections::HashMap;
use std::fs;
use std::io::{Cursor, Read, Seek, SeekFrom};
use std::path::{Path, PathBuf};
use std::process::Command;

use super::models::{FileType, GIF_EXTENSION, IMAGE_EXTENSIONS, VIDEO_EXTENSIONS};

/// GPS coordinates (decimal degrees; south/west negative).
#[derive(Debug, Clone, Serialize, PartialEq)]
pub struct GpsCoords {
    pub lat: f64,
    pub lon: f64,
}

/// Rich file metadata response. Absent Option fields are skipped in JSON.
#[derive(Debug, Clone, Serialize, PartialEq)]
pub struct FileMetadata {
    pub path: String,
    pub filename: String,
    pub format: String,
    pub size: u64,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub file_type: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub width: Option<u32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub height: Option<u32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub duration: Option<f64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub capture_time: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub gps: Option<GpsCoords>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub created: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub modified: Option<String>,
}

/// GET /api/file/metadata?path=<abs>
pub async fn get_file_metadata(
    query: web::Query<HashMap<String, String>>,
) -> Result<HttpResponse> {
    let path_str = query
        .get("path")
        .ok_or_else(|| actix_web::error::ErrorBadRequest("缺少 path 参数"))?;

    let path = Path::new(path_str);
    if !path.exists() || !path.is_file() {
        return Err(actix_web::error::ErrorNotFound("文件不存在"));
    }

    let meta = extract_metadata(path)
        .map_err(|e| actix_web::error::ErrorInternalServerError(e))?;
    Ok(HttpResponse::Ok().json(meta))
}

/// Extract metadata for a file on disk. Public for unit tests.
pub fn extract_metadata(path: &Path) -> std::result::Result<FileMetadata, String> {
    let metadata = fs::metadata(path).map_err(|e| format!("无法读取文件元数据: {e}"))?;
    if !metadata.is_file() {
        return Err("路径不是文件".into());
    }

    let filename = path
        .file_name()
        .and_then(|n| n.to_str())
        .unwrap_or("")
        .to_string();

    let extension = path
        .extension()
        .and_then(|e| e.to_str())
        .unwrap_or("")
        .to_lowercase();

    let format = format_label(&extension, &filename);
    let file_type = classify_file_type(&extension);

    let created = system_time_string(metadata.created().ok());
    let modified = system_time_string(metadata.modified().ok());

    let mut width: Option<u32> = None;
    let mut height: Option<u32> = None;
    let mut duration: Option<f64> = None;
    let mut capture_time: Option<String> = None;
    let mut gps: Option<GpsCoords> = None;

    // Raster images (JPEG/PNG/…) via `image` crate — also feeds EXIF for JPEG.
    if matches!(
        extension.as_str(),
        "jpg" | "jpeg" | "png" | "webp" | "bmp" | "tiff" | "tif" | "gif"
    ) {
        if let Ok(img) = image::image_dimensions(path) {
            width = Some(img.0);
            height = Some(img.1);
        }
        if matches!(extension.as_str(), "jpg" | "jpeg") {
            if let Ok(bytes) = fs::read(path) {
                if let Some(exif) = parse_jpeg_exif(&bytes) {
                    if capture_time.is_none() {
                        capture_time = exif.capture_time;
                    }
                    if gps.is_none() {
                        gps = exif.gps;
                    }
                }
            }
        }
    }

    // HEIC / video / anything still missing dims → ffprobe
    let needs_probe = matches!(
        extension.as_str(),
        "heic" | "heif" | "avif" | "mp4" | "mov" | "m4v" | "avi" | "mkv" | "webm" | "flv" | "wmv"
    ) || width.is_none()
        || height.is_none()
        || (file_type == Some(FileType::Video) && duration.is_none());

    if needs_probe {
        if let Some(probe) = probe_with_ffprobe(path) {
            if width.is_none() {
                width = probe.width;
            }
            if height.is_none() {
                height = probe.height;
            }
            if duration.is_none() {
                duration = probe.duration.filter(|d| *d > 0.0);
            }
            if capture_time.is_none() {
                capture_time = probe.capture_time;
            }
            if gps.is_none() {
                gps = probe.gps;
            }
        }
    }

    // HEIC / HEIF EXIF often invisible to ffprobe — try exiftool when present.
    if matches!(extension.as_str(), "heic" | "heif" | "avif")
        && (capture_time.is_none() || gps.is_none())
    {
        if let Some(et) = probe_with_exiftool(path) {
            if capture_time.is_none() {
                capture_time = et.capture_time;
            }
            if gps.is_none() {
                gps = et.gps;
            }
            if width.is_none() {
                width = et.width;
            }
            if height.is_none() {
                height = et.height;
            }
        }
    }

    Ok(FileMetadata {
        path: path.to_string_lossy().to_string(),
        filename,
        format,
        size: metadata.len(),
        file_type: file_type.map(|t| match t {
            FileType::Image => "image".into(),
            FileType::Video => "video".into(),
            FileType::Gif => "gif".into(),
            FileType::Other => "other".into(),
        }),
        width,
        height,
        duration,
        capture_time,
        gps,
        created,
        modified,
    })
}

fn format_label(extension: &str, filename: &str) -> String {
    if extension.is_empty() {
        return filename.to_string();
    }
    match extension {
        "jpg" | "jpeg" => "JPEG".into(),
        "png" => "PNG".into(),
        "gif" => "GIF".into(),
        "webp" => "WebP".into(),
        "heic" => "HEIC".into(),
        "heif" => "HEIF".into(),
        "avif" => "AVIF".into(),
        "mp4" => "MP4".into(),
        "mov" => "MOV".into(),
        "m4v" => "M4V".into(),
        "mkv" => "MKV".into(),
        "webm" => "WebM".into(),
        "pdf" => "PDF".into(),
        other => other.to_uppercase(),
    }
}

fn classify_file_type(extension: &str) -> Option<FileType> {
    if extension == GIF_EXTENSION {
        Some(FileType::Gif)
    } else if IMAGE_EXTENSIONS.contains(&extension)
        || matches!(extension, "heic" | "heif" | "avif")
    {
        Some(FileType::Image)
    } else if VIDEO_EXTENSIONS.contains(&extension) {
        Some(FileType::Video)
    } else {
        Some(FileType::Other)
    }
}

fn system_time_string(t: Option<std::time::SystemTime>) -> Option<String> {
    let t = t?;
    let d = t.duration_since(std::time::UNIX_EPOCH).ok()?;
    let datetime = chrono::DateTime::<chrono::Utc>::from_timestamp(d.as_secs() as i64, 0)?;
    Some(datetime.format("%Y-%m-%d %H:%M:%S").to_string())
}

#[derive(Debug, Default)]
struct ProbeFields {
    width: Option<u32>,
    height: Option<u32>,
    duration: Option<f64>,
    capture_time: Option<String>,
    gps: Option<GpsCoords>,
}

fn probe_with_ffprobe(path: &Path) -> Option<ProbeFields> {
    let ffprobe = crate::preview::utils::get_ffprobe_path();
    let output = Command::new(&ffprobe)
        .args([
            "-v",
            "quiet",
            "-print_format",
            "json",
            "-show_format",
            "-show_streams",
        ])
        .arg(path)
        .output()
        .ok()?;
    if !output.status.success() {
        return None;
    }
    let json: Value = serde_json::from_slice(&output.stdout).ok()?;
    Some(parse_ffprobe_json(&json))
}

fn parse_ffprobe_json(json: &Value) -> ProbeFields {
    let mut out = ProbeFields::default();

    if let Some(streams) = json.get("streams").and_then(|s| s.as_array()) {
        for stream in streams {
            if stream.get("codec_type").and_then(|v| v.as_str()) != Some("video") {
                continue;
            }
            if out.width.is_none() {
                out.width = stream.get("width").and_then(|v| v.as_u64()).map(|v| v as u32);
            }
            if out.height.is_none() {
                out.height = stream
                    .get("height")
                    .and_then(|v| v.as_u64())
                    .map(|v| v as u32);
            }
            if let Some(tags) = stream.get("tags") {
                merge_tags_into(&mut out, tags);
            }
            if out.width.is_some() && out.height.is_some() {
                break;
            }
        }
    }

    if let Some(format) = json.get("format") {
        if out.duration.is_none() {
            if let Some(d) = format
                .get("duration")
                .and_then(|v| v.as_str())
                .and_then(|s| s.parse::<f64>().ok())
            {
                out.duration = Some(d);
            }
        }
        if let Some(tags) = format.get("tags") {
            merge_tags_into(&mut out, tags);
        }
    }

    out
}

fn merge_tags_into(out: &mut ProbeFields, tags: &Value) {
    if out.capture_time.is_none() {
        for key in [
            "DateTimeOriginal",
            "creation_time",
            "com.apple.quicktime.creationdate",
            "CreationDate",
        ] {
            if let Some(v) = tags.get(key).and_then(|v| v.as_str()) {
                let normalized = normalize_capture_time(v);
                if !normalized.is_empty() {
                    out.capture_time = Some(normalized);
                    break;
                }
            }
        }
    }
    if out.gps.is_none() {
        for key in ["location", "location-eng", "com.apple.quicktime.location.ISO6709"] {
            if let Some(v) = tags.get(key).and_then(|v| v.as_str()) {
                if let Some(gps) = parse_iso6709(v) {
                    out.gps = Some(gps);
                    break;
                }
            }
        }
    }
}

/// Normalize EXIF / ISO8601 capture times to `YYYY-MM-DD HH:MM:SS`.
fn normalize_capture_time(raw: &str) -> String {
    let s = raw.trim();
    if s.is_empty() {
        return String::new();
    }
    // EXIF: "2024:06:15 14:32:01"
    if s.len() >= 19 && s.as_bytes().get(4) == Some(&b':') {
        let mut chars: Vec<u8> = s.as_bytes()[..19].to_vec();
        if chars.get(4) == Some(&b':') {
            chars[4] = b'-';
        }
        if chars.get(7) == Some(&b':') {
            chars[7] = b'-';
        }
        return String::from_utf8_lossy(&chars).to_string();
    }
    // ISO8601: 2024-06-15T14:32:01Z / with fractional seconds
    if let Some(t_pos) = s.find('T') {
        let date = &s[..t_pos];
        let rest = &s[t_pos + 1..];
        let time = rest
            .split(|c| c == '.' || c == 'Z' || c == '+' || c == '-')
            .next()
            .unwrap_or(rest);
        let time = if time.len() >= 8 { &time[..8] } else { time };
        return format!("{date} {time}");
    }
    s.to_string()
}

/// Parse ISO6709 like `-33.8688+151.2093/` or `+37.7749-122.4194/`.
fn parse_iso6709(raw: &str) -> Option<GpsCoords> {
    let s = raw.trim().trim_end_matches('/');
    if s.is_empty() {
        return None;
    }
    // Find second sign (start of longitude)
    let bytes = s.as_bytes();
    let mut second_sign = None;
    for (i, &b) in bytes.iter().enumerate().skip(1) {
        if b == b'+' || b == b'-' {
            second_sign = Some(i);
            break;
        }
    }
    let i = second_sign?;
    let lat: f64 = s[..i].parse().ok()?;
    let lon_part = &s[i..];
    let lon_end = lon_part
        .find(|c: char| c == '/' || c == '+')
        .filter(|&p| p > 0)
        .unwrap_or(lon_part.len());
    // longitude may be followed by altitude (+alt)
    let lon_str = if let Some(alt_at) = lon_part[1..].find(['+', '-']) {
        &lon_part[..alt_at + 1]
    } else {
        &lon_part[..lon_end.min(lon_part.len())]
    };
    let lon: f64 = lon_str.parse().ok()?;
    if !(-90.0..=90.0).contains(&lat) || !(-180.0..=180.0).contains(&lon) {
        return None;
    }
    Some(GpsCoords { lat, lon })
}

fn probe_with_exiftool(path: &Path) -> Option<ProbeFields> {
    let exiftool = which_exiftool()?;
    let output = Command::new(exiftool)
        .args([
            "-j",
            "-n",
            "-DateTimeOriginal",
            "-CreateDate",
            "-GPSLatitude",
            "-GPSLongitude",
            "-ImageWidth",
            "-ImageHeight",
        ])
        .arg(path)
        .output()
        .ok()?;
    if !output.status.success() {
        return None;
    }
    let arr: Value = serde_json::from_slice(&output.stdout).ok()?;
    let obj = arr.as_array()?.first()?;
    let mut out = ProbeFields::default();
    if let Some(v) = obj.get("DateTimeOriginal").or_else(|| obj.get("CreateDate")) {
        if let Some(s) = v.as_str() {
            let n = normalize_capture_time(s);
            if !n.is_empty() {
                out.capture_time = Some(n);
            }
        }
    }
    let lat = obj.get("GPSLatitude").and_then(|v| v.as_f64());
    let lon = obj.get("GPSLongitude").and_then(|v| v.as_f64());
    if let (Some(lat), Some(lon)) = (lat, lon) {
        out.gps = Some(GpsCoords { lat, lon });
    }
    out.width = obj
        .get("ImageWidth")
        .and_then(|v| v.as_u64())
        .map(|v| v as u32);
    out.height = obj
        .get("ImageHeight")
        .and_then(|v| v.as_u64())
        .map(|v| v as u32);
    Some(out)
}

fn which_exiftool() -> Option<PathBuf> {
    if let Ok(p) = which_in_path("exiftool") {
        return Some(p);
    }
    let candidates = [
        "/opt/homebrew/bin/exiftool",
        "/usr/local/bin/exiftool",
        "/usr/bin/exiftool",
    ];
    candidates
        .iter()
        .map(PathBuf::from)
        .find(|p| p.is_file())
}

fn which_in_path(name: &str) -> std::io::Result<PathBuf> {
    let path = std::env::var_os("PATH").ok_or(std::io::Error::from(std::io::ErrorKind::NotFound))?;
    for dir in std::env::split_paths(&path) {
        let candidate = dir.join(name);
        if candidate.is_file() {
            return Ok(candidate);
        }
    }
    Err(std::io::Error::from(std::io::ErrorKind::NotFound))
}

// ── Minimal JPEG EXIF reader (DateTimeOriginal + GPS) ──────────────────────

#[derive(Debug, Default)]
struct JpegExif {
    capture_time: Option<String>,
    gps: Option<GpsCoords>,
}

fn parse_jpeg_exif(data: &[u8]) -> Option<JpegExif> {
    if data.len() < 4 || data[0] != 0xFF || data[1] != 0xD8 {
        return None;
    }
    let mut i = 2usize;
    while i + 4 < data.len() {
        if data[i] != 0xFF {
            i += 1;
            continue;
        }
        let marker = data[i + 1];
        if marker == 0xD9 || marker == 0xDA {
            break;
        }
        if i + 4 > data.len() {
            break;
        }
        let len = u16::from_be_bytes([data[i + 2], data[i + 3]]) as usize;
        if len < 2 || i + 2 + len > data.len() {
            break;
        }
        let segment = &data[i + 4..i + 2 + len];
        if marker == 0xE1 && segment.starts_with(b"Exif\0\0") {
            return parse_exif_tiff(&segment[6..]);
        }
        i += 2 + len;
    }
    None
}

fn parse_exif_tiff(tiff: &[u8]) -> Option<JpegExif> {
    if tiff.len() < 8 {
        return None;
    }
    let le = match &tiff[0..2] {
        b"II" => true,
        b"MM" => false,
        _ => return None,
    };
    let read_u16 = |off: usize| -> Option<u16> {
        let b = tiff.get(off..off + 2)?;
        Some(if le {
            u16::from_le_bytes([b[0], b[1]])
        } else {
            u16::from_be_bytes([b[0], b[1]])
        })
    };
    let read_u32 = |off: usize| -> Option<u32> {
        let b = tiff.get(off..off + 4)?;
        Some(if le {
            u32::from_le_bytes([b[0], b[1], b[2], b[3]])
        } else {
            u32::from_be_bytes([b[0], b[1], b[2], b[3]])
        })
    };

    let ifd0 = read_u32(4)? as usize;
    let mut out = JpegExif::default();

    // IFD0 → ExifIFD pointer (0x8769) and GPS IFD (0x8825)
    let (exif_ptr, gps_ptr) = read_ifd_pointers(tiff, ifd0, le, read_u16, read_u32)?;

    if let Some(exif_off) = exif_ptr {
        if let Some(dt) = read_ascii_tag(tiff, exif_off, le, 0x9003, read_u16, read_u32) {
            // DateTimeOriginal
            let n = normalize_capture_time(&dt);
            if !n.is_empty() {
                out.capture_time = Some(n);
            }
        }
        if out.capture_time.is_none() {
            if let Some(dt) = read_ascii_tag(tiff, exif_off, le, 0x9004, read_u16, read_u32) {
                let n = normalize_capture_time(&dt);
                if !n.is_empty() {
                    out.capture_time = Some(n);
                }
            }
        }
    }

    if let Some(gps_off) = gps_ptr {
        out.gps = read_gps_ifd(tiff, gps_off, le, read_u16, read_u32);
    }

    // IFD0 DateTime (0x0132) as last resort
    if out.capture_time.is_none() {
        if let Some(dt) = read_ascii_tag(tiff, ifd0, le, 0x0132, read_u16, read_u32) {
            let n = normalize_capture_time(&dt);
            if !n.is_empty() {
                out.capture_time = Some(n);
            }
        }
    }

    Some(out)
}

fn read_ifd_pointers(
    _tiff: &[u8],
    ifd_off: usize,
    _le: bool,
    read_u16: impl Fn(usize) -> Option<u16>,
    read_u32: impl Fn(usize) -> Option<u32>,
) -> Option<(Option<usize>, Option<usize>)> {
    let count = read_u16(ifd_off)? as usize;
    let mut exif_ptr = None;
    let mut gps_ptr = None;
    for i in 0..count {
        let entry = ifd_off + 2 + i * 12;
        let tag = read_u16(entry)?;
        let typ = read_u16(entry + 2)?;
        let _count = read_u32(entry + 4)?;
        let val_or_off = read_u32(entry + 8)?;
        if tag == 0x8769 && typ == 4 {
            exif_ptr = Some(val_or_off as usize);
        }
        if tag == 0x8825 && typ == 4 {
            gps_ptr = Some(val_or_off as usize);
        }
    }
    Some((exif_ptr, gps_ptr))
}

fn read_ascii_tag(
    tiff: &[u8],
    ifd_off: usize,
    le: bool,
    want_tag: u16,
    read_u16: impl Fn(usize) -> Option<u16>,
    read_u32: impl Fn(usize) -> Option<u32>,
) -> Option<String> {
    let count = read_u16(ifd_off)? as usize;
    for i in 0..count {
        let entry = ifd_off + 2 + i * 12;
        let tag = read_u16(entry)?;
        if tag != want_tag {
            continue;
        }
        let typ = read_u16(entry + 2)?;
        let cnt = read_u32(entry + 4)? as usize;
        if typ != 2 || cnt == 0 {
            return None;
        }
        let data = if cnt <= 4 {
            &tiff[entry + 8..entry + 8 + cnt]
        } else {
            let off = read_u32(entry + 8)? as usize;
            tiff.get(off..off + cnt)?
        };
        let s = String::from_utf8_lossy(data)
            .trim_end_matches('\0')
            .trim()
            .to_string();
        let _ = le;
        return Some(s);
    }
    None
}

fn read_gps_ifd(
    tiff: &[u8],
    ifd_off: usize,
    le: bool,
    read_u16: impl Fn(usize) -> Option<u16>,
    read_u32: impl Fn(usize) -> Option<u32>,
) -> Option<GpsCoords> {
    let count = read_u16(ifd_off)? as usize;
    let mut lat_ref: Option<String> = None;
    let mut lon_ref: Option<String> = None;
    let mut lat: Option<f64> = None;
    let mut lon: Option<f64> = None;

    for i in 0..count {
        let entry = ifd_off + 2 + i * 12;
        let tag = read_u16(entry)?;
        let typ = read_u16(entry + 2)?;
        let cnt = read_u32(entry + 4)? as usize;
        match (tag, typ) {
            (1, 2) | (3, 2) if cnt > 0 => {
                let data = if cnt <= 4 {
                    tiff.get(entry + 8..entry + 8 + cnt)?
                } else {
                    let off = read_u32(entry + 8)? as usize;
                    tiff.get(off..off + cnt)?
                };
                let s = String::from_utf8_lossy(data)
                    .trim_end_matches('\0')
                    .to_string();
                if tag == 1 {
                    lat_ref = Some(s);
                } else {
                    lon_ref = Some(s);
                }
            }
            (2, 5) if cnt == 3 => {
                let off = read_u32(entry + 8)? as usize;
                lat = read_rational_dms(tiff, off, le);
            }
            (4, 5) if cnt == 3 => {
                let off = read_u32(entry + 8)? as usize;
                lon = read_rational_dms(tiff, off, le);
            }
            _ => {}
        }
    }

    let mut lat = lat?;
    let mut lon = lon?;
    if lat_ref.as_deref() == Some("S") {
        lat = -lat;
    }
    if lon_ref.as_deref() == Some("W") {
        lon = -lon;
    }
    Some(GpsCoords { lat, lon })
}

fn read_rational_dms(tiff: &[u8], off: usize, le: bool) -> Option<f64> {
    let read_u32 = |o: usize| -> Option<u32> {
        let b = tiff.get(o..o + 4)?;
        Some(if le {
            u32::from_le_bytes([b[0], b[1], b[2], b[3]])
        } else {
            u32::from_be_bytes([b[0], b[1], b[2], b[3]])
        })
    };
    let mut vals = [0.0f64; 3];
    for i in 0..3 {
        let num = read_u32(off + i * 8)? as f64;
        let den = read_u32(off + i * 8 + 4)? as f64;
        if den == 0.0 {
            return None;
        }
        vals[i] = num / den;
    }
    Some(vals[0] + vals[1] / 60.0 + vals[2] / 3600.0)
}

// silence unused import warnings for Cursor/Read/Seek used only in tests below
#[allow(dead_code)]
fn _keep_io_imports() {
    let mut c = Cursor::new(Vec::<u8>::new());
    let _ = c.seek(SeekFrom::Start(0));
    let mut buf = [0u8; 1];
    let _ = c.read(&mut buf);
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Write;
    use std::time::{SystemTime, UNIX_EPOCH};

    fn temp_path(label: &str) -> PathBuf {
        let nanos = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        std::env::temp_dir().join(format!("resourcer-meta-{}-{nanos}", label))
    }

    #[test]
    fn normalize_exif_and_iso_times() {
        assert_eq!(
            normalize_capture_time("2024:06:15 14:32:01"),
            "2024-06-15 14:32:01"
        );
        assert_eq!(
            normalize_capture_time("2024-06-15T14:32:01.000000Z"),
            "2024-06-15 14:32:01"
        );
    }

    #[test]
    fn parse_iso6709_lat_lon() {
        let g = parse_iso6709("-33.8688+151.2093/").unwrap();
        assert!((g.lat + 33.8688).abs() < 1e-6);
        assert!((g.lon - 151.2093).abs() < 1e-6);
        let g2 = parse_iso6709("+37.7749-122.4194/").unwrap();
        assert!((g2.lat - 37.7749).abs() < 1e-6);
        assert!((g2.lon + 122.4194).abs() < 1e-6);
    }

    #[test]
    fn extract_sparse_png_hides_optional_fields() {
        let dir = temp_path("sparse");
        fs::create_dir_all(&dir).unwrap();
        let path = dir.join("plain.png");
        // Minimal 1x1 PNG
        let png_1x1: &[u8] = &[
            0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48,
            0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x02, 0x00, 0x00,
            0x00, 0x90, 0x77, 0x53, 0xDE, 0x00, 0x00, 0x00, 0x0C, 0x49, 0x44, 0x41, 0x54, 0x08,
            0xD7, 0x63, 0xF8, 0xCF, 0xC0, 0x00, 0x00, 0x00, 0x03, 0x00, 0x01, 0x00, 0x05, 0xFE,
            0x02, 0xFE, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
        ];
        fs::write(&path, png_1x1).unwrap();
        let meta = extract_metadata(&path).unwrap();
        assert_eq!(meta.filename, "plain.png");
        assert_eq!(meta.format, "PNG");
        assert!(meta.gps.is_none());
        assert!(meta.capture_time.is_none());
        assert_eq!(meta.width, Some(1));
        assert_eq!(meta.height, Some(1));
        // JSON omits null optionals
        let json = serde_json::to_value(&meta).unwrap();
        assert!(json.get("gps").is_none());
        assert!(json.get("capture_time").is_none());
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn extract_jpeg_with_exif_gps_and_capture_time() {
        // Build a tiny JPEG via image crate then inject EXIF with a prebuilt APP1 from piexif dump
        // Prefer reading a fixture produced by the test harness when present.
        let fixture = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("tests/fixtures/meta_with_exif.jpg");
        let path = if fixture.is_file() {
            fixture
        } else {
            // Fallback: write plain JPEG (no EXIF) — still validates dims/format
            let dir = temp_path("jpg");
            fs::create_dir_all(&dir).unwrap();
            let path = dir.join("shot.jpg");
            let img = image::RgbImage::from_pixel(8, 6, image::Rgb([10, 20, 30]));
            img.save(&path).unwrap();
            let meta = extract_metadata(&path).unwrap();
            assert_eq!(meta.format, "JPEG");
            assert_eq!(meta.width, Some(8));
            assert_eq!(meta.height, Some(6));
            let _ = fs::remove_dir_all(&dir);
            return;
        };

        let meta = extract_metadata(&path).unwrap();
        assert_eq!(meta.format, "JPEG");
        assert!(meta.width.is_some());
        assert!(meta.height.is_some());
        assert!(
            meta.capture_time.is_some(),
            "expected capture_time from EXIF fixture"
        );
        assert!(meta.gps.is_some(), "expected GPS from EXIF fixture");
        let gps = meta.gps.unwrap();
        assert!(gps.lat < 0.0, "Sydney should be southern hemisphere");
        assert!(gps.lon > 0.0);
    }

    #[test]
    fn missing_path_is_error() {
        let missing = temp_path("no-such-file.jpg");
        assert!(extract_metadata(&missing).is_err());
    }

    #[test]
    fn ffprobe_json_location_and_creation() {
        let json: Value = serde_json::json!({
            "streams": [{"codec_type":"video","width":100,"height":50,"tags":{}}],
            "format": {
                "duration": "12.5",
                "tags": {
                    "creation_time": "2024-06-15T14:32:01.000000Z",
                    "location": "-33.8688+151.2093/"
                }
            }
        });
        let p = parse_ffprobe_json(&json);
        assert_eq!(p.width, Some(100));
        assert_eq!(p.height, Some(50));
        assert_eq!(p.duration, Some(12.5));
        assert_eq!(p.capture_time.as_deref(), Some("2024-06-15 14:32:01"));
        let g = p.gps.unwrap();
        assert!((g.lat + 33.8688).abs() < 1e-6);
    }

    #[test]
    fn write_helper_for_fixture_generation() {
        // Ensures Write import stays meaningful in test cfg
        let dir = temp_path("write");
        fs::create_dir_all(&dir).unwrap();
        let mut f = fs::File::create(dir.join("x.txt")).unwrap();
        f.write_all(b"ok").unwrap();
        let _ = fs::remove_dir_all(&dir);
    }
}
