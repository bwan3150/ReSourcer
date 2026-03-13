package com.resourcer.eink.data.cache

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.util.LruCache
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.File
import java.security.MessageDigest

/**
 * 缩略图缓存
 * 磁盘结构：thumbnails/{serverHash8}/{sfHash8}/{uuidPrefix2}/{sha256}.jpg
 * sfHash8 目录下有 _meta.json 记录真实路径，用于按源文件夹清除
 */
class ThumbnailCache(cacheDir: File) {

    private val root = File(cacheDir, "thumbnails").also { it.mkdirs() }

    // 内存 LRU 缓存：最多使用可用内存的 1/6
    private val maxMemBytes = (Runtime.getRuntime().maxMemory() / 6).toInt()
    private val memCache = object : LruCache<String, Bitmap>(maxMemBytes) {
        override fun sizeOf(key: String, value: Bitmap) = value.byteCount
    }

    companion object {
        @Volatile private var _instance: ThumbnailCache? = null
        fun getInstance(cacheDir: File): ThumbnailCache =
            _instance ?: synchronized(this) {
                _instance ?: ThumbnailCache(cacheDir).also { _instance = it }
            }
    }

    // ─── 读写 ──────────────────────────────────────────────────────────────

    fun get(uuid: String, serverUrl: String, sfPath: String): Bitmap? {
        memCache.get(uuid)?.let { return it }
        val f = diskFile(uuid, serverUrl, sfPath)
        if (f.exists()) {
            val bmp = BitmapFactory.decodeFile(f.path) ?: return null
            memCache.put(uuid, bmp)
            return bmp
        }
        return null
    }

    fun put(uuid: String, serverUrl: String, sfPath: String, bitmap: Bitmap) {
        memCache.put(uuid, bitmap)
        val f = diskFile(uuid, serverUrl, sfPath)
        f.parentFile?.mkdirs()
        // 同时写入 sfHash 目录的元数据
        writeMeta(sfDir(serverUrl, sfPath), sfPath)
        f.outputStream().use { bitmap.compress(Bitmap.CompressFormat.JPEG, 85, it) }
    }

    /** 异步加载：先查缓存，未命中则请求网络 */
    suspend fun load(
        uuid: String,
        serverUrl: String,
        sfPath: String,
        apiKey: String,
        size: Int,
        client: OkHttpClient
    ): Bitmap? {
        get(uuid, serverUrl, sfPath)?.let { return it }
        return withContext(Dispatchers.IO) {
            try {
                val url = "$serverUrl/api/preview/thumbnail?uuid=$uuid&size=$size"
                val req = Request.Builder()
                    .url(url)
                    .header("Cookie", "api_key=$apiKey")
                    .build()
                val resp = client.newCall(req).execute()
                if (!resp.isSuccessful) return@withContext null
                val bytes = resp.body?.bytes() ?: return@withContext null
                val bmp = BitmapFactory.decodeByteArray(bytes, 0, bytes.size) ?: return@withContext null
                put(uuid, serverUrl, sfPath, bmp)
                bmp
            } catch (_: Exception) { null }
        }
    }

    // ─── 清除 ──────────────────────────────────────────────────────────────

    fun clearAll() {
        memCache.evictAll()
        root.deleteRecursively()
        root.mkdirs()
    }

    /** 清除指定服务器下某个源文件夹的缓存 */
    fun clearBySourceFolder(sfPath: String, serverUrl: String) {
        memCache.evictAll()
        sfDir(serverUrl, sfPath).deleteRecursively()
    }

    // ─── 统计 ──────────────────────────────────────────────────────────────

    /** 返回当前服务器各源文件夹缓存大小列表 */
    fun sourceFolderStats(serverUrl: String): List<SfCacheStats> {
        val serverDir = File(root, sha256(serverUrl).take(8))
        if (!serverDir.exists()) return emptyList()
        return serverDir.listFiles()
            ?.filter { it.isDirectory && it.name != "_meta.json" }
            ?.mapNotNull { sfDir ->
                val sfPath = readMeta(sfDir) ?: return@mapNotNull null
                val bytes = dirSize(sfDir)
                if (bytes == 0L) null
                else SfCacheStats(sfPath = sfPath, bytes = bytes)
            } ?: emptyList()
    }

    fun totalSize(): Long = dirSize(root)

    // ─── 内部工具 ──────────────────────────────────────────────────────────

    private fun diskFile(uuid: String, serverUrl: String, sfPath: String): File {
        val uuidPrefix = uuid.take(2).ifEmpty { "00" }
        val key = sha256(uuid)
        return File(sfDir(serverUrl, sfPath), "$uuidPrefix/$key.jpg")
    }

    private fun sfDir(serverUrl: String, sfPath: String): File {
        val serverHash = sha256(serverUrl).take(8)
        val sfHash = sha256(sfPath).take(8)
        return File(root, "$serverHash/$sfHash")
    }

    private fun writeMeta(sfDir: File, sfPath: String) {
        val meta = File(sfDir, "_meta.json")
        if (!meta.exists()) {
            sfDir.mkdirs()
            val name = sfPath.substringAfterLast('/').ifEmpty { sfPath }
            meta.writeText("""{"sourceFolder":"$sfPath","name":"$name"}""")
        }
    }

    private fun readMeta(sfDir: File): String? {
        val meta = File(sfDir, "_meta.json")
        if (!meta.exists()) return null
        return try {
            val json = meta.readText()
            Regex(""""sourceFolder"\s*:\s*"([^"]+)"""").find(json)?.groupValues?.get(1)
        } catch (_: Exception) { null }
    }

    private fun dirSize(dir: File): Long =
        dir.walkTopDown().filter { it.isFile && it.name != "_meta.json" }.sumOf { it.length() }

    private fun sha256(input: String): String {
        val digest = MessageDigest.getInstance("SHA-256")
        return digest.digest(input.toByteArray()).joinToString("") { "%02x".format(it) }
    }
}

data class SfCacheStats(
    val sfPath: String,
    val bytes: Long
) {
    val name: String get() = sfPath.substringAfterLast('/').ifEmpty { sfPath }
    fun formattedSize(): String = when {
        bytes < 1024 -> "${bytes}B"
        bytes < 1024 * 1024 -> "${bytes / 1024}KB"
        bytes < 1024L * 1024 * 1024 -> "${bytes / (1024 * 1024)}MB"
        else -> String.format("%.1fGB", bytes / (1024.0 * 1024 * 1024))
    }
}
