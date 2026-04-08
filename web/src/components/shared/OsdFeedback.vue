<template>
  <transition name="osd">
    <div v-if="visible" class="fixed inset-0 flex items-center justify-center z-50 pointer-events-none">
      <div class="bg-black/60 rounded-2xl p-4">
        <component :is="currentIcon" :size="32" class="text-white" />
      </div>
    </div>
  </transition>
</template>

<script setup>
import { ref, shallowRef } from 'vue'
import * as icons from 'lucide-vue-next'

const visible = ref(false)
const currentIcon = shallowRef(null)
let timer = null

function show(iconName) {
  if (!iconName || !icons[iconName]) return
  currentIcon.value = icons[iconName]
  visible.value = true
  clearTimeout(timer)
  timer = setTimeout(() => { visible.value = false }, 600)
}

defineExpose({ show })
</script>

<style scoped>
.osd-enter-active { transition: opacity 0.15s ease-in; }
.osd-leave-active { transition: opacity 0.4s ease-out; }
.osd-enter-from, .osd-leave-to { opacity: 0; }
</style>
