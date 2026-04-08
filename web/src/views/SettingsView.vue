<template>
  <AppLayout>
    <template #header>
      <h1 class="text-lg font-semibold flex-1">{{ $t('settings.title') }}</h1>
    </template>

    <div class="max-w-2xl mx-auto p-6">
      <div class="join join-vertical w-full">
        <!-- Source Folders -->
        <div class="collapse collapse-arrow join-item border border-base-300">
          <input type="radio" name="settings-accordion" />
          <div class="collapse-title font-medium text-sm flex items-center gap-2">
            <FolderCog :size="18" class="text-base-content/50" />
            {{ $t('settings.sourceFolders') }}
            <span v-if="sourceFolder" class="text-xs text-base-content/40 ml-auto mr-4 truncate max-w-48">{{ sourceFolder }}</span>
          </div>
          <div class="collapse-content">
            <SourceFolderManager
              :current="sourceFolder"
              :backups="backupSources"
              @switch="onSwitchSource"
              @remove="onRemoveSource"
              @browse="fileBrowser?.show()"
              @migrated="loadSettings"
            />
          </div>
        </div>

        <!-- Category Folders -->
        <div class="collapse collapse-arrow join-item border border-base-300">
          <input type="radio" name="settings-accordion" />
          <div class="collapse-title font-medium text-sm flex items-center gap-2">
            <Folders :size="18" class="text-base-content/50" />
            {{ $t('settings.categoryFolders') }}
          </div>
          <div class="collapse-content">
            <CategoryManager :folders="categories" @toggle="toggleCategory" />
          </div>
        </div>

        <!-- Ignore Rules -->
        <div class="collapse collapse-arrow join-item border border-base-300">
          <input type="radio" name="settings-accordion" />
          <div class="collapse-title font-medium text-sm flex items-center gap-2">
            <EyeOff :size="18" class="text-base-content/50" />
            {{ $t('settings.ignoreRules') }}
          </div>
          <div class="collapse-content space-y-5">
            <div>
              <h3 class="text-sm font-medium mb-2">{{ $t('settings.ignoredFolders') }}</h3>
              <IgnoreManager
                :items="ignoredFolders"
                :description="$t('settings.ignoredFoldersDesc')"
                @update="v => { ignoredFolders = v; saveSettings() }"
              />
            </div>
            <div>
              <h3 class="text-sm font-medium mb-2">{{ $t('settings.ignoredFiles') }}</h3>
              <IgnoreManager
                :items="ignoredFiles"
                :description="$t('settings.ignoredFilesDesc')"
                @update="v => { ignoredFiles = v; saveSettings() }"
              />
            </div>
          </div>
        </div>

        <!-- Tools -->
        <div class="collapse collapse-arrow join-item border border-base-300">
          <input type="radio" name="settings-accordion" />
          <div class="collapse-title font-medium text-sm flex items-center gap-2">
            <Wrench :size="18" class="text-base-content/50" />
            {{ $t('settings.tools') }}
          </div>
          <div class="collapse-content space-y-3">
            <p class="text-xs text-base-content/40 mb-2">{{ $t('settings.toolsDesc') }}</p>
            <div v-for="tool in tools" :key="tool.name" class="border border-base-300 rounded-lg p-3">
              <div class="flex items-center justify-between mb-1">
                <div class="flex items-center gap-2">
                  <span class="font-medium text-sm">{{ tool.name }}</span>
                  <span class="badge badge-sm" :class="tool.installed ? 'badge-outline' : 'badge-ghost'">
                    {{ tool.installed ? $t('settings.installed') : $t('settings.notInstalled') }}
                  </span>
                </div>
                <button v-if="editingTool !== tool.name" class="btn btn-ghost btn-xs" @click="startEditTool(tool)">
                  <Pencil :size="14" />
                </button>
              </div>
              <p class="text-xs text-base-content/40">{{ tool.description }}</p>
              <div v-if="editingTool === tool.name" class="mt-3 space-y-2">
                <div v-for="platform in ['linux_x86_64', 'linux_aarch64', 'macos', 'windows']" :key="platform">
                  <label class="label py-0"><span class="label-text text-xs">{{ platform }}</span></label>
                  <input v-model="editUrls[platform]" class="input input-bordered input-xs w-full font-mono" />
                </div>
                <div class="flex gap-2 mt-2">
                  <button class="btn btn-neutral btn-xs" @click="saveToolUrls(tool.name)">{{ $t('common.save') }}</button>
                  <button class="btn btn-ghost btn-xs" @click="editingTool = ''">{{ $t('common.cancel') }}</button>
                </div>
              </div>
            </div>
          </div>
        </div>

        <!-- Reindex -->
        <div class="collapse collapse-arrow join-item border border-base-300">
          <input type="radio" name="settings-accordion" />
          <div class="collapse-title font-medium text-sm flex items-center gap-2">
            <RefreshCw :size="18" class="text-base-content/50" />
            {{ $t('settings.reindex') }}
          </div>
          <div class="collapse-content">
            <p class="text-sm text-base-content/50 mb-3">{{ $t('settings.reindexDesc') }}</p>
            <button class="btn btn-neutral btn-sm" @click="reindex" :disabled="reindexing">
              <span v-if="reindexing" class="loading loading-spinner loading-xs"></span>
              {{ reindexing ? $t('settings.reindexing') : $t('settings.reindex') }}
            </button>
          </div>
        </div>

        <!-- Cache -->
        <div class="collapse collapse-arrow join-item border border-base-300">
          <input type="radio" name="settings-accordion" />
          <div class="collapse-title font-medium text-sm flex items-center gap-2">
            <HardDrive :size="18" class="text-base-content/50" />
            {{ $t('settings.cache') }}
            <span v-if="cacheSize" class="text-xs text-base-content/40 ml-auto mr-4">{{ cacheSize }}</span>
          </div>
          <div class="collapse-content">
            <div class="space-y-3 text-sm">
              <p class="text-xs text-base-content/40">{{ $t('settings.cacheDesc') }}</p>

              <!-- Per-server breakdown (if available) -->
              <div v-if="cacheDetails.length" class="space-y-1">
                <div v-for="item in cacheDetails" :key="item.name" class="flex justify-between items-center py-1">
                  <span class="text-xs truncate flex-1">{{ item.server }}</span>
                  <span class="text-xs text-base-content/40 mr-2">{{ item.count }} items &middot; {{ item.sizeLabel }}</span>
                  <button class="btn btn-ghost btn-xs text-error" @click="clearCacheByName(item.name)">
                    <Trash2 :size="12" />
                  </button>
                </div>
              </div>

              <div class="flex gap-2">
                <button class="btn btn-ghost btn-xs gap-1" @click="refreshCacheInfo">
                  <RefreshCw :size="14" />
                  {{ $t('common.refresh') }}
                </button>
                <button class="btn btn-ghost btn-xs gap-1 text-error" @click="clearAllCache">
                  <Trash2 :size="14" />
                  {{ $t('settings.clearCache') }}
                </button>
              </div>
            </div>
          </div>
        </div>

        <!-- Shortcuts -->
        <div class="collapse collapse-arrow join-item border border-base-300">
          <input type="radio" name="settings-accordion" />
          <div class="collapse-title font-medium text-sm flex items-center gap-2">
            <Keyboard :size="18" class="text-base-content/50" />
            {{ $t('settings.shortcuts') }}
          </div>
          <div class="collapse-content">
            <div class="space-y-1">
              <div
                v-for="(label, action) in shortcutLabels"
                :key="action"
                class="flex justify-between items-center py-1.5"
              >
                <span class="text-xs">{{ label }}</span>
                <button
                  class="btn btn-ghost btn-xs font-mono min-w-16"
                  :class="{ 'btn-outline': listeningAction === action }"
                  @click="startListening(action)"
                >
                  {{ listeningAction === action ? '...' : formatShortcut(currentShortcuts[action]) }}
                </button>
              </div>
            </div>
            <div class="mt-3">
              <button class="btn btn-ghost btn-xs" @click="doResetShortcuts">
                {{ $t('settings.resetShortcuts') }}
              </button>
            </div>
          </div>
        </div>

        <!-- About -->
        <div class="collapse collapse-arrow join-item border border-base-300">
          <input type="radio" name="settings-accordion" />
          <div class="collapse-title font-medium text-sm flex items-center gap-2">
            <Info :size="18" class="text-base-content/50" />
            {{ $t('settings.about') }}
          </div>
          <div class="collapse-content">
            <div class="space-y-2 text-sm">
              <div class="flex justify-between items-center">
                <span class="text-base-content/50">{{ $t('settings.webVersion') }}</span>
                <div class="flex items-center gap-2">
                  <span>{{ webVersion }}</span>
                  <span v-if="hasWebUpdate" class="badge badge-outline badge-xs">{{ latestWebVersion }}</span>
                  <span v-if="hasWebUpdate" class="text-xs text-base-content/40">docker compose pull</span>
                  <button v-if="!hasWebUpdate" class="btn btn-ghost btn-xs" @click="checkWebUpdateOnly" :disabled="checkingWeb">
                    <span v-if="checkingWeb" class="loading loading-spinner loading-xs"></span>
                    <RefreshCw v-else :size="14" />
                  </button>
                </div>
              </div>
              <div class="flex justify-between items-center">
                <span class="text-base-content/50">{{ $t('settings.serverVersion') }}</span>
                <div class="flex items-center gap-2">
                  <span>{{ serverVersion || '—' }}</span>
                  <span v-if="hasServerUpdate" class="badge badge-outline badge-xs">{{ latestVersion }}</span>
                  <button
                    v-if="hasServerUpdate"
                    class="btn btn-ghost btn-xs"
                    @click="doServerUpdate"
                    :disabled="updating"
                  >
                    <span v-if="updating" class="loading loading-spinner loading-xs"></span>
                    <Download v-else :size="14" />
                  </button>
                  <button v-else class="btn btn-ghost btn-xs" @click="checkServerUpdateOnly" :disabled="checkingServer">
                    <span v-if="checkingServer" class="loading loading-spinner loading-xs"></span>
                    <RefreshCw v-else :size="14" />
                  </button>
                </div>
              </div>
              <div class="flex gap-2 mt-4">
                <a v-if="iosUrl" :href="iosUrl" target="_blank" rel="noopener" class="btn btn-ghost btn-xs gap-1">
                  <Smartphone :size="16" />
                  iOS
                </a>
                <a v-if="githubUrl" :href="githubUrl" target="_blank" rel="noopener" class="btn btn-ghost btn-xs gap-1">
                  <Github :size="16" />
                  GitHub
                </a>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>

    <!-- Toast -->
    <div v-if="toast" class="toast toast-end">
      <div class="alert"><span>{{ toast }}</span></div>
    </div>

    <FileBrowserModal ref="fileBrowser" @select="onAddSource" />
  </AppLayout>
