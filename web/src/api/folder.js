import client from './client'

export function listFolders(sourceFolder) {
  const params = sourceFolder ? { source_folder: sourceFolder } : {}
  return client.get('/api/folder/list', { params })
}

export function createFolder(folderName, parentPath) {
  const data = { folderName }
  // 传入父目录时在其下创建，否则默认建在源文件夹根部
  if (parentPath) data.parentPath = parentPath
  return client.post('/api/folder/create', data)
}

export function reorderFolders(sourceFolder, categoryOrder) {
  return client.post('/api/folder/reorder', { sourceFolder, categoryOrder })
}

export function openFolder(path) {
  return client.post('/api/folder/open', { path })
}
