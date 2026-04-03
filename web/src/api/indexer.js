import client from './client'

export function getFiles(folderPath, { offset = 0, limit = 50, fileType, sort } = {}) {
  return client.get('/api/indexer/files', {
    params: { folder_path: folderPath, offset, limit, file_type: fileType, sort },
  })
}

export function getFileByUuid(uuid) {
  return client.get('/api/indexer/file', { params: { uuid } })
}

export function getFolders(parentPath, sourceFolder) {
  return client.get('/api/indexer/folders', {
    params: { parent_path: parentPath, source_folder: sourceFolder },
  })
}

export function getBreadcrumb(folderPath) {
  return client.get('/api/indexer/breadcrumb', { params: { folder_path: folderPath } })
}

export function triggerScan(sourceFolder, force = false) {
  return client.post('/api/indexer/scan', { sourceFolder, force })
}

export function getScanStatus() {
  return client.get('/api/indexer/status')
}
