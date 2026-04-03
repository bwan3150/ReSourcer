import { createI18n } from 'vue-i18n'
import en from './en'
import zh from './zh'

export const i18n = createI18n({
  legacy: false,
  locale: localStorage.getItem('lang') || 'zh',
  fallbackLocale: 'en',
  messages: { en, zh },
})

export function setLocale(lang) {
  i18n.global.locale.value = lang
  localStorage.setItem('lang', lang)
  document.documentElement.lang = lang
}
