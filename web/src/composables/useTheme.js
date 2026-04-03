import { ref, watchEffect, onUnmounted } from 'vue'

const mode = ref(localStorage.getItem('theme') || 'system')

const mediaQuery = window.matchMedia('(prefers-color-scheme: dark)')

function getEffectiveTheme() {
  if (mode.value === 'system') {
    return mediaQuery.matches ? 'dark' : 'light'
  }
  return mode.value
}

function applyTheme() {
  document.documentElement.setAttribute('data-theme', getEffectiveTheme())
}

// Listen for system theme changes
function onSystemChange() {
  if (mode.value === 'system') applyTheme()
}
mediaQuery.addEventListener('change', onSystemChange)

// Apply on load
applyTheme()

export function useTheme() {
  watchEffect(applyTheme)

  function setMode(m) {
    mode.value = m
    localStorage.setItem('theme', m)
    applyTheme()
  }

  function cycle() {
    const next = { system: 'light', light: 'dark', dark: 'system' }
    setMode(next[mode.value] || 'system')
  }

  return { mode, cycle, setMode }
}
