<template>
  <div
    class="card bg-base-100 shadow-sm hover:shadow-md transition-shadow cursor-pointer group overflow-hidden"
    @click="$emit('click', file)"
  >
    <figure class="relative aspect-square bg-base-200 overflow-hidden">
      <img
        v-if="hasThumb && cachedThumb"
        :src="cachedThumb"
        :alt="file.fileName"
        class="w-full h-full object-cover"
        loading="lazy"
      />
      <div v-if="isVideo && cachedThumb" class="absolute inset-0 flex items-center justify-center">
        <div class="bg-black/50 rounded-full p-3">
          <Play :size="24" class="text-white fill-white" />
        </div>
      </div>
      <div v-if="!cachedThumb && hasThumb" class="w-full h-full flex items-center justify-center">
        <span class="loading loading-spinner loading-sm text-base-content/20"></span>
      </div>
      <div v-if="!hasThumb" class="w-full h-full flex items-center justify-center">
        <FileText :size="32" class="text-base-content/30" />
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
import { Play, FileText } from 'lucide-vue-next'
import { thumbnailUrl } from '../../api/preview'
import { getCachedThumbnail } from '../../composables/useThumbnailCache'

const props = defineProps({
  file: { type: Object, required: true },
})
defineEmits(['click'])

const isImage = computed(() => props.file.fileType === 'image')
const isGif = computed(() => props.file.fileType === 'gif')
const isVideo = computed(() => props.file.fileType === 'video')
const isPdf = computed(() => props.file.fileType === 'pdf')
const hasThumb = computed(() => isImage.value || isGif.value || isVideo.value || isPdf.value)

const cachedThumb = ref(null)
let currentObjectUrl = null

async function loadThumb() {
  // Revoke previous object URL to free memory
  if (currentObjectUrl) {
    URL.revokeObjectURL(currentObjectUrl)
    currentObjectUrl = null
  }
  cachedThumb.value = null

  const url = thumbnailUrl(props.file)
  if (!url) return

  const result = await getCachedThumbnail(url)
  cachedThumb.value = result
  // Track if it's an object URL (blob:) so we can revoke it
  if (result.startsWith('blob:')) currentObjectUrl = result
}

watch(() => props.file.uuid, loadThumb, { immediate: true })

onUnmounted(() => {
  if (currentObjectUrl) URL.revokeObjectURL(currentObjectUrl)
})

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
