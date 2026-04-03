import axios from 'axios'
import { getApiKey, clearApiKey } from '../composables/useAuth'

function toSnake(str) {
  return str.replace(/[A-Z]/g, c => '_' + c.toLowerCase())
}
function toCamel(str) {
  return str.replace(/_([a-z])/g, (_, c) => c.toUpperCase())
}
function convertKeys(obj, fn) {
  if (Array.isArray(obj)) return obj.map(v => convertKeys(v, fn))
  if (obj && typeof obj === 'object' && !(obj instanceof File) && !(obj instanceof FormData)) {
    return Object.fromEntries(Object.entries(obj).map(([k, v]) => [fn(k), convertKeys(v, fn)]))
  }
  return obj
}

const client = axios.create({
  baseURL: window.__RESOURCER_API_BASE || '',
  timeout: 30000,
})

client.interceptors.request.use(config => {
  const key = getApiKey()
  if (key) config.headers['X-API-Key'] = key
  if (config.data && !(config.data instanceof FormData)) {
    config.data = convertKeys(config.data, toSnake)
  }
  return config
})

client.interceptors.response.use(
  res => {
    if (res.data && typeof res.data === 'object') {
      res.data = convertKeys(res.data, toCamel)
    }
    return res
  },
  err => {
    if (err.response?.status === 401) {
      clearApiKey()
      window.location.href = '/login'
    }
    return Promise.reject(err)
  }
)

export default client
