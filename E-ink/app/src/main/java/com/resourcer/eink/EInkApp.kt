package com.resourcer.eink

import android.app.Application
import coil.ImageLoader
import coil.ImageLoaderFactory
import coil.disk.DiskCache
import coil.memory.MemoryCache

/**
 * Application 入口
 * 配置全局 Coil ImageLoader（默认无认证，具体认证在请求级别注入）
 */
class EInkApp : Application(), ImageLoaderFactory {

    override fun newImageLoader(): ImageLoader {
        return ImageLoader.Builder(this)
            .memoryCache {
                MemoryCache.Builder(this)
                    .maxSizePercent(0.20)
                    .build()
            }
            .diskCache {
                DiskCache.Builder()
                    .directory(cacheDir.resolve("thumbnail_cache"))
                    .maxSizeBytes(300L * 1024 * 1024) // 300MB
                    .build()
            }
            .crossfade(false) // 电纸书不需要过渡动画
            .build()
    }
}
