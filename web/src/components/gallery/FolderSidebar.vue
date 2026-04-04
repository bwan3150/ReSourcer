<template>
  <aside class="w-56 border-r border-base-300 flex flex-col h-full overflow-hidden shrink-0">
    <div class="flex-1 overflow-y-auto py-2 px-1">
      <FolderTreeNode
        v-for="folder in rootFolders"
        :key="folder.path"
        :folder="folder"
        :source-folder="sourceFolder"
        :active-path="activePath"
        :depth="0"
        @navigate="$emit('navigate', $event)"
      />
      <div v-if="!rootFolders.length && !loading" class="text-sm text-base-content/40 px-3 py-6 text-center">
        {{ $t('gallery.noFolders') }}
      </div>
      <div v-if="loading" class="flex justify-center py-6">
        <span class="loading loading-spinner loading-sm"></span>
      </div>
    </div>
  </aside>
</template>

<script setup>
import FolderTreeNode from './FolderTreeNode.vue'

defineProps({
  rootFolders: { type: Array, default: () => [] },
  sourceFolder: { type: String, default: '' },
  activePath: { type: String, default: '' },
  loading: { type: Boolean, default: false },
})

defineEmits(['navigate'])
</script>
