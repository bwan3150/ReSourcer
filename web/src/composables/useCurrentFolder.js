import { ref } from 'vue'

const sourceFolder = ref('')
const currentFolder = ref('')

export function getSourceFolder() { return sourceFolder.value }
export function getCurrentFolder() { return currentFolder.value }

export function setSourceFolder(path) {
  sourceFolder.value = path
  if (!currentFolder.value) currentFolder.value = path
}

export function setCurrentFolder(path) {
  currentFolder.value = path
}

export function useCurrentFolder() {
  return { sourceFolder, currentFolder, setSourceFolder, setCurrentFolder }
}