</template>

<script setup>
import { ref, onMounted } from 'vue'
import { useI18n } from 'vue-i18n'
import { FolderCog, Folders, EyeOff, Wrench, RefreshCw, Pencil, Info, Github, Download, Smartphone, HardDrive, Trash2, Keyboard } from 'lucide-vue-next'
import { SHORTCUT_LABELS, getShortcuts, setShortcut, resetShortcuts, formatShortcut, encodeKey } from '../composables/useKeyboardShortcuts'
import AppLayout from '../components/layout/AppLayout.vue'
import SourceFolderManager from '../components/settings/SourceFolderManager.vue'
import CategoryManager from '../components/settings/CategoryManager.vue'
import IgnoreManager from '../components/settings/IgnoreManager.vue'
import FileBrowserModal from '../components/settings/FileBrowserModal.vue'
import { getCacheStats, getTotalCacheSize, clearServerCache, clearAllThumbnailCache } from '../composables/useThumbnailCache'
import * as configApi from '../api/config'
import * as folderApi from '../api/folder'
import * as indexerApi from '../api/indexer'

const { t } = useI18n()

const sourceFolder = ref('')
const backupSources = ref([])
const categories = ref([])
const hiddenFolders = ref([])
const ignoredFolders = ref([])
const ignoredFiles = ref([])
const reindexing = ref(false)
const toast = ref('')
const fileBrowser = ref(null)
const tools = ref([])
const editingTool = ref('')
const editUrls = ref({ linux_x86_64: '', linux_aarch64: '', macos: '', windows: '' })

