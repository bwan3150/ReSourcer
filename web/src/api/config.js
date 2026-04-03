import client from './client'

export function getConfig() {
  return client.get('/api/config')
}

export function getAppInfo() {
  return client.get('/api/app')
}

export function getConfigState() {
  return client.get('/api/config/state')
}

export function saveConfig(data) {
  return client.post('/api/config/save', data)
}

export function getDownloadConfig() {
  return client.get('/api/config/download')
}

export function saveDownloadConfig(data) {
  return client.post('/api/config/download', data)
}

export function getSources() {
  return client.get('/api/config/sources')
}

export function addSource(folderPath) {
  return client.post('/api/config/sources/add', { folderPath })
}

export function removeSource(folderPath) {
  return client.post('/api/config/sources/remove', { folderPath })
}

export function switchSource(folderPath) {
  return client.post('/api/config/sources/switch', { folderPath })
}

export function uploadCredentials(platform, content) {
  return client.post(`/api/config/credentials/${platform}`, content, {
    headers: { 'Content-Type': 'text/plain' },
  })
}

export function deleteCredentials(platform) {
  return client.delete(`/api/config/credentials/${platform}`)
}

export function getTools() {
  return client.get('/api/config/tools')
}

export function updateToolUrls(name, urls) {
  return client.post('/api/config/tools/update', { name, urls })
}
