import { ref, reactive } from 'vue'

// 私密源文件夹管理（纯本地）
// - 私密路径集合 + 手势图案哈希均存 localStorage（Web 无 Keychain）
// - 解锁状态仅存内存，刷新/重开页面后自动重置为未解锁
// - 忘记手势无法找回（与 iOS 端一致）

const PRIVATE_KEY = 'private_source_folders'
const PATTERN_KEY = 'privacy_pattern_hash'

// 本次会话是否已解锁
const isUnlocked = ref(false)

// 私密路径集合（用 reactive Set 以便视图响应）
function loadPrivate() {
  try {
    const arr = JSON.parse(localStorage.getItem(PRIVATE_KEY) || '[]')
    return Array.isArray(arr) ? arr : []
  } catch {
    return []
  }
}
const privateFolders = reactive(new Set(loadPrivate()))

function persist() {
  localStorage.setItem(PRIVATE_KEY, JSON.stringify([...privateFolders]))
}

function isPrivate(path) {
  return privateFolders.has(path)
}

function setPrivate(path, value) {
  if (value) privateFolders.add(path)
  else privateFolders.delete(path)
  persist()
}

// 是否已设置手势图案
function hasPattern() {
  return !!localStorage.getItem(PATTERN_KEY)
}

// 简易字符串哈希（降级用）：局域网 http 等非安全上下文没有 crypto.subtle
// 这里仅作软性隐私开关（客户端可绕过），非加密安全场景，降级可接受
function fallbackHash(raw) {
  let h = 0x811c9dc5
  for (let i = 0; i < raw.length; i++) {
    h ^= raw.charCodeAt(i)
    h = Math.imul(h, 0x01000193)
  }
  return 'fnv' + (h >>> 0).toString(16)
}

// 将手势点序列哈希为字符串（优先 SHA-256，降级 FNV-1a）
async function hashDots(dots) {
  const raw = dots.join('-')
  if (crypto?.subtle) {
    try {
      const buf = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(raw))
      return [...new Uint8Array(buf)].map(b => b.toString(16).padStart(2, '0')).join('')
    } catch {
      // 落到降级实现
    }
  }
  return fallbackHash(raw)
}

// 设置手势图案（覆盖旧值）
async function setPattern(dots) {
  localStorage.setItem(PATTERN_KEY, await hashDots(dots))
}

// 校验手势图案是否正确
async function verifyPattern(dots) {
  const stored = localStorage.getItem(PATTERN_KEY)
  if (!stored) return false
  return stored === (await hashDots(dots))
}

function clearPattern() {
  localStorage.removeItem(PATTERN_KEY)
}

export function usePrivacy() {
  return {
    isUnlocked,
    isPrivate,
    setPrivate,
    hasPattern,
    setPattern,
    verifyPattern,
    clearPattern,
  }
}
