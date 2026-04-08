<template>
  <div ref="container" class="relative w-full h-full overflow-auto flex justify-center" @scroll="onScroll">
    <div class="py-4 space-y-2">
      <canvas
        v-for="p in renderedPages"
        :key="p"
        :ref="el => setCanvasRef(el, p)"
        class="shadow-md mx-auto block"
      />
    </div>
    <!-- Page indicator -->
    <div v-if="totalPages > 0" class="absolute bottom-4 left-1/2 -translate-x-1/2 bg-black/60 text-white text-xs px-3 py-1 rounded-full pointer-events-none">
      {{ currentPage }} / {{ totalPages }}
    </div>
  </div>
</template>

<script setup>
import { ref, watch, onUnmounted, nextTick } from 'vue'
import * as pdfjsLib from 'pdfjs-dist'

pdfjsLib.GlobalWorkerOptions.workerSrc = new URL(
  'pdfjs-dist/build/pdf.worker.min.mjs',
  import.meta.url
).href

const props = defineProps({
  src: { type: String, default: '' },
})

const container = ref(null)
const totalPages = ref(0)
const currentPage = ref(1)
const renderedPages = ref([])
const fitMode = ref('width') // 'width' or 'height'
const canvasRefs = {}

let pdfDoc = null
let renderScale = 2

function setCanvasRef(el, page) {
  if (el) canvasRefs[page] = el
}

watch(() => props.src, async (src) => {
  if (!src) return
  cleanup()
  try {
    const loadingTask = pdfjsLib.getDocument(src)
    pdfDoc = await loadingTask.promise
    totalPages.value = pdfDoc.numPages
    renderedPages.value = Array.from({ length: pdfDoc.numPages }, (_, i) => i + 1)
    await nextTick()
    for (let i = 1; i <= pdfDoc.numPages; i++) {
      await renderPage(i)
    }
  } catch (e) {
    console.error('PDF load error:', e)
  }
}, { immediate: true })

async function renderPage(pageNum) {
  if (!pdfDoc) return
  const page = await pdfDoc.getPage(pageNum)
  const canvas = canvasRefs[pageNum]
  if (!canvas) return

  const containerWidth = container.value?.clientWidth || 800
  const containerHeight = container.value?.clientHeight || 600
  const viewport = page.getViewport({ scale: 1 })

  let fitScale
  if (fitMode.value === 'height') {
    fitScale = (containerHeight - 16) / viewport.height
  } else {
    fitScale = (containerWidth - 32) / viewport.width
  }

  const scaledViewport = page.getViewport({ scale: fitScale * renderScale })

  canvas.width = scaledViewport.width
  canvas.height = scaledViewport.height
  canvas.style.width = `${scaledViewport.width / renderScale}px`
  canvas.style.height = `${scaledViewport.height / renderScale}px`

  const ctx = canvas.getContext('2d')
  await page.render({ canvasContext: ctx, viewport: scaledViewport }).promise
}

async function rerenderAll() {
  if (!pdfDoc) return
  for (let i = 1; i <= pdfDoc.numPages; i++) {
    await renderPage(i)
  }
}

function toggleFitMode() {
  fitMode.value = fitMode.value === 'width' ? 'height' : 'width'
  rerenderAll()
}

function onScroll() {
  if (!container.value) return

  let bestPage = 1
  let bestOverlap = 0

  for (const [pageStr, canvas] of Object.entries(canvasRefs)) {
    const page = parseInt(pageStr)
    const rect = canvas.getBoundingClientRect()
    const containerRect = container.value.getBoundingClientRect()
    const top = Math.max(rect.top, containerRect.top)
    const bottom = Math.min(rect.bottom, containerRect.bottom)
    const overlap = Math.max(0, bottom - top)
    if (overlap > bestOverlap) {
      bestOverlap = overlap
      bestPage = page
    }
  }
  currentPage.value = bestPage
}

function cleanup() {
  if (pdfDoc) {
    pdfDoc.destroy()
    pdfDoc = null
  }
  totalPages.value = 0
  currentPage.value = 1
  renderedPages.value = []
  Object.keys(canvasRefs).forEach(k => delete canvasRefs[k])
}

onUnmounted(cleanup)

function scrollBy(dx, dy) {
  if (!container.value) return
  container.value.scrollBy({ left: dx, top: dy, behavior: 'smooth' })
}

defineExpose({ toggleFitMode, scrollBy, fitMode, currentPage, totalPages })
</script>
