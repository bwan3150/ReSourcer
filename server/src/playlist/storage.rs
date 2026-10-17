use crate::database::get_connection;
use crate::indexer::models::IndexedFile;
use crate::indexer::storage::{map_file_row, get_file_by_uuid};

const FILE_COLUMNS: &str = "uuid, fingerprint, current_path, folder_path, file_name, file_type, extension, file_size, created_at, modified_at, indexed_at, source_url";
const CONTEXT_SIZE: i64 = 3;

/// Sliding playlist window returned to clients.
#[derive(Debug, Clone)]
pub struct PlaylistWindow {
    pub items: Vec<IndexedFile>,
    pub current_index: usize,
    pub at_start: bool,
    pub at_end: bool,
}

fn fetch_window(
    folder_path: &str,
    file_type: Option<&str>,
    ignored: &[String],
    ignore_clause: &str,
    type_clause: &str,
    order_by: &str,
    off: i64,
    lim: i64,
) -> Result<Vec<IndexedFile>, rusqlite::Error> {
    let conn = get_connection()?;
    let query = format!(
        "SELECT {} FROM file_index WHERE folder_path = ? AND current_path IS NOT NULL{}{} ORDER BY {} LIMIT ? OFFSET ?",
        FILE_COLUMNS, type_clause, ignore_clause, order_by
    );
    let mut p: Vec<String> = vec![folder_path.to_string()];
    if let Some(ft) = file_type { p.push(ft.to_string()); }
    p.extend(ignored.iter().cloned());
    p.push(lim.to_string());
    p.push(off.to_string());
    let mut s = conn.prepare(&query)?;
    let rows = s.query_map(rusqlite::params_from_iter(p.iter()), map_file_row)?;
    let result: Vec<IndexedFile> = rows.collect::<Result<Vec<_>, _>>()?;
    Ok(result)
}

fn sort_clause(sort: Option<&str>) -> (&str, &str) {
    // Returns (primary_column, direction) for ORDER BY and position counting
    match sort {
        Some("name_asc") => ("file_name", "ASC"),
        Some("name_desc") => ("file_name", "DESC"),
        Some("size_asc") => ("file_size", "ASC"),
        Some("size_desc") => ("file_size", "DESC"),
        Some("created_asc") => ("created_at", "ASC"),
        Some("created_desc") => ("created_at", "DESC"),
        _ => ("modified_at", "DESC"),
    }
}

fn ignored_files_clause() -> (String, Vec<String>) {
    let ignored = crate::config_api::storage::load_config()
        .map(|c| c.ignored_files)
        .unwrap_or_default();
    if ignored.is_empty() {
        (String::new(), vec![])
    } else {
        let placeholders = ignored.iter().map(|_| "?").collect::<Vec<_>>().join(", ");
        (format!(" AND file_name NOT IN ({})", placeholders), ignored)
    }
}

