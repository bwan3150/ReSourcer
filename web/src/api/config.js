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

export function migrateSource(oldPath, newPath) {
  return client.post('/api/config/sources/migrate', { oldPath, newPath })
}

export function checkWebUpdate() {
  return client.get('/api/app/web/check-update')
}

export function doWebUpdate() {
  return client.post('/api/app/web/update')
}

export function checkUpdate() {
  return client.get('/api/app/check-update')
}

export function doUpdate() {
  return client.post('/api/app/update')
}

/**
 * 轮询健康检查，等服务端自更新后重启完成。
 * 先等它掉线（确认真的重启了），再等它回来。
 */
export async function waitForServerRestart() {
  const { getServerUrl } = await import('../composables/useServer')
  const base = getServerUrl()
  const ping = async () => {
    try {
      const resp = await fetch(`${base}/api/health`)
      return resp.ok
    } catch {
      return false
    }
  }

  let wentDown = false
  for (let i = 0; i < 10; i++) {
    await new Promise(r => setTimeout(r, 500))
    if (!(await ping())) { wentDown = true; break }
  }
  // 5 秒内没掉线：可能重启得太快没抓到，再多等一会儿
  if (!wentDown) await new Promise(r => setTimeout(r, 2000))

  for (let i = 0; i < 30; i++) {
    if (await ping()) return true
    await new Promise(r => setTimeout(r, 1000))
  }
  return false
}

/**
 * 直接向 GitHub 查最新的 web-v* tag。
 * 仅在服务端没有托管网页端（独立部署）时作为兜底，拿不到就返回 null。
 */
export async function fetchLatestWebTag() {
  try {
    const resp = await fetch('https://api.github.com/repos/bwan3150/ReSourcer/tags?per_page=20', {
      headers: { 'Accept': 'application/vnd.github.v3+json' }
    })
    if (!resp.ok) return null
    const tags = await resp.json()
    const webTag = tags.find(t => t.name.startsWith('web-v'))
    return webTag ? webTag.name.replace('web-v', '') : null
  } catch {
    return null
  }
}
