//! Backend API tests for GET /api/file/metadata?path=
//! Spawns the server binary and drives HTTP checks via `file_metadata_api.sh`.

use std::process::Command;

#[test]
fn file_metadata_http_api() {
    let bin = env!("CARGO_BIN_EXE_re-sourcer");
    let script = concat!(env!("CARGO_MANIFEST_DIR"), "/tests/file_metadata_api.sh");

    let status = Command::new("bash")
        .arg(script)
        .env("RESOURCER_BIN", bin)
        .status()
        .expect("failed to spawn file_metadata_api.sh");

    assert!(
        status.success(),
        "file metadata API script failed with status {:?}",
        status.code()
    );
}
