// Thumbnail cache using Cache API — per-server isolation, inspectable, clearable
import { getServerUrl } from './useServer'

function getCacheName() {
  const server = getServerUrl() || 'local'
  // Sanitize server URL to use as cache name
  return `thumbnails-${server.replace(/[^a-zA-Z0-9.-]/g, '_')}`
}

/**
 * Get a thumbnail URL that goes through Cache API.
 * Returns an object URL from cache if available, otherwise fetches and caches.
 */
export async function getCachedThumbnail(url) {
  if (!url || !window.caches) return url

  const cacheName = getCacheName()

  try {
    const cache = await caches.open(cacheName)

    // Check cache first
    const cached = await cache.match(url)
    if (cached) {
      const blob = await cached.blob()
      return URL.createObjectURL(blob)
    }

    // Fetch and cache
    const response = await fetch(url)
    if (response.ok) {
      // Clone before consuming — one for cache, one for display
      await cache.put(url, response.clone())
      const blob = await response.blob()
      return URL.createObjectURL(blob)
    }
  } catch {
    // Fallback to direct URL on any error
  }

  return url
}

/**
 * Get cache statistics for all servers
 */
export async function getCacheStats() {
  if (!window.caches) return []

  const stats = []
  try {
    const names = await caches.keys()
    for (const name of names) {
      if (!name.startsWith('thumbnails-')) continue

      const cache = await caches.open(name)
      const keys = await cache.keys()

      // Estimate size by sampling
      let totalSize = 0
      const sampleCount = Math.min(keys.length, 10)
      for (let i = 0; i < sampleCount; i++) {
        try {
          const res = await cache.match(keys[i])
          if (res) {
            const blob = await res.blob()
            totalSize += blob.size
          }
        } catch {}
      }

      // Extrapolate from sample
      const avgSize = sampleCount > 0 ? totalSize / sampleCount : 0
      const estimatedTotal = Math.round(avgSize * keys.length)

      // Extract server name from cache name
      const serverLabel = name.replace('thumbnails-', '').replace(/_/g, '/')

      stats.push({
        name,
        server: serverLabel,
        count: keys.length,
        size: estimatedTotal,
        sizeLabel: formatBytes(estimatedTotal),
      })
    }
  } catch {}

  return stats
}

/**
 * Get total cache size across all servers
 */
export async function getTotalCacheSize() {
  const stats = await getCacheStats()
  return stats.reduce((sum, s) => sum + s.size, 0)
}

/**
 * Clear cache for a specific server
 */
export async function clearServerCache(cacheName) {
  if (window.caches) {
    await caches.delete(cacheName)
  }
}

/**
 * Clear all thumbnail caches
 */
export async function clearAllThumbnailCache() {
  if (!window.caches) return
  const names = await caches.keys()
  await Promise.all(
    names.filter(n => n.startsWith('thumbnails-')).map(n => caches.delete(n))
  )
}

function formatBytes(bytes) {
  if (bytes < 1024) return bytes + ' B'
  if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(1) + ' KB'
  if (bytes < 1024 * 1024 * 1024) return (bytes / (1024 * 1024)).toFixed(1) + ' MB'
  return (bytes / (1024 * 1024 * 1024)).toFixed(2) + ' GB'
}
