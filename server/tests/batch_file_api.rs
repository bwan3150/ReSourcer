//! Backend API tests for batch file move/delete.
//! Spawns the server binary against a temp RESOURCER_DIR and drives HTTP checks
//! via `batch_file_api.sh` (same black-box style as `.ai/reports/RS-002/api.sh`).

use std::process::Command;

#[test]
fn batch_move_and_delete_http_api() {
    let bin = env!("CARGO_BIN_EXE_re-sourcer");
    let script = concat!(env!("CARGO_MANIFEST_DIR"), "/tests/batch_file_api.sh");

    let status = Command::new("bash")
        .arg(script)
        .env("RESOURCER_BIN", bin)
        .status()
        .expect("failed to spawn batch_file_api.sh");

    assert!(
        status.success(),
        "batch file API script failed with status {:?}",
        status.code()
    );
}
