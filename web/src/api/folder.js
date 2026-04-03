import client from './client'

export function listFolders(sourceFolder) {
  const params = sourceFolder ? { source_folder: sourceFolder } : {}
  return client.get('/api/folder/list', { params })
}

export function createFolder(folderName) {
  return client.post('/api/folder/create', { folderName })
}

export function reorderFolders(sourceFolder, categoryOrder) {
  return client.post('/api/folder/reorder', { sourceFolder, categoryOrder })
}

export function openFolder(path) {
  return client.post('/api/folder/open', { path })
}
