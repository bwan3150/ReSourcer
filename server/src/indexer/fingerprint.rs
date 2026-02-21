// 文件内容指纹计算
use sha2::{Sha256, Digest};
use std::fs::File;
use std::io::{self, Read, Seek, SeekFrom};
use std::path::Path;

const CHUNK_SIZE: usize = 64 * 1024; // 64KB

/// 计算文件指纹: SHA256(file_size_le_bytes || first_64KB || last_64KB)
/// 对 GB 级视频也只读 128KB，几乎不可能碰撞
pub fn compute_fingerprint(path: &Path) -> Result<String, io::Error> {
    let mut file = File::open(path)?;
    let file_size = file.metadata()?.len();

    let mut hasher = Sha256::new();

    // 写入文件大小（小端序 8 字节）
    hasher.update(&file_size.to_le_bytes());

    // 读取前 64KB
    let mut head_buf = vec![0u8; CHUNK_SIZE.min(file_size as usize)];
    file.read_exact(&mut head_buf)?;
    hasher.update(&head_buf);

    // 如果文件大于 64KB，读取最后 64KB
    if file_size > CHUNK_SIZE as u64 {
        let tail_start = file_size - CHUNK_SIZE as u64;
        file.seek(SeekFrom::Start(tail_start))?;
        let mut tail_buf = vec![0u8; CHUNK_SIZE];
        file.read_exact(&mut tail_buf)?;
        hasher.update(&tail_buf);
    }

    let result = hasher.finalize();
    Ok(format!("{:x}", result))
}
