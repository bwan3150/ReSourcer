import client from './client'

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
