import { createI18n } from 'vue-i18n'
import en from './en'
import zh from './zh'

function detectLocale() {
  const stored = localStorage.getItem('lang')
  if (stored) return stored
  const nav = navigator.language || navigator.languages?.[0] || 'en'
  return nav.startsWith('zh') ? 'zh' : 'en'
}

export const i18n = createI18n({
  legacy: false,
  locale: detectLocale(),
  fallbackLocale: 'en',
  messages: { en, zh },
})

export function setLocale(lang) {
  i18n.global.locale.value = lang
  localStorage.setItem('lang', lang)
  document.documentElement.lang = lang
}
