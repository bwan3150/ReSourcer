use crate::database::get_connection;
use crate::indexer::models::IndexedFile;
use crate::indexer::storage::{map_file_row, get_file_by_uuid};
use rusqlite::params;

const FILE_COLUMNS: &str = "uuid, fingerprint, current_path, folder_path, file_name, file_type, extension, file_size, created_at, modified_at, indexed_at, source_url";
const CONTEXT_SIZE: i64 = 3;

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

/// Sequential playlist: find the file's position in sorted order, return 3 before + current + 3 after
pub fn get_playlist_sequential(
    folder_path: &str,
    uuid: &str,
    file_type: Option<&str>,
    sort: Option<&str>,
) -> Result<(Vec<IndexedFile>, usize), rusqlite::Error> {
    let conn = get_connection()?;
    let target = get_file_by_uuid(uuid)?
        .ok_or_else(|| rusqlite::Error::QueryReturnedNoRows)?;

    let (col, dir) = sort_clause(sort);
    let (ignore_clause, ignored) = ignored_files_clause();
    let type_clause = if file_type.is_some() { " AND file_type = ?" } else { "" };

    // Count files that come before this one in the sorted order
    // For ASC: count where (col < value) OR (col = value AND uuid < target_uuid)
    // For DESC: count where (col > value) OR (col = value AND uuid > target_uuid)
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

    // Get total count for wrapping
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
        return Ok((vec![target], 0));
    }

    let order_by = format!("{} {}, uuid {}", col, dir, dir);

    // Build window with wrapping
    let ctx = CONTEXT_SIZE.min(total - 1);

    let fw = |off: i64, lim: i64| fetch_window(folder_path, file_type, &ignored, &ignore_clause, &type_clause, &order_by, off, lim);

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

    let current_index = before.len();
    let mut items = before;
    items.push(target);
    items.extend(after);

    Ok((items, current_index))
}

/// Shuffle playlist: current file + 6 random files from the folder
///
/// `current_queue`: the client's current 7-item queue (UUIDs in order).
/// If provided, server determines which items stay in the new window
/// (based on target's position in old queue) and fills the rest with new randoms.
/// If not provided (initial request), picks 6 fresh randoms.
pub fn get_playlist_shuffle(
    folder_path: &str,
    uuid: &str,
    file_type: Option<&str>,
    current_queue: Option<&[String]>,
) -> Result<(Vec<IndexedFile>, usize), rusqlite::Error> {
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

        Ok((items, current_index))
    } else {
        // Initial shuffle: pick 6 random files
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

        Ok((items, current_index))
    }
}
