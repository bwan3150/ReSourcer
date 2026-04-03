<template>
  <aside class="w-64 bg-base-200 border-r border-base-300 flex flex-col h-full overflow-hidden">
    <!-- Source folder selector -->
    <div class="p-3 border-b border-base-300">
      <select class="select select-bordered select-sm w-full" :value="sourceFolder" @change="$emit('switchSource', $event.target.value)">
        <option v-for="s in sources" :key="s" :value="s">{{ folderName(s) }}</option>
      </select>
    </div>

    <!-- Folder tree -->
    <div class="flex-1 overflow-y-auto p-2">
      <!-- Root (source folder itself) -->
      <button
        class="btn btn-ghost btn-sm w-full justify-start gap-2 mb-1"
        :class="{ 'btn-active': currentFolder === sourceFolder }"
        @click="$emit('select', sourceFolder)"
      >
        <FolderOpen :size="16" />
        {{ folderName(sourceFolder) }}
      </button>

      <!-- Subfolders -->
      <div v-for="folder in folders" :key="folder.path" class="ml-3">
        <button
          class="btn btn-ghost btn-sm w-full justify-start gap-2 text-left"
          :class="{ 'btn-active': currentFolder === folder.path }"
          @click="$emit('select', folder.path)"
        >
          <Folder :size="16" class="shrink-0" />
          <span class="truncate">{{ folder.name }}</span>
          <span class="badge badge-sm badge-ghost ml-auto">{{ folder.fileCount }}</span>
        </button>
      </div>

      <div v-if="!folders.length && !loading" class="text-sm text-base-content/50 p-3">
        {{ $t('gallery.noFolders') }}
      </div>
      <div v-if="loading" class="flex justify-center p-4">
        <span class="loading loading-spinner loading-sm"></span>
      </div>
    </div>
  </aside>
</template>

<script setup>
import { Folder, FolderOpen } from 'lucide-vue-next'

defineProps({
  sourceFolder: { type: String, default: '' },
  sources: { type: Array, default: () => [] },
  folders: { type: Array, default: () => [] },
  currentFolder: { type: String, default: '' },
  loading: { type: Boolean, default: false },
})

defineEmits(['select', 'switchSource'])

function folderName(path) {
  return path.split('/').filter(Boolean).pop() || path
}
</script>
