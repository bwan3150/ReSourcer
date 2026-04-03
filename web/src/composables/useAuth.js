import { ref, computed } from 'vue'

const apiKey = ref(localStorage.getItem('api_key') || '')

export function getApiKey() {
  return apiKey.value
}

export function setApiKey(key) {
  apiKey.value = key
  localStorage.setItem('api_key', key)
  document.cookie = `api_key=${key};path=/;max-age=${30 * 24 * 3600}`
}

export function clearApiKey() {
  apiKey.value = ''
  localStorage.removeItem('api_key')
  document.cookie = 'api_key=;path=/;max-age=0'
}

export function useAuth() {
  const isAuthenticated = computed(() => !!apiKey.value)
  return { apiKey, isAuthenticated, getApiKey, setApiKey, clearApiKey }
}
