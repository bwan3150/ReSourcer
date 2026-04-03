<template>
  <div class="flex h-screen overflow-hidden">
    <!-- Sidebar -->
    <aside
      class="flex flex-col bg-base-200 border-r border-base-300 shrink-0 transition-all duration-200"
      :class="expanded ? 'w-56' : 'w-16'"
    >
      <!-- Logo / toggle -->
      <div class="flex items-center h-14 px-3 border-b border-base-300">
        <button class="btn btn-ghost btn-sm p-1" @click="expanded = !expanded">
          <Menu :size="20" />
        </button>
        <span v-if="expanded" class="ml-2 font-bold text-lg truncate">ReSourcer</span>
      </div>

      <!-- Nav items -->
      <nav class="flex-1 py-2 space-y-1 px-2">
        <router-link
          v-for="item in navItems"
          :key="item.to"
          :to="item.to"
          class="flex items-center gap-3 px-3 py-2 rounded-lg text-sm transition-colors hover:bg-base-300"
          :class="{ 'bg-primary/10 text-primary': isActive(item.to) }"
        >
          <component :is="item.icon" :size="20" />
          <span v-if="expanded" class="truncate">{{ $t(item.label) }}</span>
        </router-link>
      </nav>

      <!-- Bottom actions -->
      <div class="px-2 py-3 border-t border-base-300 space-y-1">
        <!-- Language -->
        <button class="flex items-center gap-3 px-3 py-2 rounded-lg text-sm w-full hover:bg-base-300 transition-colors" @click="toggleLang">
          <Languages :size="20" />
          <span v-if="expanded">{{ locale === 'zh' ? 'English' : '中文' }}</span>
        </button>

        <!-- Theme -->
        <button class="flex items-center gap-3 px-3 py-2 rounded-lg text-sm w-full hover:bg-base-300 transition-colors" @click="cycle">
          <component :is="themeIcon" :size="20" />
          <span v-if="expanded">{{ themeLabel }}</span>
        </button>

        <!-- Logout -->
        <button class="flex items-center gap-3 px-3 py-2 rounded-lg text-sm w-full hover:bg-base-300 transition-colors text-error" @click="logout">
          <LogOut :size="20" />
          <span v-if="expanded">{{ $t('nav.logout') }}</span>
        </button>
      </div>
    </aside>

    <!-- Main -->
    <div class="flex-1 flex flex-col min-w-0 overflow-hidden">
      <!-- Top bar -->
      <header class="flex items-center h-14 px-4 border-b border-base-300 shrink-0 gap-3">
        <h1 class="text-lg font-semibold">{{ $t(`nav.${currentRouteName}`) }}</h1>
        <slot name="toolbar" />
      </header>

      <!-- Content -->
      <main class="flex-1 overflow-auto">
        <slot />
      </main>
    </div>
  </div>
</template>

<script setup>
import { ref, computed } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { useI18n } from 'vue-i18n'
import { clearApiKey } from '../../composables/useAuth'
import { useTheme } from '../../composables/useTheme'
import { setLocale } from '../../i18n'
import { Image, FolderOpen, Download, Settings, LogOut, Languages, Sun, Moon, Monitor, Menu } from 'lucide-vue-next'

const { locale } = useI18n()
const route = useRoute()
const router = useRouter()
const { mode, cycle } = useTheme()
const expanded = ref(true)

const navItems = [
  { to: '/gallery', label: 'nav.gallery', icon: Image },
  { to: '/classifier', label: 'nav.classifier', icon: FolderOpen },
  { to: '/downloader', label: 'nav.downloader', icon: Download },
  { to: '/settings', label: 'nav.settings', icon: Settings },
]

const currentRouteName = computed(() => route.name || 'gallery')

const themeIcon = computed(() => {
  if (mode.value === 'light') return Sun
  if (mode.value === 'dark') return Moon
  return Monitor
})

const themeLabel = computed(() => {
  const labels = { system: 'System', light: 'Light', dark: 'Dark' }
  return labels[mode.value]
})

function isActive(path) {
  return route.path.startsWith(path)
}

function toggleLang() {
  setLocale(locale.value === 'zh' ? 'en' : 'zh')
}

function logout() {
  clearApiKey()
  router.push('/login')
}
</script>
