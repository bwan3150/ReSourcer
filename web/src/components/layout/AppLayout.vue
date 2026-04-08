<template>
  <div class="flex h-screen overflow-hidden">
    <!-- Sidebar -->
    <aside
      class="flex flex-col bg-base-200 border-r border-base-300 shrink-0 transition-all duration-200"
      :class="expanded ? 'w-56' : 'w-16'"
    >
      <!-- Logo / toggle -->
      <div class="flex items-center justify-center h-14 border-b border-base-300 cursor-pointer select-none" @click="toggleSidebar">
        <span v-if="expanded" class="font-bold text-lg">ReSourcer</span>
        <span v-else class="font-bold text-lg">Re</span>
      </div>

      <!-- Nav items -->
      <nav class="flex-1 py-2 space-y-1 px-2">
        <router-link
          v-for="item in navItems"
          :key="item.to"
          :to="item.to"
          class="flex items-center gap-3 px-3 py-2 rounded-lg text-sm transition-colors hover:bg-base-300"
          :class="{ 'bg-base-300 font-medium': isActive(item.to) }"
        >
          <component :is="item.icon" :size="20" />
          <span v-if="expanded" class="truncate">{{ $t(item.label) }}</span>
        </router-link>
      </nav>

      <!-- Bottom actions -->
      <div class="px-2 py-3 border-t border-base-300 space-y-1">
        <button class="flex items-center gap-3 px-3 py-2 rounded-lg text-sm w-full hover:bg-base-300 transition-colors" @click="toggleLang">
          <Languages :size="20" />
          <span v-if="expanded">{{ locale === 'zh' ? 'EN' : '中文' }}</span>
        </button>
        <button class="flex items-center gap-3 px-3 py-2 rounded-lg text-sm w-full hover:bg-base-300 transition-colors" @click="cycle">
          <component :is="themeIcon" :size="20" />
          <span v-if="expanded">{{ themeLabel }}</span>
        </button>
        <button class="flex items-center gap-3 px-3 py-2 rounded-lg text-sm w-full hover:bg-base-300 transition-colors text-error" @click="logout">
          <LogOut :size="20" />
          <span v-if="expanded">{{ $t('nav.logout') }}</span>
        </button>
      </div>
    </aside>

    <!-- Main -->
    <div class="flex-1 flex flex-col min-w-0 overflow-hidden">
      <!-- Header — each view provides its own content -->
      <header v-if="$slots.header" class="flex items-center h-14 px-4 border-b border-base-300 shrink-0 gap-3">
        <slot name="header" />
      </header>

      <!-- Content -->
      <main class="flex-1 overflow-auto">
        <slot />
      </main>
    </div>
  </div>
</template>

<script>
// Module-level state — survives component re-creation across routes
import { ref } from 'vue'
const sidebarExpanded = ref(localStorage.getItem('sidebar') !== 'collapsed')
</script>

<script setup>
import { computed } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { useI18n } from 'vue-i18n'
import { clearApiKey } from '../../composables/useAuth'
import { useTheme } from '../../composables/useTheme'
import { setLocale } from '../../i18n'
import { Image, FolderOpen, Download, Settings, LogOut, Languages, Sun, Moon, Monitor } from 'lucide-vue-next'

const { locale, t } = useI18n()
const route = useRoute()
const router = useRouter()
const { mode, cycle } = useTheme()
const expanded = sidebarExpanded

function toggleSidebar() {
  expanded.value = !expanded.value
  localStorage.setItem('sidebar', expanded.value ? 'expanded' : 'collapsed')
}

const navItems = [
  { to: '/gallery', label: 'nav.gallery', icon: Image },
  { to: '/classifier', label: 'nav.classifier', icon: FolderOpen },
  { to: '/downloader', label: 'nav.downloader', icon: Download },
  { to: '/settings', label: 'nav.settings', icon: Settings },
]

const themeIcon = computed(() => {
  if (mode.value === 'light') return Sun
  if (mode.value === 'dark') return Moon
  return Monitor
})

const themeLabel = computed(() => t(`nav.theme_${mode.value}`))

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
