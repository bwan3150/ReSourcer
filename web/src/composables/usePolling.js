import { onUnmounted, ref } from 'vue'

export function usePolling(fn, interval = 2000) {
  const active = ref(false)
  let timer = null

  function start() {
    if (active.value) return
    active.value = true
    tick()
  }

  function stop() {
    active.value = false
    if (timer) {
      clearTimeout(timer)
      timer = null
    }
  }

  async function tick() {
    if (!active.value) return
    try {
      await fn()
    } catch { /* ignore */ }
    if (active.value) {
      timer = setTimeout(tick, interval)
    }
  }

  onUnmounted(stop)

  return { active, start, stop }
}
