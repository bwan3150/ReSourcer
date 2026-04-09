import {
  Music, Video, Image, FileCode, FileJson, FileSpreadsheet,
  FileArchive, FileType, File, FileText, Presentation, BookOpen
} from 'lucide-vue-next'

const codeExts = ['py', 'js', 'ts', 'jsx', 'tsx', 'rs', 'go', 'java', 'c', 'cpp', 'h', 'swift', 'kt', 'rb', 'php', 'sh', 'bash', 'css', 'scss', 'html', 'xml', 'yaml', 'yml', 'toml', 'sql', 'vue', 'svelte']
const dataExts = ['json', 'csv', 'tsv', 'plist']
const archiveExts = ['zip', 'rar', '7z', 'tar', 'gz', 'bz2', 'xz', 'dmg', 'iso']
const docExts = ['doc', 'docx', 'rtf', 'odt', 'pages']
const sheetExts = ['xls', 'xlsx', 'numbers', 'ods']
const slideExts = ['ppt', 'pptx', 'key', 'odp']
const fontExts = ['ttf', 'otf', 'woff', 'woff2']
const textExts = ['txt', 'md', 'log', 'ini', 'conf', 'cfg']

/**
 * Returns { icon, color } for a file based on its type and extension.
 * @param {string} fileType - 'image' | 'video' | 'audio' | 'gif' | 'pdf' | 'other'
 * @param {string} extension - file extension with or without dot
 */
export function getFileIcon(fileType, extension) {
  const ext = (extension || '').replace('.', '').toLowerCase()

  switch (fileType) {
    case 'audio': return { icon: Music, color: '#f59e0b' }
    case 'video': return { icon: Video, color: '#8b5cf6' }
    case 'image':
    case 'gif': return { icon: Image, color: '#3b82f6' }
    case 'pdf': return { icon: BookOpen, color: '#ef4444' }
  }

  if (codeExts.includes(ext)) return { icon: FileCode, color: '#22c55e' }
  if (dataExts.includes(ext)) return { icon: FileJson, color: '#f59e0b' }
  if (archiveExts.includes(ext)) return { icon: FileArchive, color: '#a855f7' }
  if (sheetExts.includes(ext)) return { icon: FileSpreadsheet, color: '#22c55e' }
  if (slideExts.includes(ext)) return { icon: Presentation, color: '#f97316' }
  if (docExts.includes(ext)) return { icon: FileText, color: '#3b82f6' }
  if (fontExts.includes(ext)) return { icon: FileType, color: '#06b6d4' }
  if (textExts.includes(ext)) return { icon: FileText, color: '#94a3b8' }

  return { icon: File, color: '#94a3b8' }
}
