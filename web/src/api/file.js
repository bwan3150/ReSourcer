import client from './client'

export function renameFile(uuid, newName) {
  return client.post('/api/file/rename', { uuid, newName })
}

export function moveFile(uuid, targetFolder, newName) {
  const data = { uuid, targetFolder }
  if (newName) data.newName = newName
  return client.post('/api/file/move', data)
}
