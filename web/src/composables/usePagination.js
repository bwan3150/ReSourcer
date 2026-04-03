import { ref } from 'vue'

export function usePagination(fetchFn, { pageSize = 50 } = {}) {
  const items = ref([])
  const total = ref(0)
  const offset = ref(0)
  const loading = ref(false)
  const hasMore = ref(false)

  async function load(reset = false) {
    if (loading.value) return
    if (reset) {
      offset.value = 0
      items.value = []
    }
    loading.value = true
    try {
      const res = await fetchFn(offset.value, pageSize)
      if (reset) {
        items.value = res.items
      } else {
        items.value.push(...res.items)
      }
      total.value = res.total
      hasMore.value = res.hasMore
      offset.value += res.items.length
    } finally {
      loading.value = false
    }
  }

  function reset() {
    items.value = []
    total.value = 0
    offset.value = 0
    hasMore.value = false
  }

  return { items, total, offset, loading, hasMore, load, reset }
}
