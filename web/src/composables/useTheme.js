import { ref, watchEffect } from 'vue'

const mode = ref(localStorage.getItem('theme') || 'system')
const effectiveTheme = ref('dark')

const mediaQuery = window.matchMedia('(prefers-color-scheme: dark)')

function getEffectiveTheme() {
  if (mode.value === 'system') {
    return mediaQuery.matches ? 'dark' : 'light'
  }
  return mode.value
}

function applyTheme() {
  const theme = getEffectiveTheme()
  effectiveTheme.value = theme
  document.documentElement.setAttribute('data-theme', theme)
}

mediaQuery.addEventListener('change', () => {
  if (mode.value === 'system') applyTheme()
})

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

  return { mode, effectiveTheme, cycle, setMode }
}

// Standalone getter for components that don't need the full composable
export { effectiveTheme }