/// Sequential playlist: find the file's position in sorted order, return up to 3 before + current + 3 after.
///
/// When `wrap` is true (`list_loop`), edges wrap around the folder.
/// When `wrap` is false (`sequential`), edges are clipped and `at_start` / `at_end` reflect absolute ends.
pub fn get_playlist_sequential(
    folder_path: &str,
    uuid: &str,
    file_type: Option<&str>,
    sort: Option<&str>,
    wrap: bool,
) -> Result<PlaylistWindow, rusqlite::Error> {
    let conn = get_connection()?;
    let target = get_file_by_uuid(uuid)?
        .ok_or_else(|| rusqlite::Error::QueryReturnedNoRows)?;

    let (col, dir) = sort_clause(sort);
    let (ignore_clause, ignored) = ignored_files_clause();
    let type_clause = if file_type.is_some() { " AND file_type = ?" } else { "" };

    // Count files that come before this one in the sorted order
    let (cmp_before, cmp_tie) = if dir == "ASC" { ("<", "<") } else { (">", ">") };

    let sort_value: String = match col {
        "file_name" => target.file_name.clone(),
        "file_size" => target.file_size.to_string(),
        "created_at" => target.created_at.clone(),
        _ => target.modified_at.clone(),
    };

    let position_query = format!(
        "SELECT COUNT(*) FROM file_index WHERE folder_path = ? AND current_path IS NOT NULL{}{} AND ({} {} ? OR ({} = ? AND uuid {} ?))",
        type_clause, ignore_clause, col, cmp_before, col, cmp_tie
    );

    let mut pos_params: Vec<String> = vec![folder_path.to_string()];
    if let Some(ft) = file_type { pos_params.push(ft.to_string()); }
    pos_params.extend(ignored.iter().cloned());
    pos_params.push(sort_value.clone());
    pos_params.push(sort_value.clone());
    pos_params.push(uuid.to_string());

    let mut stmt = conn.prepare(&position_query)?;
    let position: i64 = {
        let mut rows = stmt.query(rusqlite::params_from_iter(pos_params.iter()))?;
        rows.next()?.map(|r| r.get(0)).transpose()?.unwrap_or(0)
    };

    // Get total count
    let total_query = format!(
        "SELECT COUNT(*) FROM file_index WHERE folder_path = ? AND current_path IS NOT NULL{}{}",
        type_clause, ignore_clause
    );
    let mut total_params: Vec<String> = vec![folder_path.to_string()];
    if let Some(ft) = file_type { total_params.push(ft.to_string()); }
    total_params.extend(ignored.iter().cloned());

    let total: i64 = {
        let mut stmt = conn.prepare(&total_query)?;
        let mut rows = stmt.query(rusqlite::params_from_iter(total_params.iter()))?;
        rows.next()?.map(|r| r.get(0)).transpose()?.unwrap_or(0)
    };

    if total == 0 {
        return Ok(PlaylistWindow {
            items: vec![target],
            current_index: 0,
            at_start: true,
            at_end: true,
        });
    }

    let order_by = format!("{} {}, uuid {}", col, dir, dir);
    let at_start = position == 0;
    let at_end = position >= total - 1;

    let fw = |off: i64, lim: i64| {
        fetch_window(
            folder_path,
            file_type,
            &ignored,
            &ignore_clause,
            &type_clause,
            &order_by,
            off,
            lim,
        )
    };

    let ctx = CONTEXT_SIZE.min(total - 1).max(0);

    let (before, after) = if wrap {
        // Items before (wrapping)
        let before = if position >= ctx {
            fw(position - ctx, ctx)?
        } else {
            let mut tail = fw(total - (ctx - position), ctx - position)?;
            tail.extend(fw(0, position)?);
            tail
        };

        // Items after (wrapping)
        let remaining_after = total - position - 1;
        let after = if remaining_after >= ctx {
            fw(position + 1, ctx)?
        } else {
            let mut tail = fw(position + 1, remaining_after)?;
            tail.extend(fw(0, ctx - remaining_after)?);
            tail
        };
        (before, after)
    } else {
        // No wrap: clip at folder ends
        let before_count = position.min(ctx);
        let before = if before_count > 0 {
            fw(position - before_count, before_count)?
        } else {
            vec![]
        };
        let remaining_after = (total - position - 1).max(0);
        let after_count = remaining_after.min(ctx);
        let after = if after_count > 0 {
            fw(position + 1, after_count)?
        } else {
            vec![]
        };
        (before, after)
    };

    let current_index = before.len();
    let mut items = before;
    items.push(target);
    items.extend(after);

    Ok(PlaylistWindow {
        items,
        current_index,
        at_start,
        at_end,
    })
}

