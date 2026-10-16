import client from './client'

/** 按绝对路径读取文件元数据（缺省字段由服务端省略） */
export function getFileMetadata(path) {
  return client.get('/api/file/metadata', { params: { path } })
}

export function renameFile(uuid, newName) {
  return client.post('/api/file/rename', { uuid, newName })
}

export function moveFile(uuid, targetFolder, newName) {
  const data = { uuid, targetFolder }
  if (newName) data.newName = newName
  return client.post('/api/file/move', data)
}

// 软删除：将文件移动到源文件夹根部的回收站（_Recycle），不做物理删除
export function deleteFile(uuid) {
  return client.post('/api/file/delete', { uuid })
}

/** 批量移动到同一目标文件夹 */
export function batchMoveFiles(uuids, targetFolder) {
  return client.post('/api/file/batch/move', { uuids, targetFolder })
}

/** 批量软删除到回收站 */
export function batchDeleteFiles(uuids) {
  return client.post('/api/file/batch/delete', { uuids })
}
