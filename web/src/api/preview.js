import { getApiKey } from '../composables/useAuth'
import { getServerUrl } from '../composables/useServer'

export function thumbnailUrl(file, size = 300) {
  const base = getServerUrl()
  const key = getApiKey()
  if (file.uuid) {
    return `${base}/api/preview/thumbnail?uuid=${encodeURIComponent(file.uuid)}&size=${size}&key=${key}`
  }
  return `${base}/api/preview/thumbnail?path=${encodeURIComponent(file.currentPath || file.path)}&size=${size}&key=${key}`
}

export function contentUrl(file) {
  const base = getServerUrl()
  const key = getApiKey()
  if (file.uuid) {
    return `${base}/api/preview/content/_?uuid=${encodeURIComponent(file.uuid)}&key=${key}`
  }
  const path = encodeURIComponent(file.currentPath || file.path)
  return `${base}/api/preview/content/${path}?key=${key}`
}
