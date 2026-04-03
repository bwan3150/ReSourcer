<template>
  <div
    class="card bg-base-100 shadow-sm hover:shadow-md transition-shadow cursor-pointer group overflow-hidden"
    @click="$emit('click', file)"
  >
    <figure class="relative aspect-square bg-base-200 overflow-hidden">
      <img
        v-if="isImage || isGif"
        :src="thumb"
        :alt="file.fileName"
        class="w-full h-full object-cover"
        loading="lazy"
        @error="imgError = true"
      />
      <div v-else-if="isVideo" class="w-full h-full flex items-center justify-center relative">
        <img
          :src="thumb"
          :alt="file.fileName"
          class="w-full h-full object-cover"
          loading="lazy"
          @error="imgError = true"
        />
        <div class="absolute inset-0 flex items-center justify-center">
          <div class="bg-black/50 rounded-full p-3">
            <svg class="w-8 h-8 text-white" fill="currentColor" viewBox="0 0 24 24"><path d="M8 5v14l11-7z"/></svg>
          </div>
        </div>
      </div>
      <div v-else class="w-full h-full flex items-center justify-center text-4xl text-base-content/30">
        📄
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
import { computed, ref } from 'vue'
import { thumbnailUrl } from '../../api/preview'

const props = defineProps({
  file: { type: Object, required: true },
})
defineEmits(['click'])

const imgError = ref(false)

const isImage = computed(() => props.file.fileType === 'image')
const isGif = computed(() => props.file.fileType === 'gif')
const isVideo = computed(() => props.file.fileType === 'video')

const thumb = computed(() => thumbnailUrl(props.file))

const typeBadgeClass = computed(() => {
  switch (props.file.fileType) {
    case 'image': return 'badge-info'
    case 'video': return 'badge-warning'
    case 'gif': return 'badge-success'
    case 'audio': return 'badge-secondary'
    default: return 'badge-ghost'
  }
})
</script>
