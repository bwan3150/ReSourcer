import client from './client'

export function listTags(sourceFolder) {
  return client.get('/api/tag/list', { params: { source_folder: sourceFolder } })
}

export function createTag(sourceFolder, name, color) {
  return client.post('/api/tag/create', { sourceFolder, name, color })
}

export function updateTag(id, data) {
  return client.put(`/api/tag/update/${id}`, data)
}

export function deleteTag(id) {
  return client.delete(`/api/tag/delete/${id}`)
}

export function getFileTags(fileUuid) {
  return client.get('/api/tag/file', { params: { file_uuid: fileUuid } })
}

export function setFileTags(fileUuid, tagIds) {
  return client.post('/api/tag/file', { fileUuid, tagIds })
}

export function batchGetFileTags(fileUuids) {
  return client.post('/api/tag/files', { fileUuids })
}
