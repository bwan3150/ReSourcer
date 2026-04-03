import { getApiKey } from '../composables/useAuth'

const BASE = window.__RESOURCER_API_BASE || ''

export function thumbnailUrl(file, size = 300) {
  const key = getApiKey()
  if (file.uuid) {
    return `${BASE}/api/preview/thumbnail?uuid=${encodeURIComponent(file.uuid)}&size=${size}&key=${key}`
  }
  return `${BASE}/api/preview/thumbnail?path=${encodeURIComponent(file.currentPath || file.path)}&size=${size}&key=${key}`
}

export function contentUrl(file) {
  const key = getApiKey()
  if (file.uuid) {
    return `${BASE}/api/preview/content/_?uuid=${encodeURIComponent(file.uuid)}&key=${key}`
  }
  const path = encodeURIComponent(file.currentPath || file.path)
  return `${BASE}/api/preview/content/${path}?key=${key}`
}
