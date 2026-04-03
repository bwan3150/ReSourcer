import client from './client'

export function detectUrl(url) {
  return client.post('/api/transfer/download/detect', { url })
}

export function createTask(url, saveFolder, downloader, format) {
  const data = { url, saveFolder }
  if (downloader) data.downloader = downloader
  if (format) data.format = format
  return client.post('/api/transfer/download/task', data)
}

export function getActiveTasks() {
  return client.get('/api/transfer/download/tasks')
}

export function getTask(id) {
  return client.get(`/api/transfer/download/task/${id}`)
}

export function cancelTask(id) {
  return client.delete(`/api/transfer/download/task/${id}`)
}

export function getHistory(offset = 0, limit = 50, status) {
  const params = { offset, limit }
  if (status) params.status = status
  return client.get('/api/transfer/download/history', { params })
}

export function clearHistory() {
  return client.delete('/api/transfer/download/history')
}

export function getYtdlpVersion() {
  return client.get('/api/transfer/download/ytdlp/version')
}

export function updateYtdlp() {
  return client.post('/api/transfer/download/ytdlp/update')
}
