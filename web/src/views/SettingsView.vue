<template>
  <AppLayout>
    <div class="max-w-3xl mx-auto p-6 space-y-6">
      <h1 class="text-2xl font-bold">{{ $t('settings.title') }}</h1>

      <!-- Source Folders -->
      <div class="card bg-base-100 shadow">
        <div class="card-body">
          <h2 class="card-title text-base">{{ $t('settings.sourceFolders') }}</h2>
          <SourceFolderManager
            :current="sourceFolder"
            :backups="backupSources"
            @switch="onSwitchSource"
            @remove="onRemoveSource"
            @browse="fileBrowser?.show()"
          />
        </div>
      </div>

      <!-- Category Folders -->
      <div class="card bg-base-100 shadow">
        <div class="card-body">
          <h2 class="card-title text-base">{{ $t('settings.categoryFolders') }}</h2>
          <CategoryManager :folders="categories" @toggle="toggleCategory" />
        </div>
      </div>

      <!-- Ignored Folders -->
      <div class="card bg-base-100 shadow">
        <div class="card-body">
          <h2 class="card-title text-base">{{ $t('settings.ignoredFolders') }}</h2>
          <IgnoreManager
            :items="ignoredFolders"
            :description="$t('settings.ignoredFoldersDesc')"
            @update="v => { ignoredFolders = v; saveSettings() }"
          />
        </div>
      </div>

      <!-- Ignored Files -->
      <div class="card bg-base-100 shadow">
        <div class="card-body">
          <h2 class="card-title text-base">{{ $t('settings.ignoredFiles') }}</h2>
          <IgnoreManager
            :items="ignoredFiles"
            :description="$t('settings.ignoredFilesDesc')"
            @update="v => { ignoredFiles = v; saveSettings() }"
          />
        </div>
      </div>

      <!-- Tools -->
      <div class="card bg-base-100 shadow">
        <div class="card-body">
          <h2 class="card-title text-base">{{ $t('settings.tools') }}</h2>
          <p class="text-xs text-base-content/50 mb-3">{{ $t('settings.toolsDesc') }}</p>
          <div class="space-y-4">
            <div v-for="tool in tools" :key="tool.name" class="border border-base-300 rounded-lg p-3">
              <div class="flex items-center justify-between mb-2">
                <div class="flex items-center gap-2">
                  <span class="font-medium text-sm">{{ tool.name }}</span>
                  <span class="badge badge-sm" :class="tool.installed ? 'badge-success' : 'badge-ghost'">
                    {{ tool.installed ? $t('settings.installed') : $t('settings.notInstalled') }}
                  </span>
                </div>
                <button
                  v-if="editingTool !== tool.name"
                  class="btn btn-ghost btn-xs"
                  @click="startEditTool(tool)"
                >
                  <Pencil :size="14" />
                </button>
              </div>
              <p class="text-xs text-base-content/50">{{ tool.description }}</p>

              <!-- Edit URLs -->
              <div v-if="editingTool === tool.name" class="mt-3 space-y-2">
                <div v-for="platform in ['linux_x86_64', 'linux_aarch64', 'macos', 'windows']" :key="platform">
                  <label class="label py-0"><span class="label-text text-xs">{{ platform }}</span></label>
                  <input
                    v-model="editUrls[platform]"
                    class="input input-bordered input-xs w-full font-mono"
                  />
                </div>
                <div class="flex gap-2 mt-2">
                  <button class="btn btn-primary btn-xs" @click="saveToolUrls(tool.name)">{{ $t('common.save') }}</button>
                  <button class="btn btn-ghost btn-xs" @click="editingTool = ''">{{ $t('common.cancel') }}</button>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>

      <!-- Reindex -->
      <div class="card bg-base-100 shadow">
        <div class="card-body">
          <div class="flex items-center justify-between">
            <h2 class="card-title text-base">{{ $t('settings.reindex') }}</h2>
            <button class="btn btn-outline btn-sm" @click="reindex" :disabled="reindexing">
              <span v-if="reindexing" class="loading loading-spinner loading-xs"></span>
              {{ reindexing ? $t('settings.reindexing') : $t('settings.reindex') }}
            </button>
          </div>
        </div>
      </div>

      <!-- Toast -->
      <div v-if="toast" class="toast toast-end">
        <div class="alert alert-success"><span>{{ toast }}</span></div>
      </div>
    </div>

    <FileBrowserModal ref="fileBrowser" @select="onAddSource" />
  </AppLayout>
</template>

<script setup>
import { ref, onMounted } from 'vue'
import { useI18n } from 'vue-i18n'
import { Pencil } from 'lucide-vue-next'
import AppLayout from '../components/layout/AppLayout.vue'
import SourceFolderManager from '../components/settings/SourceFolderManager.vue'
import CategoryManager from '../components/settings/CategoryManager.vue'
import IgnoreManager from '../components/settings/IgnoreManager.vue'
import FileBrowserModal from '../components/settings/FileBrowserModal.vue'
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

// Tools
const tools = ref([])
const editingTool = ref('')
const editUrls = ref({ linux_x86_64: '', linux_aarch64: '', macos: '', windows: '' })

onMounted(async () => {
  await loadSettings()
  await loadTools()
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
  // Poll status
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

function showToast(msg) {
  toast.value = msg
  setTimeout(() => { toast.value = '' }, 3000)
}
</script>
