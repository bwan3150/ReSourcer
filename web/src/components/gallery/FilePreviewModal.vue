<template>
  <dialog ref="dialogEl" class="modal" @close="$emit('close')" @keydown="onKeydown">
    <div class="modal-box max-w-7xl w-[95vw] h-[90vh] flex flex-col p-0 overflow-hidden">
      <!-- Header -->
      <div class="flex items-center justify-between px-4 py-2 border-b border-base-300 shrink-0">
        <div class="flex items-center gap-2 min-w-0">
          <span class="text-sm font-medium truncate">{{ file?.fileName }}</span>
          <span class="text-xs text-base-content/50">{{ currentIndex + 1 }} {{ $t('gallery.of') }} {{ total }}</span>
        </div>
        <div class="flex gap-1">
          <button class="btn btn-ghost btn-sm btn-square" @click="$emit('rename', file)" :title="$t('common.rename')">
            <Pencil :size="16" />
          </button>
          <button class="btn btn-ghost btn-sm btn-square" @click="$emit('move', file)" :title="$t('common.move')">
            <FolderInput :size="16" />
          </button>
          <button class="btn btn-ghost btn-sm btn-square" @click="close">
            <X :size="16" />
          </button>
        </div>
      </div>

      <!-- Content -->
      <div class="flex-1 flex items-center justify-center relative bg-black min-h-0 overflow-hidden">
        <button
          v-if="currentIndex > 0"
          class="absolute left-2 z-10 btn btn-circle btn-ghost text-white bg-black/30 hover:bg-black/50"
          @click.stop="$emit('prev')"
        >
          <ChevronLeft :size="20" />
        </button>

        <img
          v-if="isImage || isGif"
          :src="contentSrc"
          :alt="file?.fileName"
          class="max-w-full max-h-full object-contain"
        />
        <video
          v-else-if="isVideo"
          :key="contentSrc"
          :src="contentSrc"
          controls
          autoplay
          class="max-w-full max-h-full object-contain"
        />
        <div v-else class="text-base-content/50 text-lg">
          {{ file?.fileName }}
        </div>

        <button
          v-if="currentIndex < total - 1"
          class="absolute right-2 z-10 btn btn-circle btn-ghost text-white bg-black/30 hover:bg-black/50"
          @click.stop="$emit('next')"
        >
          <ChevronRight :size="20" />
        </button>
      </div>

      <!-- Info bar -->
      <div class="px-4 py-2 border-t border-base-300 flex flex-wrap gap-4 text-xs text-base-content/60 shrink-0">
        <span>{{ formatSize(file?.fileSize) }}</span>
        <span>{{ file?.extension?.replace('.', '').toUpperCase() }}</span>
        <span v-if="file?.sourceUrl" class="flex items-center gap-1 truncate max-w-xs" :title="file.sourceUrl">
          <Link :size="12" /> {{ file.sourceUrl }}
        </span>
      </div>
    </div>
    <form method="dialog" class="modal-backdrop"><button>close</button></form>
  </dialog>
</template>

<script setup>
import { computed, ref } from 'vue'
import { Pencil, FolderInput, X, ChevronLeft, ChevronRight, Link } from 'lucide-vue-next'
import { contentUrl } from '../../api/preview'

const props = defineProps({
  file: { type: Object, default: null },
  currentIndex: { type: Number, default: 0 },
  total: { type: Number, default: 0 },
})

const emit = defineEmits(['close', 'prev', 'next', 'rename', 'move'])
const dialogEl = ref(null)

const isImage = computed(() => ['image', 'gif'].includes(props.file?.fileType))
const isGif = computed(() => props.file?.fileType === 'gif')
const isVideo = computed(() => props.file?.fileType === 'video')
const contentSrc = computed(() => props.file ? contentUrl(props.file) : '')

function show() { dialogEl.value?.showModal() }
function close() { dialogEl.value?.close() }

function onKeydown(e) {
  if (e.key === 'ArrowLeft') emit('prev')
  else if (e.key === 'ArrowRight') emit('next')
  else if (e.key === 'Escape') close()
}

function formatSize(bytes) {
  if (!bytes) return ''
  if (bytes < 1024) return bytes + ' B'
  if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(1) + ' KB'
  return (bytes / (1024 * 1024)).toFixed(1) + ' MB'
}

defineExpose({ show, close })
</script>
