use crate::database::get_connection;
use super::models::MetricsSnapshot;
use rusqlite::params;

pub fn insert_snapshot(s: &MetricsSnapshot) -> Result<(), rusqlite::Error> {
    let conn = get_connection()?;
    conn.execute(
        "INSERT INTO metrics_history (
            timestamp, cpu_usage_percent,
            memory_total_bytes, memory_used_bytes, memory_available_bytes,
            disk_total_bytes, disk_used_bytes, disk_available_bytes,
            load_avg_1m, load_avg_5m, load_avg_15m,
            process_memory_bytes, uptime_seconds, system_uptime_seconds
        ) VALUES (?1,?2,?3,?4,?5,?6,?7,?8,?9,?10,?11,?12,?13,?14)",
        params![
            s.timestamp, s.cpu_usage_percent,
            s.memory_total_bytes as i64, s.memory_used_bytes as i64, s.memory_available_bytes as i64,
            s.disk_total_bytes as i64, s.disk_used_bytes as i64, s.disk_available_bytes as i64,
            s.load_avg_1m, s.load_avg_5m, s.load_avg_15m,
            s.process_memory_bytes as i64, s.uptime_seconds as i64, s.system_uptime_seconds as i64
        ],
    )?;
    Ok(())
}

pub fn get_history(minutes: u32) -> Result<Vec<MetricsSnapshot>, rusqlite::Error> {
    let conn = get_connection()?;
    let cutoff = (chrono::Utc::now() - chrono::Duration::minutes(minutes as i64)).to_rfc3339();

    let mut stmt = conn.prepare(
        "SELECT timestamp, cpu_usage_percent,
                memory_total_bytes, memory_used_bytes, memory_available_bytes,
                disk_total_bytes, disk_used_bytes, disk_available_bytes,
                load_avg_1m, load_avg_5m, load_avg_15m,
                process_memory_bytes, uptime_seconds,
                COALESCE(system_uptime_seconds, 0)
         FROM metrics_history
         WHERE timestamp >= ?1
         ORDER BY timestamp ASC"
    )?;

    let rows = stmt.query_map(params![cutoff], |row| {
        Ok(MetricsSnapshot {
            timestamp: row.get(0)?,
            cpu_usage_percent: row.get(1)?,
            memory_total_bytes: row.get::<_, i64>(2)? as u64,
            memory_used_bytes: row.get::<_, i64>(3)? as u64,
            memory_available_bytes: row.get::<_, i64>(4)? as u64,
            disk_total_bytes: row.get::<_, i64>(5)? as u64,
            disk_used_bytes: row.get::<_, i64>(6)? as u64,
            disk_available_bytes: row.get::<_, i64>(7)? as u64,
            load_avg_1m: row.get(8)?,
            load_avg_5m: row.get(9)?,
            load_avg_15m: row.get(10)?,
            process_memory_bytes: row.get::<_, i64>(11)? as u64,
            uptime_seconds: row.get::<_, i64>(12)? as u64,
            system_uptime_seconds: row.get::<_, i64>(13)? as u64,
        })
    })?;

    let mut snapshots = Vec::new();
    for row in rows {
        snapshots.push(row?);
    }
    Ok(snapshots)
}

pub fn get_indexed_file_count() -> Result<i64, rusqlite::Error> {
    let conn = get_connection()?;
    conn.query_row(
        "SELECT COUNT(*) FROM file_index WHERE current_path IS NOT NULL",
        [],
        |row| row.get(0),
    )
}

pub fn get_db_size() -> Result<(u64, u64), rusqlite::Error> {
    let db_path = crate::database::get_db_path();
    let db_size = std::fs::metadata(&db_path).map(|m| m.len()).unwrap_or(0);
    let wal_path = db_path.with_extension("db-wal");
    let wal_size = std::fs::metadata(&wal_path).map(|m| m.len()).unwrap_or(0);
    Ok((db_size, wal_size))
}

pub fn cleanup_old_snapshots() -> Result<usize, rusqlite::Error> {
    let conn = get_connection()?;
    let cutoff = (chrono::Utc::now() - chrono::Duration::hours(24)).to_rfc3339();
    let deleted = conn.execute(
        "DELETE FROM metrics_history WHERE timestamp < ?1",
        params![cutoff],
    )?;
    if deleted > 0 {
        eprintln!("[metrics] cleaned {} old snapshots", deleted);
    }
    Ok(deleted)
}
