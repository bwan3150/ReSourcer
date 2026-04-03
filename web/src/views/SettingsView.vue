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

onMounted(loadSettings)

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

function showToast(msg) {
  toast.value = msg
  setTimeout(() => { toast.value = '' }, 3000)
}
</script>