/// Shuffle playlist: current file + up to 6 random files from the folder.
///
/// `current_queue`: the client's current window (UUIDs in play order).
/// - **Omit** when first entering shuffle so neighbors are freshly random (fixes
///   "first N still sequential" when the prior sequential window was reused).
/// - **Provide** while navigating so relative shuffled order is preserved and
///   only empty edge slots are filled with new randoms.
pub fn get_playlist_shuffle(
    folder_path: &str,
    uuid: &str,
    file_type: Option<&str>,
    current_queue: Option<&[String]>,
) -> Result<PlaylistWindow, rusqlite::Error> {
    let conn = get_connection()?;
    let target = get_file_by_uuid(uuid)?
        .ok_or_else(|| rusqlite::Error::QueryReturnedNoRows)?;

    let (ignore_clause, ignored) = ignored_files_clause();
    let type_clause = if file_type.is_some() { " AND file_type = ?" } else { "" };

    if let Some(queue) = current_queue {
        // Find target's position in old queue
        let target_pos = queue.iter().position(|u| u == uuid);

        // Determine which old items stay in the new window (centered on target)
        let mut keep_uuids: Vec<String> = Vec::new();
        if let Some(pos) = target_pos {
            // Items within 3 positions of target in the old queue stay
            for (i, u) in queue.iter().enumerate() {
                if u == uuid { continue; }
                let dist = (i as i64 - pos as i64).unsigned_abs() as usize;
                if dist <= CONTEXT_SIZE as usize {
                    keep_uuids.push(u.clone());
                }
            }
        }
        // else: target not in old queue (jump), keep nothing

        // Load kept files, preserving their order from the old queue
        let mut before_files: Vec<IndexedFile> = Vec::new();
        let mut after_files: Vec<IndexedFile> = Vec::new();
        if let Some(pos) = target_pos {
            for (i, u) in queue.iter().enumerate() {
                if u == uuid { continue; }
                if !keep_uuids.contains(u) { continue; }
                if let Some(f) = get_file_by_uuid(u)? {
                    if i < pos { before_files.push(f); }
                    else { after_files.push(f); }
                }
            }
        }

        // Trim to max 3 before, 3 after
        if before_files.len() > CONTEXT_SIZE as usize {
            before_files = before_files.split_off(before_files.len() - CONTEXT_SIZE as usize);
        }
        if after_files.len() > CONTEXT_SIZE as usize {
            after_files.truncate(CONTEXT_SIZE as usize);
        }

        // How many new randoms needed?
        let need_before = (CONTEXT_SIZE as usize).saturating_sub(before_files.len());
        let need_after = (CONTEXT_SIZE as usize).saturating_sub(after_files.len());
        let need_total = need_before + need_after;

        // Exclude current + kept from random picks
        let mut exclude: Vec<String> = vec![uuid.to_string()];
        exclude.extend(keep_uuids.iter().cloned());
        let excl_placeholders = exclude.iter().map(|_| "?").collect::<Vec<_>>().join(", ");

        let rand_query = format!(
            "SELECT {} FROM file_index WHERE folder_path = ? AND current_path IS NOT NULL AND uuid NOT IN ({}){}{} ORDER BY RANDOM() LIMIT ?",
            FILE_COLUMNS, excl_placeholders, type_clause, ignore_clause
        );

        let mut rand_params: Vec<String> = vec![folder_path.to_string()];
        rand_params.extend(exclude);
        if let Some(ft) = file_type { rand_params.push(ft.to_string()); }
        rand_params.extend(ignored.iter().cloned());
        rand_params.push(need_total.to_string());

        let mut stmt = conn.prepare(&rand_query)?;
        let new_randoms: Vec<IndexedFile> = stmt
            .query_map(rusqlite::params_from_iter(rand_params.iter()), map_file_row)?
            .collect::<Result<Vec<_>, _>>()?;

        // Distribute new randoms: fill before first, then after
        let rand_for_before = &new_randoms[..need_before.min(new_randoms.len())];
        let rand_for_after = &new_randoms[need_before.min(new_randoms.len())..];

        // Assemble: [new_rand_before...] + [kept_before...] + target + [kept_after...] + [new_rand_after...]
        let mut items: Vec<IndexedFile> = Vec::new();
        items.extend(rand_for_before.to_vec());
        items.extend(before_files);
        let current_index = items.len();
        items.push(target);
        items.extend(after_files);
        items.extend(rand_for_after.to_vec());

        Ok(PlaylistWindow {
            items,
            current_index,
            at_start: false,
            at_end: false,
        })
    } else {
        // Fresh shuffle: pick 6 random files — do NOT reuse a sequential window.
        let rand_query = format!(
            "SELECT {} FROM file_index WHERE folder_path = ? AND uuid != ? AND current_path IS NOT NULL{}{} ORDER BY RANDOM() LIMIT 6",
            FILE_COLUMNS, type_clause, ignore_clause
        );

        let mut rand_params: Vec<String> = vec![folder_path.to_string(), uuid.to_string()];
        if let Some(ft) = file_type { rand_params.push(ft.to_string()); }
        rand_params.extend(ignored.iter().cloned());

        let mut stmt = conn.prepare(&rand_query)?;
        let randoms: Vec<IndexedFile> = stmt
            .query_map(rusqlite::params_from_iter(rand_params.iter()), map_file_row)?
            .collect::<Result<Vec<_>, _>>()?;

        let split = randoms.len().min(3);
        let current_index = split;
        let mut items: Vec<IndexedFile> = randoms[..split].to_vec();
        items.push(target);
        items.extend(randoms[split..].to_vec());

        Ok(PlaylistWindow {
            items,
            current_index,
            at_start: false,
            at_end: false,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::indexer::models::IndexedFile;
    use std::fs;
    use std::path::PathBuf;
    use std::sync::Mutex;
    use std::time::{SystemTime, UNIX_EPOCH};

    static TEST_LOCK: Mutex<()> = Mutex::new(());

    struct TestEnv {
        _guard: std::sync::MutexGuard<'static, ()>,
        data_dir: PathBuf,
        folder: String,
        uuids: Vec<String>,
        names: Vec<String>,
    }

    impl TestEnv {
        fn setup(file_count: usize) -> Self {
            let guard = TEST_LOCK.lock().unwrap_or_else(|e| e.into_inner());
            let nanos = SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap()
                .as_nanos();
            let root = std::env::temp_dir().join(format!("resourcer-playlist-{}", nanos));
            let data_dir = root.join("data");
            let source = root.join("source");
            fs::create_dir_all(&data_dir).unwrap();
            fs::create_dir_all(&source).unwrap();
            std::env::set_var("RESOURCER_DIR", &data_dir);
            std::env::remove_var("RESOURCER_DATA_DIR");
            crate::database::init_db().expect("init_db");
            let folder = source.to_string_lossy().to_string();
            crate::config_api::storage::add_source_folder(&folder).expect("add_source");

            let mut names = Vec::new();
            let mut uuids = Vec::new();
            for i in 0..file_count {
                let name = format!("file{:02}.png", i);
                let path = source.join(&name);
                fs::write(&path, format!("png-{}", i)).unwrap();
                let uuid = uuid::Uuid::new_v4().to_string();
                // Distinct modified_at so default sort is stable; name_asc used in tests.
                let modified = format!("2026-01-01T00:{:02}:00Z", i);
                let file = IndexedFile {
                    uuid: uuid.clone(),
                    fingerprint: format!("fp-{}", name),
                    current_path: Some(path.to_string_lossy().to_string()),
                    folder_path: folder.clone(),
                    file_name: name.clone(),
                    file_type: "image".to_string(),
                    extension: "png".to_string(),
                    file_size: 8,
                    created_at: modified.clone(),
                    modified_at: modified.clone(),
                    indexed_at: modified,
                    source_url: None,
            live_video_uuid: None,
            live_video_path: None,
                };
                crate::indexer::storage::upsert_file(&file).expect("upsert");
                names.push(name);
                uuids.push(uuid);
            }

            Self {
                _guard: guard,
                data_dir,
                folder,
                uuids,
                names,
            }
        }
    }

    impl Drop for TestEnv {
        fn drop(&mut self) {
            let _ = fs::remove_dir_all(self.data_dir.parent().unwrap_or(&self.data_dir));
            std::env::remove_var("RESOURCER_DIR");
        }
    }

    #[test]
    fn sequential_no_wrap_marks_ends() {
        let env = TestEnv::setup(7);
        let mid = &env.uuids[3];
        let win = get_playlist_sequential(&env.folder, mid, None, Some("name_asc"), false)
            .expect("sequential mid");
        assert!(!win.at_start);
        assert!(!win.at_end);
        assert_eq!(win.items.len(), 7);

        let first = &env.uuids[0];
        let win0 = get_playlist_sequential(&env.folder, first, None, Some("name_asc"), false)
            .expect("sequential first");
        assert!(win0.at_start);
        assert!(!win0.at_end);
        assert_eq!(win0.current_index, 0);

        let last = env.uuids.last().unwrap();
        let win_last = get_playlist_sequential(&env.folder, last, None, Some("name_asc"), false)
            .expect("sequential last");
        assert!(win_last.at_end);
        assert!(!win_last.at_start);
        assert_eq!(win_last.current_index, win_last.items.len() - 1);
    }

    #[test]
    fn list_loop_wraps_at_edges() {
        let env = TestEnv::setup(7);
        let first = &env.uuids[0];
        let win = get_playlist_sequential(&env.folder, first, None, Some("name_asc"), true)
            .expect("list_loop first");
        assert!(win.current_index > 0, "wrap should put prior items before first");
        let names: Vec<_> = win.items.iter().map(|f| f.file_name.as_str()).collect();
        assert!(names.contains(&env.names.last().unwrap().as_str()));
    }

    #[test]
    fn fresh_shuffle_does_not_keep_sequential_neighbors() {
        let env = TestEnv::setup(12);
        let mid = &env.uuids[5];

        let seq = get_playlist_sequential(&env.folder, mid, None, Some("name_asc"), false)
            .expect("seq");
        let seq_neighbor_ids: Vec<String> = seq
            .items
            .iter()
            .filter(|f| f.uuid != *mid)
            .map(|f| f.uuid.clone())
            .collect();

        let mut differed = false;
        for _ in 0..20 {
            let sh = get_playlist_shuffle(&env.folder, mid, None, None).expect("shuffle");
            let sh_ids: Vec<String> = sh
                .items
                .iter()
                .filter(|f| f.uuid != *mid)
                .map(|f| f.uuid.clone())
                .collect();
            if sh_ids != seq_neighbor_ids {
                differed = true;
                break;
            }
        }
        assert!(
            differed,
            "fresh shuffle kept identical sequential neighbors for 20 trials"
        );
    }

    #[test]
    fn shuffle_with_queue_preserves_relative_order() {
        let env = TestEnv::setup(10);
        let mid = &env.uuids[4];
        let fresh = get_playlist_shuffle(&env.folder, mid, None, None).expect("fresh");
        assert!(fresh.current_index + 1 < fresh.items.len());
        let queue: Vec<String> = fresh.items.iter().map(|f| f.uuid.clone()).collect();
        let next_uuid = queue[fresh.current_index + 1].clone();

        let moved = get_playlist_shuffle(&env.folder, &next_uuid, None, Some(&queue))
            .expect("nav");
        let mid_pos = moved.items.iter().position(|f| f.uuid == *mid);
        let next_pos = moved.items.iter().position(|f| f.uuid == next_uuid);
        assert!(mid_pos.is_some() && next_pos.is_some());
        assert!(mid_pos.unwrap() < next_pos.unwrap());
    }
}
