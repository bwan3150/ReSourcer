<template>
  <dialog ref="dialogEl" class="modal">
    <div class="modal-box max-w-lg">
      <h3 class="font-bold text-lg mb-4">{{ $t('settings.browse') }}</h3>

      <!-- Breadcrumb -->
      <div class="text-sm breadcrumbs mb-3">
        <ul>
          <li v-for="(part, i) in pathParts" :key="i">
            <a class="cursor-pointer" @click="navigateTo(part.path)">{{ part.name }}</a>
          </li>
        </ul>
      </div>

      <!-- Directory list -->
      <div class="max-h-60 overflow-y-auto border border-base-300 rounded-lg">
        <div v-if="parentPath" class="p-2 hover:bg-base-200 cursor-pointer border-b border-base-300 flex items-center gap-2" @click="navigateTo(parentPath)">
          <Folder :size="16" /> ..
        </div>
        <div
          v-for="item in items.filter(i => i.isDirectory)"
          :key="item.path"
          class="p-2 hover:bg-base-200 cursor-pointer flex items-center gap-2"
          :class="{ 'bg-base-300': selectedPath === item.path }"
          @click="selectedPath = item.path"
          @dblclick="navigateTo(item.path)"
        >
          <Folder :size="16" /> {{ item.name }}
        </div>
        <div v-if="!items.filter(i => i.isDirectory).length" class="p-4 text-center text-base-content/50 text-sm">
          {{ $t('settings.noFolders') }}
        </div>
      </div>

      <!-- New folder -->
      <div class="flex gap-2 mt-3">
        <input
          v-model="newDirName"
          :placeholder="$t('settings.createFolder')"
          class="input input-bordered input-sm flex-1"
          @keyup.enter="createDir"
        />
        <button class="btn btn-sm btn-ghost btn-square" @click="createDir" :disabled="!newDirName.trim()">
          <Plus :size="16" />
        </button>
      </div>

      <!-- Selected path -->
      <div v-if="selectedPath" class="mt-3 text-sm text-base-content truncate">{{ selectedPath }}</div>

      <div class="modal-action">
        <button class="btn" @click="close">{{ $t('common.cancel') }}</button>
        <button class="btn btn-neutral" @click="confirmSelect" :disabled="!effectivePath">{{ $t('common.confirm') }}</button>
      </div>
    </div>
    <form method="dialog" class="modal-backdrop"><button>close</button></form>
  </dialog>
</template>

<script setup>
import { ref, computed } from 'vue'
import { Folder, Plus } from 'lucide-vue-next'
import * as browserApi from '../../api/browser'

const emit = defineEmits(['select'])
const dialogEl = ref(null)
const currentPath = ref('')
const parentPath = ref('')
const items = ref([])
const selectedPath = ref('')
const newDirName = ref('')

const effectivePath = computed(() => selectedPath.value || currentPath.value)

const pathParts = computed(() => {
  if (!currentPath.value) return [{ name: '/', path: '' }]
  const parts = currentPath.value.split('/').filter(Boolean)
  return [
    { name: '/', path: '' },
    ...parts.map((name, i) => ({ name, path: '/' + parts.slice(0, i + 1).join('/') })),
  ]
})

async function navigateTo(path) {
  try {
    const { data } = await browserApi.browse(path)
    currentPath.value = data.currentPath
    parentPath.value = data.parentPath || ''
    items.value = data.items || []
    selectedPath.value = ''
  } catch {}
}

async function createDir() {
  if (!newDirName.value.trim()) return
  try {
    await browserApi.createDirectory(currentPath.value, newDirName.value.trim())
    newDirName.value = ''
    await navigateTo(currentPath.value)
  } catch {}
}

function show(initialPath) {
  navigateTo(initialPath || '')
  dialogEl.value?.showModal()
}

function close() { dialogEl.value?.close() }

function confirmSelect() {
  emit('select', effectivePath.value)
  close()
}

defineExpose({ show, close })
</script>
