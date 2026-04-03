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
