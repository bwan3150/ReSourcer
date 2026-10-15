//! Backend API tests for HEIC tiled thumbnail generation.
//! Spawns the server with real ffmpeg/ffprobe and checks that a tile-grid
//! HEIC yields a full-frame JPEG thumb (not a single-tile grey crop).

use std::process::Command;

#[test]
fn heic_tiled_thumbnail_http_api() {
    let bin = env!("CARGO_BIN_EXE_re-sourcer");
    let script = concat!(env!("CARGO_MANIFEST_DIR"), "/tests/heic_thumbnail_api.sh");

    let status = Command::new("bash")
        .arg(script)
        .env("RESOURCER_BIN", bin)
        .status()
        .expect("failed to spawn heic_thumbnail_api.sh");

    assert!(
        status.success(),
        "HEIC thumbnail API script failed with status {:?}",
        status.code()
    );
}
