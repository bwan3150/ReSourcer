//! Backend API tests for /api/playlist modes (sequential / list_loop / shuffle).

use std::process::Command;

#[test]
fn playlist_modes_http_api() {
    let bin = env!("CARGO_BIN_EXE_re-sourcer");
    let script = concat!(env!("CARGO_MANIFEST_DIR"), "/tests/playlist_api.sh");

    let status = Command::new("bash")
        .arg(script)
        .env("RESOURCER_BIN", bin)
        .status()
        .expect("failed to spawn playlist_api.sh");

    assert!(
        status.success(),
        "playlist API script failed with status {:?}",
        status.code()
    );
}
