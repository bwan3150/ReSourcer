import { getApiKey } from '../composables/useAuth'
import { getServerUrl } from '../composables/useServer'

/** Bump when server thumbnail algorithm changes so IndexedDB / HTTP caches refresh. */
export const THUMBNAIL_VERSION = '2'

export function thumbnailUrl(file, size = 300) {
  const base = getServerUrl()
  const key = getApiKey()
  const tv = `tv=${THUMBNAIL_VERSION}`
  if (file.uuid) {
    return `${base}/api/preview/thumbnail?uuid=${encodeURIComponent(file.uuid)}&size=${size}&${tv}&key=${key}`
  }
  return `${base}/api/preview/thumbnail?path=${encodeURIComponent(file.currentPath || file.path)}&size=${size}&${tv}&key=${key}`
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
