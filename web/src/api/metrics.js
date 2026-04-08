import client from './client'

export function getCurrent() {
  return client.get('/api/metrics/current')
}

export function getHistory(minutes = 60) {
  return client.get('/api/metrics/history', { params: { minutes } })
}

export function getDiskDetails() {
  return client.get('/api/metrics/disk')
}

export function getSystemInfo() {
  return client.get('/api/metrics/system')
}
