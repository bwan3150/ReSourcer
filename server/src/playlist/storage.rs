use crate::database::get_connection;
use crate::indexer::models::IndexedFile;
use crate::indexer::storage::{map_file_row, get_file_by_uuid};
use rusqlite::params;

const FILE_COLUMNS: &str = "uuid, fingerprint, current_path, folder_path, file_name, file_type, extension, file_size, created_at, modified_at, indexed_at, source_url";
const CONTEXT_SIZE: i64 = 3;

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

    // Fetch window: offset = max(0, position - 3), limit = 7
    let offset = (position - CONTEXT_SIZE).max(0);
    let limit = CONTEXT_SIZE * 2 + 1;

    let order_by = format!("{} {}, uuid {}", col, dir, dir);
    let fetch_query = format!(
        "SELECT {} FROM file_index WHERE folder_path = ? AND current_path IS NOT NULL{}{} ORDER BY {} LIMIT ? OFFSET ?",
        FILE_COLUMNS, type_clause, ignore_clause, order_by
    );

    let mut fetch_params: Vec<String> = vec![folder_path.to_string()];
    if let Some(ft) = file_type { fetch_params.push(ft.to_string()); }
    fetch_params.extend(ignored.iter().cloned());
    fetch_params.push(limit.to_string());
    fetch_params.push(offset.to_string());

    let mut stmt = conn.prepare(&fetch_query)?;
    let items: Vec<IndexedFile> = stmt
        .query_map(rusqlite::params_from_iter(fetch_params.iter()), map_file_row)?
        .collect::<Result<Vec<_>, _>>()?;

    let current_index = (position - offset) as usize;

    Ok((items, current_index))
}

/// Shuffle playlist: current file + 6 random files from the folder
pub fn get_playlist_shuffle(
    folder_path: &str,
    uuid: &str,
    file_type: Option<&str>,
    keep_uuids: Option<&[String]>,
) -> Result<(Vec<IndexedFile>, usize), rusqlite::Error> {
    let conn = get_connection()?;
    let target = get_file_by_uuid(uuid)?
        .ok_or_else(|| rusqlite::Error::QueryReturnedNoRows)?;

    let (ignore_clause, ignored) = ignored_files_clause();
    let type_clause = if file_type.is_some() { " AND file_type = ?" } else { "" };

    if let Some(keep) = keep_uuids {
        // Sliding window: keep specified items, fill remaining with new randoms
        let mut kept_files: Vec<IndexedFile> = Vec::new();
        for k_uuid in keep {
            if let Some(f) = get_file_by_uuid(k_uuid)? {
                kept_files.push(f);
            }
        }

        let need = (6i64 - kept_files.len() as i64).max(0);

        // Exclude current + kept from random picks
        let mut exclude: Vec<String> = vec![uuid.to_string()];
        exclude.extend(keep.iter().cloned());
        let excl_placeholders = exclude.iter().map(|_| "?").collect::<Vec<_>>().join(", ");

        let rand_query = format!(
            "SELECT {} FROM file_index WHERE folder_path = ? AND current_path IS NOT NULL AND uuid NOT IN ({}){}{} ORDER BY RANDOM() LIMIT ?",
            FILE_COLUMNS, excl_placeholders, type_clause, ignore_clause
        );

        let mut rand_params: Vec<String> = vec![folder_path.to_string()];
        rand_params.extend(exclude);
        if let Some(ft) = file_type { rand_params.push(ft.to_string()); }
        rand_params.extend(ignored.iter().cloned());
        rand_params.push(need.to_string());

        let mut stmt = conn.prepare(&rand_query)?;
        let new_randoms: Vec<IndexedFile> = stmt
            .query_map(rusqlite::params_from_iter(rand_params.iter()), map_file_row)?
            .collect::<Result<Vec<_>, _>>()?;

        // Assemble: [kept_before...] + [new_randoms_before...] + target + [kept_after...] + [new_randoms_after...]
        // Place kept items first (they maintain relative order), then fill with new randoms
        // Split: 3 before current, 3 after
        let mut before: Vec<IndexedFile> = Vec::new();
        let mut after: Vec<IndexedFile> = Vec::new();

        // Distribute kept + new into before/after
        let all_others: Vec<IndexedFile> = kept_files.into_iter().chain(new_randoms).collect();
        for f in all_others.into_iter() {
            if before.len() < 3 { before.push(f); }
            else { after.push(f); }
        }

        let current_index = before.len();
        let mut items = before;
        items.push(target);
        items.extend(after);

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

        // Split: first 3 before, last 3 after
        let split = randoms.len().min(3);
        let before = &randoms[..split];
        let after = &randoms[split..];

        let current_index = before.len();
        let mut items: Vec<IndexedFile> = before.to_vec();
        items.push(target);
        items.extend(after.to_vec());

        Ok((items, current_index))
    }
}
