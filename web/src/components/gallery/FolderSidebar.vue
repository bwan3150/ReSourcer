<template>
  <aside class="w-56 border-r border-base-300 flex flex-col h-full overflow-hidden shrink-0">
    <div class="flex-1 overflow-y-auto py-2 px-2 space-y-0.5">
      <!-- Go up / Go root (when not at source root) -->
      <template v-if="showNavButtons">
        <button
          class="flex items-center gap-2 px-3 py-2 rounded-lg text-sm w-full text-left transition-colors hover:bg-base-200 text-base-content/60"
          @click="$emit('goRoot')"
        >
          <Home :size="14" class="shrink-0" />
          <span class="truncate">{{ $t('gallery.rootFolder') }}</span>
        </button>
        <button
          class="flex items-center gap-2 px-3 py-2 rounded-lg text-sm w-full text-left transition-colors hover:bg-base-200 text-base-content/60"
          @click="$emit('goUp')"
        >
          <ArrowUp :size="14" class="shrink-0" />
          <span class="truncate">..</span>
        </button>
        <div class="border-b border-base-300 my-1"></div>
      </template>

      <!-- Subfolders -->
      <button
        v-for="folder in folders"
        :key="folder.path"
        class="flex items-center gap-2 px-3 py-2 rounded-lg text-sm w-full text-left transition-colors hover:bg-base-200"
        @click="$emit('select', folder.path)"
      >
        <Folder :size="16" class="shrink-0 text-base-content/40" />
        <span class="truncate flex-1">{{ folder.name }}</span>
        <span v-if="folder.fileCount" class="text-xs text-base-content/40">{{ folder.fileCount }}</span>
        <ChevronRight :size="14" class="shrink-0 text-base-content/30" />
      </button>

      <div v-if="!folders.length && !loading" class="text-sm text-base-content/40 px-3 py-6 text-center">
        {{ $t('gallery.noFolders') }}
      </div>
      <div v-if="loading" class="flex justify-center py-6">
        <span class="loading loading-spinner loading-sm"></span>
      </div>
    </div>
  </aside>
</template>

<script setup>
import { Folder, ChevronRight, ArrowUp, Home } from 'lucide-vue-next'

defineProps({
  folders: { type: Array, default: () => [] },
  loading: { type: Boolean, default: false },
  showNavButtons: { type: Boolean, default: false },
})

defineEmits(['select', 'goUp', 'goRoot'])
</script>
