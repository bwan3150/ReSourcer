package com.resourcer.eink.data.network

import coil.ImageLoader
import coil.disk.DiskCache
import coil.memory.MemoryCache
import coil.request.CachePolicy
import com.google.gson.GsonBuilder
import com.resourcer.eink.data.model.Server
import okhttp3.OkHttpClient
import okhttp3.logging.HttpLoggingInterceptor
import retrofit2.Retrofit
import retrofit2.converter.gson.GsonConverterFactory
import java.util.concurrent.TimeUnit

/**
 * API 客户端工厂
 * 根据服务器配置构建 Retrofit 实例和 Coil ImageLoader
 */
object ApiClient {

    /** 当前服务器配置（由 ServerViewModel 维护） */
    @Volatile
    var currentServer: Server? = null

    /** 当前 ApiService 实例 */
    @Volatile
    private var _apiService: ApiService? = null

    /** 当前 OkHttpClient（供 Coil 复用，确保统一走认证拦截） */
    @Volatile
    private var _okHttpClient: OkHttpClient? = null

    /** 获取当前 ApiService，若 baseUrl 与 server 不匹配则重建 */
    fun getApiService(server: Server): ApiService {
        val existing = _apiService
        val prevServer = currentServer

        // 当 server 配置发生变化（切换地址或 apiKey），重建客户端
        if (existing == null
            || prevServer?.activeUrl != server.activeUrl
            || prevServer?.apiKey != server.apiKey
        ) {
            return rebuild(server)
        }
        return existing
    }

    /** 获取认证后的 OkHttpClient（供 Coil 构建时使用） */
    fun getOkHttpClient(server: Server): OkHttpClient {
        val client = _okHttpClient
        val prevServer = currentServer
        if (client == null
            || prevServer?.activeUrl != server.activeUrl
            || prevServer?.apiKey != server.apiKey
        ) {
            rebuild(server)
        }
        return _okHttpClient!!
    }

    /** 构建 Coil ImageLoader（带认证 header） */
    fun buildImageLoader(
        context: android.content.Context,
        server: Server
    ): ImageLoader {
        val client = getOkHttpClient(server)
        return ImageLoader.Builder(context)
            .okHttpClient(client)
            .memoryCache {
                MemoryCache.Builder(context)
                    .maxSizePercent(0.20) // 内存缓存占 20% 可用内存
                    .build()
            }
            .diskCache {
                DiskCache.Builder()
                    .directory(context.cacheDir.resolve("thumbnail_cache"))
                    .maxSizeBytes(300L * 1024 * 1024) // 300MB 磁盘缓存
                    .build()
            }
            // 电纸书不需要淡入动画
            .crossfade(false)
            // 优先读缓存
            .memoryCachePolicy(CachePolicy.ENABLED)
            .diskCachePolicy(CachePolicy.ENABLED)
            .build()
    }

    // ─── 内部构建 ─────────────────────────────────────────────────────────

    @Synchronized
    private fun rebuild(server: Server): ApiService {
        val client = buildOkHttpClient(server)
        val gson = GsonBuilder().setLenient().create()

        val retrofit = Retrofit.Builder()
            .baseUrl(server.activeUrl.trimEnd('/') + "/")
            .client(client)
            .addConverterFactory(GsonConverterFactory.create(gson))
            .build()

        val service = retrofit.create(ApiService::class.java)
        _apiService = service
        _okHttpClient = client
        currentServer = server
        return service
    }

    private fun buildOkHttpClient(server: Server): OkHttpClient {
        return OkHttpClient.Builder()
            .connectTimeout(15, TimeUnit.SECONDS)
            .readTimeout(30, TimeUnit.SECONDS)
            .writeTimeout(60, TimeUnit.SECONDS)
            // 认证拦截器：自动附加 api_key Cookie
            .addInterceptor { chain ->
                val original = chain.request()
                val request = original.newBuilder()
                    .header("Cookie", "api_key=${server.apiKey}")
                    .build()
                chain.proceed(request)
            }
            // 调试日志（仅 debug 构建时有效）
            .addInterceptor(
                HttpLoggingInterceptor().apply {
                    level = HttpLoggingInterceptor.Level.BASIC
                }
            )
            .build()
    }
}
