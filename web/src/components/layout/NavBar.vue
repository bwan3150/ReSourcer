<template>
  <div class="navbar bg-base-100 border-b border-base-300 px-4">
    <div class="flex-1">
      <router-link to="/" class="text-xl font-bold">ReSourcer</router-link>
    </div>
    <div class="flex-none">
      <ul class="menu menu-horizontal px-1 gap-1">
        <li><router-link to="/gallery" active-class="active">{{ $t('nav.gallery') }}</router-link></li>
        <li><router-link to="/classifier" active-class="active">{{ $t('nav.classifier') }}</router-link></li>
        <li><router-link to="/downloader" active-class="active">{{ $t('nav.downloader') }}</router-link></li>
        <li><router-link to="/settings" active-class="active">{{ $t('nav.settings') }}</router-link></li>
      </ul>
      <!-- Lang toggle -->
      <button class="btn btn-ghost btn-sm ml-2" @click="toggleLang">
        {{ locale === 'zh' ? 'EN' : '中文' }}
      </button>
      <!-- Theme toggle -->
      <button class="btn btn-ghost btn-sm" @click="toggleTheme">
        {{ isDark ? '☀️' : '🌙' }}
      </button>
      <!-- Logout -->
      <button class="btn btn-ghost btn-sm text-error" @click="logout">
        {{ $t('nav.logout') }}
      </button>
    </div>
  </div>
</template>

<script setup>
import { ref } from 'vue'
import { useRouter } from 'vue-router'
import { useI18n } from 'vue-i18n'
import { clearApiKey } from '../../composables/useAuth'
import { setLocale } from '../../i18n'

const { locale } = useI18n()
const router = useRouter()
const isDark = ref(document.documentElement.getAttribute('data-theme') === 'dark')

function toggleLang() {
  setLocale(locale.value === 'zh' ? 'en' : 'zh')
}

function toggleTheme() {
  isDark.value = !isDark.value
  document.documentElement.setAttribute('data-theme', isDark.value ? 'dark' : 'light')
  localStorage.setItem('theme', isDark.value ? 'dark' : 'light')
}

function logout() {
  clearApiKey()
  router.push('/login')
}

// Restore theme on load
const savedTheme = localStorage.getItem('theme') || 'dark'
document.documentElement.setAttribute('data-theme', savedTheme)
isDark.value = savedTheme === 'dark'
</script>
