import { ref, onMounted, onUnmounted } from 'vue'

// Default shortcuts
const DEFAULTS = {
  prevFile: 'Ctrl+ArrowLeft',
  nextFile: 'Ctrl+ArrowRight',
  seekForward: 'ArrowRight',
  seekBackward: 'ArrowLeft',
  playPause: ' ',           // Space
  volumeUp: 'ArrowUp',
  volumeDown: 'ArrowDown',
  toggleMute: 'm',
  fileInfo: 'i',
  exitPreview: 'Escape',
  zoomIn: '=',
  zoomOut: '-',
  pdfNextPage: 'Alt+ArrowDown',
  pdfPrevPage: 'Alt+ArrowUp',
  panUp: 'Alt+ArrowUp',
  panDown: 'Alt+ArrowDown',
  panLeft: 'Alt+ArrowLeft',
  panRight: 'Alt+ArrowRight',
  toggleUI: 'h',
  cycleTheme: 'Tab',
}

// Human-readable labels for settings UI
export const SHORTCUT_LABELS = {
  prevFile: 'Previous file',
  nextFile: 'Next file',
  seekForward: 'Seek forward 1s',
  seekBackward: 'Seek backward 1s',
  playPause: 'Play / Pause',
  volumeUp: 'Volume up 5%',
  volumeDown: 'Volume down 5%',
  toggleMute: 'Mute / Unmute',
  fileInfo: 'File info',
  exitPreview: 'Exit preview',
  zoomIn: 'Zoom in',
  zoomOut: 'Zoom out',
  pdfNextPage: 'PDF next page',
  pdfPrevPage: 'PDF prev page',
  toggleUI: 'Hide / Show UI',
  cycleTheme: 'Cycle theme',
}

// Icons for OSD feedback (lucide icon names)
export const SHORTCUT_ICONS = {
  prevFile: 'SkipBack',
  nextFile: 'SkipForward',
  seekForward: 'FastForward',
  seekBackward: 'Rewind',
  playPause: null, // dynamic: Play or Pause
  volumeUp: 'Volume2',
  volumeDown: 'Volume1',
  toggleMute: null, // dynamic: VolumeX or Volume2
  fileInfo: 'Info',
  exitPreview: 'X',
  zoomIn: 'ZoomIn',
  zoomOut: 'ZoomOut',
  pdfNextPage: 'ChevronDown',
  pdfPrevPage: 'ChevronUp',
  toggleUI: 'Eye',
  cycleTheme: 'Monitor',
}

function loadShortcuts() {
  try {
    const stored = localStorage.getItem('shortcuts')
    if (stored) return { ...DEFAULTS, ...JSON.parse(stored) }
  } catch {}
  return { ...DEFAULTS }
}

function saveShortcuts(shortcuts) {
  localStorage.setItem('shortcuts', JSON.stringify(shortcuts))
}

// Encode a keyboard event to string like "Alt+ArrowLeft", "Shift+m"
export function encodeKey(e) {
  const parts = []
  if (e.ctrlKey || e.metaKey) parts.push('Ctrl')
  if (e.altKey) parts.push('Alt')
  if (e.shiftKey) parts.push('Shift')
  let key = e.key
  if (key === ' ') key = 'Space'
  if (!['Control', 'Alt', 'Shift', 'Meta'].includes(key)) {
    parts.push(key)
  }
  return parts.join('+')
}

// Format for display: "Alt+ArrowLeft" → "⌥←"
export function formatShortcut(code) {
  if (!code) return ''
  return code
    .replace('Ctrl+', '⌃')
    .replace('Alt+', '⌥')
    .replace('Shift+', '⇧')
    .replace('ArrowLeft', '←')
    .replace('ArrowRight', '→')
    .replace('ArrowUp', '↑')
    .replace('ArrowDown', '↓')
    .replace('Escape', 'Esc')
    .replace('Space', '␣')
    .replace(' ', '␣')
    .replace('Tab', '⇥')
}

const shortcuts = ref(loadShortcuts())

export function getShortcuts() {
  return shortcuts.value
}

export function setShortcut(action, code) {
  shortcuts.value[action] = code
  saveShortcuts(shortcuts.value)
}

export function resetShortcuts() {
  shortcuts.value = { ...DEFAULTS }
  saveShortcuts(shortcuts.value)
}

// Match an event against a shortcut code
function matchEvent(e, code) {
  if (!code) return false
  const parts = code.split('+')
  const key = parts[parts.length - 1]
  const needAlt = parts.includes('Alt')
  const needCtrl = parts.includes('Ctrl')
  const needShift = parts.includes('Shift')

  let eventKey = e.key
  // Normalize space
  if (eventKey === ' ') eventKey = 'Space'
  let matchKey = key
  if (matchKey === ' ') matchKey = 'Space'

  // For single-char keys like '+', '-', '=', don't enforce shift matching
  // because '+' requires Shift on most keyboards
  const isSingleChar = parts.length === 1 && key.length === 1
  const shiftOk = isSingleChar || (e.shiftKey === needShift)

  return eventKey === matchKey
    && e.altKey === needAlt
    && (e.ctrlKey || e.metaKey) === needCtrl
    && shiftOk
}

/**
 * Use keyboard shortcuts in a component.
 * @param {Object} handlers - map of action name → callback function
 * @param {Function} isActive - return true when shortcuts should be active
 */
export function useKeyboardShortcuts(handlers, isActive = () => true) {
  function onKeydown(e) {
    if (!isActive()) return
    if (e.target.tagName === 'INPUT' || e.target.tagName === 'TEXTAREA' || e.target.tagName === 'SELECT') return

    const sc = shortcuts.value
    for (const [action, handler] of Object.entries(handlers)) {
      if (sc[action] && matchEvent(e, sc[action])) {
        e.preventDefault()
        handler(e)
        return
      }
    }
  }

  onMounted(() => window.addEventListener('keydown', onKeydown))
  onUnmounted(() => window.removeEventListener('keydown', onKeydown))
}

export { shortcuts, DEFAULTS }
