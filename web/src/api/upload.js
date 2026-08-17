import client from './client'

export function uploadFiles(targetFolder, files, onProgress) {
  const form = new FormData()
  form.append('target_folder', targetFolder)
  for (const file of files) {
    form.append('files', file)
  }
  return client.post('/api/transfer/upload/task', form, {
    timeout: 300000,
    onUploadProgress: onProgress,
  })
}

export function getActiveTasks() {
  return client.get('/api/transfer/upload/tasks')
}

export function getTask(taskId) {
  return client.get(`/api/transfer/upload/task/${taskId}`)
}

export function deleteTask(taskId) {
  return client.delete(`/api/transfer/upload/task/${taskId}`)
}

export function clearFinished() {
  return client.post('/api/transfer/upload/tasks/clear')
}

export function getHistory(offset = 0, limit = 50, status) {
  const params = { offset, limit }
  if (status) params.status = status
  return client.get('/api/transfer/upload/history', { params })
}

// ==================== 分片上传（大文件）====================

// 获取服务器分片上传策略（分片大小阈值）
export function getUploadPolicy() {
  return client.get('/api/transfer/upload/policy')
}

// 更新服务器分片大小限制（MB）
export function setUploadPolicy(chunkSizeMb) {
  return client.post('/api/transfer/upload/policy', { chunkSizeMb })
}

// 初始化分片会话
function initChunkUpload(payload) {
  return client.post('/api/transfer/upload/chunk/init', payload)
}

// 上传单个分片（裸二进制）
function uploadChunkPart(uploadId, index, blob) {
  return client.post(
    `/api/transfer/upload/chunk/part/${uploadId}/${index}`,
    blob,
    {
      timeout: 300000,
      headers: { 'Content-Type': 'application/octet-stream' },
    }
  )
}

// 触发服务端合并
function completeChunkUpload(uploadId) {
  return client.post(`/api/transfer/upload/chunk/complete/${uploadId}`)
}

// 中止并清理暂存分片
function abortChunkUpload(uploadId) {
  return client.post(`/api/transfer/upload/chunk/abort/${uploadId}`)
}

/**
 * 分片上传单个大文件：切分 → 逐片上传 → 服务端合并
 * @param {string} targetFolder 目标文件夹
 * @param {File} file 待上传文件
 * @param {object} opts
 * @param {number} opts.chunkSize 分片大小（字节），由服务器策略决定
 * @param {(ratio:number)=>void} [opts.onProgress] 进度回调（0.0~1.0）
 */
export async function uploadFileChunked(targetFolder, file, { chunkSize, onProgress } = {}) {
  if (!chunkSize || chunkSize <= 0) {
    throw new Error('无效的分片大小')
  }
  const totalBytes = file.size
  // 向上取整计算分片数量
  const totalChunks = Math.max(1, Math.ceil(totalBytes / chunkSize))

  // 1. 初始化分片会话
  const initResp = await initChunkUpload({
    fileName: file.name,
    fileSize: totalBytes,
    targetFolder,
    totalChunks,
  })
  const uploadId = initResp.data.uploadId

  try {
    // 2. 逐片上传（顺序，index 从 0 起）
    for (let index = 0; index < totalChunks; index++) {
      const start = index * chunkSize
      const end = Math.min(start + chunkSize, totalBytes)
      const blob = file.slice(start, end)
      await uploadChunkPart(uploadId, index, blob)
      onProgress?.((index + 1) / totalChunks)
    }
    // 3. 触发服务端合并
    const complete = await completeChunkUpload(uploadId)
    return complete.data
  } catch (err) {
    // 失败时尽力清理服务端暂存分片
    try {
      await abortChunkUpload(uploadId)
    } catch (_) {
      /* 忽略清理错误 */
    }
    throw err
  }
}
