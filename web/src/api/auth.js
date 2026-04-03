import client from './client'

export function verifyApiKey(apiKey) {
  return client.post('/api/auth/verify', { apiKey })
}

export function checkAuth() {
  return client.get('/api/auth/check')
}
