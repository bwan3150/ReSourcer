// Thumbnail cache using IndexedDB — works on HTTP, per-server isolation
import { getServerUrl } from './useServer'

const DB_NAME = 'resourcer-thumbnails'
const DB_VERSION = 1

function getStoreName() {
  const server = getServerUrl() || 'local'
  return server.replace(/[^a-zA-Z0-9.-]/g, '_')
}

function openDB() {
  return new Promise((resolve, reject) => {
    const req = indexedDB.open(DB_NAME, DB_VERSION)
    req.onupgradeneeded = (e) => {
      const db = e.target.result
      if (!db.objectStoreNames.contains('cache')) {
        db.createObjectStore('cache')
      }
    }
    req.onsuccess = () => resolve(req.result)
    req.onerror = () => reject(req.error)
  })
}

async function dbGet(key) {
  const db = await openDB()
  return new Promise((resolve) => {
    const tx = db.transaction('cache', 'readonly')
    const req = tx.objectStore('cache').get(key)
    req.onsuccess = () => resolve(req.result || null)
    req.onerror = () => resolve(null)
  })
}

async function dbPut(key, value) {
  const db = await openDB()
  return new Promise((resolve) => {
    const tx = db.transaction('cache', 'readwrite')
    tx.objectStore('cache').put(value, key)
    tx.oncomplete = () => resolve()
    tx.onerror = () => resolve()
  })
}

async function dbDelete(key) {
  const db = await openDB()
  return new Promise((resolve) => {
    const tx = db.transaction('cache', 'readwrite')
    tx.objectStore('cache').delete(key)
    tx.oncomplete = () => resolve()
    tx.onerror = () => resolve()
  })
}

async function dbGetAllKeys() {
  const db = await openDB()
  return new Promise((resolve) => {
    const tx = db.transaction('cache', 'readonly')
    const req = tx.objectStore('cache').getAllKeys()
    req.onsuccess = () => resolve(req.result || [])
    req.onerror = () => resolve([])
  })
}

// Cache key = storeName:url
function cacheKey(url) {
  return `${getStoreName()}:${url}`
}

/**
 * Get a thumbnail through IndexedDB cache.
 * Returns blob URL from cache or fetches and caches.
 */
export async function getCachedThumbnail(url) {
  if (!url) return url

  const key = cacheKey(url)

  try {
    // Check cache
    const cached = await dbGet(key)
    if (cached) {
      return URL.createObjectURL(cached)
    }

    // Fetch and cache
    const response = await fetch(url)
    if (response.ok) {
      const blob = await response.blob()
      await dbPut(key, blob)
      return URL.createObjectURL(blob)
    }
    // Server returned error (400/404/500) — no thumbnail available
    throw new Error(`Thumbnail failed: ${response.status}`)
  } catch (e) {
    throw e
  }
}

/**
 * Get cache statistics per server
 */
export async function getCacheStats() {
  try {
    const allKeys = await dbGetAllKeys()

    // Group by server (store name prefix)
    const serverMap = {}
    for (const key of allKeys) {
      const sep = key.indexOf(':')
      const server = sep > 0 ? key.substring(0, sep) : 'unknown'
      if (!serverMap[server]) serverMap[server] = 0
      serverMap[server]++
    }

    // Estimate sizes by sampling
    const stats = []
    for (const [server, count] of Object.entries(serverMap)) {
      // Sample up to 5 items to estimate average size
      const serverKeys = allKeys.filter(k => k.startsWith(server + ':'))
      let sampleSize = 0
      const sampleCount = Math.min(serverKeys.length, 5)
      for (let i = 0; i < sampleCount; i++) {
        const blob = await dbGet(serverKeys[i])
        if (blob) sampleSize += blob.size
      }
      const avgSize = sampleCount > 0 ? sampleSize / sampleCount : 0
      const estimatedTotal = Math.round(avgSize * count)

      stats.push({
        name: server,
        server: server.replace(/_/g, '/'),
        count,
        size: estimatedTotal,
        sizeLabel: formatBytes(estimatedTotal),
      })
    }

    return stats
  } catch {
    return []
  }
}

/**
 * Get total cache size
 */
export async function getTotalCacheSize() {
  const stats = await getCacheStats()
  return stats.reduce((sum, s) => sum + s.size, 0)
}

/**
 * Clear cache for a specific server
 */
export async function clearServerCache(serverName) {
  try {
    const allKeys = await dbGetAllKeys()
    const toDelete = allKeys.filter(k => k.startsWith(serverName + ':'))
    for (const key of toDelete) {
      await dbDelete(key)
    }
  } catch {}
}

/**
 * Clear all thumbnail caches
 */
export async function clearAllThumbnailCache() {
  try {
    const db = await openDB()
    return new Promise((resolve) => {
      const tx = db.transaction('cache', 'readwrite')
      tx.objectStore('cache').clear()
      tx.oncomplete = () => resolve()
      tx.onerror = () => resolve()
    })
  } catch {}
}

function formatBytes(bytes) {
  if (bytes < 1024) return bytes + ' B'
  if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(1) + ' KB'
  if (bytes < 1024 * 1024 * 1024) return (bytes / (1024 * 1024)).toFixed(1) + ' MB'
  return (bytes / (1024 * 1024 * 1024)).toFixed(2) + ' GB'
}
