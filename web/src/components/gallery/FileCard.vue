<template>
  <div
    class="card bg-base-100 shadow-sm hover:shadow-md transition-shadow cursor-pointer group overflow-hidden relative"
    :class="{ 'ring-2 ring-primary': selectMode && selected }"
    @click="onClick"
  >
    <figure class="relative aspect-square bg-base-200 overflow-hidden">
      <img
        v-if="hasThumb && cachedThumb"
        :src="cachedThumb"
        :alt="file.fileName"
        class="w-full h-full object-cover select-none"
        loading="lazy"
        draggable="false"
      />
      <div v-if="isVideo && cachedThumb" class="absolute inset-0 flex items-center justify-center">
        <div class="bg-black/50 rounded-full p-3">
          <Play :size="24" class="text-white fill-white" />
        </div>
      </div>
      <div v-if="!cachedThumb && hasThumb && !thumbFailed" class="w-full h-full flex items-center justify-center">
        <span class="loading loading-spinner loading-sm text-base-content/20"></span>
      </div>
      <!-- Fallback icon: thumb failed or no thumbnail type -->
      <div v-if="(!hasThumb) || (thumbFailed && !cachedThumb)" class="w-full h-full flex items-center justify-center">
        <component :is="fileIconInfo.icon" :size="32" :style="{ color: fileIconInfo.color }" />
      </div>

      <!-- Selection checkbox -->
      <div
        v-if="selectMode"
        class="absolute top-1.5 left-1.5 z-10"
        @click.stop="$emit('toggle-select', file)"
      >
        <div
          class="w-5 h-5 rounded-full border-2 flex items-center justify-center transition-colors"
          :class="selected
            ? 'bg-primary border-primary text-primary-content'
            : 'bg-base-100/80 border-base-content/40'"
        >
          <Check v-if="selected" :size="12" :stroke-width="3" />
        </div>
      </div>

      <!-- File type badge -->
      <div class="absolute top-1 right-1 badge badge-sm" :class="typeBadgeClass">
        {{ file.extension?.replace('.', '').toUpperCase() }}
      </div>
    </figure>
    <div class="p-2">
      <p class="text-xs truncate" :title="file.fileName">{{ file.fileName }}</p>
    </div>
  </div>
</template>

<script setup>
import { ref, computed, watch, onUnmounted } from 'vue'
import { Play, Check } from 'lucide-vue-next'
import { thumbnailUrl } from '../../api/preview'
import { getCachedThumbnail } from '../../composables/useThumbnailCache'
import { getFileIcon } from '../../composables/useFileIcon'

const props = defineProps({
  file: { type: Object, required: true },
  selectMode: { type: Boolean, default: false },
  selected: { type: Boolean, default: false },
})
const emit = defineEmits(['click', 'toggle-select'])

function onClick() {
  if (props.selectMode) {
    emit('toggle-select', props.file)
  } else {
    emit('click', props.file)
  }
}

const isImage = computed(() => props.file.fileType === 'image')
const isGif = computed(() => props.file.fileType === 'gif')
const isVideo = computed(() => props.file.fileType === 'video')
const isPdf = computed(() => props.file.fileType === 'pdf')
const isAudio = computed(() => props.file.fileType === 'audio')
const hasThumb = computed(() => isImage.value || isGif.value || isVideo.value || isPdf.value || isAudio.value)

const cachedThumb = ref(null)
const thumbFailed = ref(false)
let currentObjectUrl = null

async function loadThumb() {
  if (currentObjectUrl) {
    URL.revokeObjectURL(currentObjectUrl)
    currentObjectUrl = null
  }
  cachedThumb.value = null
  thumbFailed.value = false

  if (!hasThumb.value) return
  const url = thumbnailUrl(props.file)
  if (!url) return

  try {
    const result = await getCachedThumbnail(url)
    cachedThumb.value = result
    if (result.startsWith('blob:')) currentObjectUrl = result
  } catch {
    // No thumbnail available — for audio/pdf this is expected (no cover / broken file),
    // fall back to file type icon instead of showing error question mark
    thumbFailed.value = true
  }
}

watch(() => props.file.uuid, loadThumb, { immediate: true })

onUnmounted(() => {
  if (currentObjectUrl) URL.revokeObjectURL(currentObjectUrl)
})

const fileIconInfo = computed(() => getFileIcon(props.file.fileType, props.file.extension))

const typeBadgeClass = computed(() => {
  switch (props.file.fileType) {
    case 'image': return 'badge-ghost'
    case 'video': return 'badge-outline'
    case 'gif': return 'badge-outline'
    case 'audio': return 'badge-ghost'
    default: return 'badge-ghost'
  }
})
</script>