// About & Update
const webVersion = __APP_VERSION__
const serverVersion = ref('')
const githubUrl = ref('')
const iosUrl = ref('')
const latestVersion = ref('')
const hasServerUpdate = ref(false)
const latestWebVersion = ref('')
const hasWebUpdate = ref(false)
const checkingWeb = ref(false)
const checkingServer = ref(false)
const checking = ref(false)
const updating = ref(false)

// Shortcuts
const shortcutLabels = SHORTCUT_LABELS
const currentShortcuts = ref(getShortcuts())
const listeningAction = ref('')

function startListening(action) {
  listeningAction.value = action
  const handler = (e) => {
    e.preventDefault()
    e.stopPropagation()
    const code = encodeKey(e)
    if (code && !['Control', 'Alt', 'Shift', 'Meta'].includes(e.key)) {
      setShortcut(action, code)
      currentShortcuts.value = getShortcuts()
      listeningAction.value = ''
      window.removeEventListener('keydown', handler, true)
    }
  }
  window.addEventListener('keydown', handler, true)
}

function doResetShortcuts() {
  resetShortcuts()
  currentShortcuts.value = getShortcuts()
  showToast(t('settings.saveSuccess'))
}

// Cache
const cacheSize = ref('')
const cacheDetails = ref([])

onMounted(async () => {
  await loadSettings()
  await loadTools()
  refreshCacheInfo()
  try {
    const { data } = await configApi.getAppInfo()
    serverVersion.value = data.version || ''
    githubUrl.value = data.githubUrl || ''
    iosUrl.value = data.iosUrl || ''
  } catch {}
})

