import { ref } from 'vue'

const serverUrl = ref(localStorage.getItem('server_url') || '')

export function getServerUrl() {
  return serverUrl.value
}

export function setServerUrl(url) {
  // Normalize: remove trailing slash
  const normalized = url ? url.replace(/\/+$/, '') : ''
  serverUrl.value = normalized
  localStorage.setItem('server_url', normalized)
}

export function useServer() {
  return { serverUrl, getServerUrl, setServerUrl }
}
