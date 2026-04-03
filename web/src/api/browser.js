import client from './client'

export function browse(path) {
  return client.post('/api/browser/browse', { path: path || '' })
}

export function createDirectory(parentPath, directoryName) {
  return client.post('/api/browser/create', { parentPath, directoryName })
}