async function loadSettings() {
  try {
    const { data } = await configApi.getConfigState()
    sourceFolder.value = data.sourceFolder || ''
    hiddenFolders.value = data.hiddenFolders || []
    ignoredFolders.value = data.ignoredFolders || []
    ignoredFiles.value = data.ignoredFiles || []

    const { data: sources } = await configApi.getSources()
    backupSources.value = sources.backups || []

    if (sourceFolder.value) {
      const { data: folderList } = await folderApi.listFolders(sourceFolder.value)
      categories.value = folderList
    }
  } catch {}
}

async function saveSettings() {
  try {
    await configApi.saveConfig({
      sourceFolder: sourceFolder.value,
      hiddenFolders: hiddenFolders.value,
      ignoredFolders: ignoredFolders.value,
      ignoredFiles: ignoredFiles.value,
    })
    showToast(t('settings.saveSuccess'))
  } catch {}
}

async function onSwitchSource(path) {
  await configApi.switchSource(path)
  await loadSettings()
}

async function onRemoveSource(path) {
  await configApi.removeSource(path)
  await loadSettings()
}

async function onAddSource(path) {
  await configApi.addSource(path)
  await loadSettings()
}

async function toggleCategory(folder) {
  if (folder.hidden) {
    hiddenFolders.value = hiddenFolders.value.filter(f => f !== folder.name)
  } else {
    hiddenFolders.value.push(folder.name)
  }
  await saveSettings()
  await loadSettings()
}

async function reindex() {
  reindexing.value = true
  try {
    await indexerApi.triggerScan(sourceFolder.value, true)
    showToast(t('settings.reindexing'))
  } catch {}
  const poll = setInterval(async () => {
    try {
      const { data } = await indexerApi.getScanStatus()
      if (!data.isScanning) {
        clearInterval(poll)
        reindexing.value = false
        showToast(t('settings.saveSuccess'))
      }
    } catch { clearInterval(poll); reindexing.value = false }
  }, 2000)
}

async function loadTools() {
  try {
    const { data } = await configApi.getTools()
    tools.value = data.tools || []
  } catch {}
}

function startEditTool(tool) {
  editingTool.value = tool.name
  editUrls.value = { ...tool.urls }
}

async function saveToolUrls(name) {
  try {
    await configApi.updateToolUrls(name, editUrls.value)
    editingTool.value = ''
    await loadTools()
    showToast(t('settings.saveSuccess'))
  } catch {}
}

async function checkWebUpdateOnly() {
  checkingWeb.value = true
  try {
    const resp = await fetch('https://api.github.com/repos/bwan3150/ReSourcer/tags?per_page=20', {
      headers: { 'Accept': 'application/vnd.github.v3+json' }
    })
    if (resp.ok) {
      const tags = await resp.json()
      const webTag = tags.find(t => t.name.startsWith('web-v'))
      if (webTag) {
        const latest = webTag.name.replace('web-v', '')
        latestWebVersion.value = latest
        hasWebUpdate.value = latest !== webVersion
      }
    }
    if (!hasWebUpdate.value) showToast(t('settings.upToDate'))
  } catch {}
  checkingWeb.value = false
}

async function checkServerUpdateOnly() {
  checkingServer.value = true
  try {
    const { data } = await configApi.checkUpdate()
    latestVersion.value = data.latestVersion || ''
    hasServerUpdate.value = data.hasUpdate || false
    if (!data.hasUpdate) showToast(t('settings.upToDate'))
  } catch {}
  checkingServer.value = false
}

async function doServerUpdate() {
  updating.value = true
  try {
    await configApi.doUpdate()
    showToast(t('settings.updateStarted'))
  } catch {}
  updating.value = false
}

async function refreshCacheInfo() {
  const stats = await getCacheStats()
  cacheDetails.value = stats
  const total = stats.reduce((sum, s) => sum + s.size, 0)
  cacheSize.value = formatBytes(total)
}

async function clearCacheByName(name) {
  await clearServerCache(name)
  showToast(t('settings.cacheCleared'))
  await refreshCacheInfo()
}

async function clearAllCache() {
  await clearAllThumbnailCache()
  showToast(t('settings.cacheCleared'))
  await refreshCacheInfo()
}

function formatBytes(bytes) {
  if (!bytes) return '0 B'
  if (bytes < 1024) return bytes + ' B'
  if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(1) + ' KB'
  if (bytes < 1024 * 1024 * 1024) return (bytes / (1024 * 1024)).toFixed(1) + ' MB'
  return (bytes / (1024 * 1024 * 1024)).toFixed(2) + ' GB'
}

function showToast(msg) {
  toast.value = msg
  setTimeout(() => { toast.value = '' }, 3000)
}
</script>
