//! Backend API tests for path-mirrored `.thumb` persistence.
//! Spawns the server and drives HTTP checks via `thumbnail_persist_api.sh`.

use std::process::Command;

#[test]
fn thumbnail_persist_http_api() {
    let bin = env!("CARGO_BIN_EXE_re-sourcer");
    let script = concat!(env!("CARGO_MANIFEST_DIR"), "/tests/thumbnail_persist_api.sh");

    let status = Command::new("bash")
        .arg(script)
        .env("RESOURCER_BIN", bin)
        .status()
        .expect("failed to spawn thumbnail_persist_api.sh");

    assert!(
        status.success(),
        "thumbnail persist API script failed with status {:?}",
        status.code()
    );
}
