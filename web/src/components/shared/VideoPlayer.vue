<template>
  <div class="relative group">
    <video
      ref="videoEl"
      :src="src"
      class="w-full h-full object-contain bg-black"
      :controls="controls"
      preload="metadata"
      playsinline
      @click="togglePlay"
    />
  </div>
</template>

<script setup>
import { ref } from 'vue'

defineProps({
  src: { type: String, required: true },
  controls: { type: Boolean, default: true },
})

const videoEl = ref(null)

function togglePlay() {
  if (!videoEl.value) return
  if (videoEl.value.paused) videoEl.value.play()
  else videoEl.value.pause()
}

defineExpose({ videoEl })
</script>
