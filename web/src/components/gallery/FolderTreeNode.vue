<template>
  <div>
    <!-- This folder row -->
    <div
      class="flex items-center gap-1 px-2 py-1.5 rounded-lg text-sm transition-colors hover:bg-base-200 group"
      :class="{ 'bg-base-300': isActive }"
      :style="{ paddingLeft: (depth * 12 + 8) + 'px' }"
    >
      <!-- Expand/collapse toggle -->
      <button
        class="shrink-0 w-5 h-5 flex items-center justify-center rounded hover:bg-base-300 transition-colors"
        @click="toggle"
      >
        <FolderOpen v-if="expanded" :size="14" class="text-base-content/50" />
        <Folder v-else :size="14" class="text-base-content/40" />
      </button>

      <!-- Folder name (click to expand too) -->
      <span class="truncate flex-1 cursor-pointer" @click="toggle">{{ folder.name }}</span>

      <!-- File count -->
      <span v-if="folder.fileCount" class="text-xs text-base-content/30 shrink-0">{{ folder.fileCount }}</span>

      <!-- Navigate button (go to this folder) -->
      <button
        class="shrink-0 w-5 h-5 flex items-center justify-center rounded hover:bg-base-300 opacity-0 group-hover:opacity-100 transition-opacity"
        @click="$emit('navigate', folder.path)"
        :title="$t('common.open')"
      >
        <ArrowRight :size="12" class="text-base-content/50" />
      </button>
    </div>

    <!-- Children (lazy loaded) -->
    <div v-if="expanded">
      <div v-if="loadingChildren" class="flex justify-center py-2" :style="{ paddingLeft: ((depth + 1) * 12 + 8) + 'px' }">
        <span class="loading loading-spinner loading-xs"></span>
      </div>
      <FolderTreeNode
        v-for="child in children"
        :key="child.path"
        :folder="child"
        :source-folder="sourceFolder"
        :active-path="activePath"
        :depth="depth + 1"
        @navigate="$emit('navigate', $event)"
      />
      <div
        v-if="!loadingChildren && !children.length"
        class="text-xs text-base-content/30 py-1"
        :style="{ paddingLeft: ((depth + 1) * 12 + 16) + 'px' }"
      >
        {{ $t('gallery.noFolders') }}
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, computed } from 'vue'
import { Folder, FolderOpen, ArrowRight } from 'lucide-vue-next'
import * as indexerApi from '../../api/indexer'

const props = defineProps({
  folder: { type: Object, required: true },
  sourceFolder: { type: String, default: '' },
  activePath: { type: String, default: '' },
  depth: { type: Number, default: 0 },
})

defineEmits(['navigate'])

const expanded = ref(false)
const children = ref([])
const loadingChildren = ref(false)
const loaded = ref(false)

const isActive = computed(() => props.activePath === props.folder.path)

async function toggle() {
  expanded.value = !expanded.value
  if (expanded.value && !loaded.value) {
    loadingChildren.value = true
    try {
      const { data } = await indexerApi.getFolders(props.folder.path, props.sourceFolder)
      children.value = data
    } catch { children.value = [] }
    loaded.value = true
    loadingChildren.value = false
  }
}
</script>
