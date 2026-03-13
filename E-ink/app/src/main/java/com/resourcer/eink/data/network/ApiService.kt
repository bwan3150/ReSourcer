package com.resourcer.eink.data.network

import com.resourcer.eink.data.model.*
import okhttp3.ResponseBody
import retrofit2.Response
import retrofit2.http.*

/**
 * Retrofit API 接口定义
 * 认证通过 OkHttp 拦截器自动附加 Cookie: api_key=xxx
 */
interface ApiService {

    // ─── 认证 ─────────────────────────────────────────────────────────────

    /** 检查 API Key 是否有效 */
    @GET("/api/auth/check")
    suspend fun authCheck(): Response<AuthCheckResponse>

    // ─── 源文件夹列表 ──────────────────────────────────────────────────────

    /** 获取所有源文件夹 */
    @GET("/api/folder/list")
    suspend fun folderList(): GalleryFolderListResponse

    // ─── 索引文件夹 ────────────────────────────────────────────────────────

    /**
     * 获取子文件夹
     * @param parentPath 父文件夹路径（null 表示获取源文件夹的直接子文件夹）
     * @param sourceFolder 源文件夹路径
     */
    @GET("/api/indexer/folders")
    suspend fun indexerFolders(
        @Query("parent_path") parentPath: String? = null,
        @Query("source_folder") sourceFolder: String? = null
    ): List<IndexedFolder>

    // ─── 索引文件 ──────────────────────────────────────────────────────────

    /**
     * 分页获取指定文件夹内的文件
     * @param folderPath 文件夹路径
     * @param offset 分页偏移
     * @param limit 每页数量
     * @param fileType 文件类型过滤（null = 全部）
     * @param sort 排序方式
     */
    @GET("/api/indexer/files")
    suspend fun indexerFiles(
        @Query("folder_path") folderPath: String,
        @Query("offset") offset: Int = 0,
        @Query("limit") limit: Int = 50,
        @Query("file_type") fileType: String? = null,
        @Query("sort") sort: String? = null
    ): IndexedFilesResponse

    // ─── 面包屑 ────────────────────────────────────────────────────────────

    /** 获取面包屑路径 */
    @GET("/api/indexer/breadcrumb")
    suspend fun indexerBreadcrumb(
        @Query("folder_path") folderPath: String
    ): BreadcrumbResponse

    // ─── 预览 ──────────────────────────────────────────────────────────────

    /**
     * 通过 UUID 获取缩略图
     * @param uuid 文件 UUID
     * @param size 缩略图尺寸（像素）
     */
    @GET("/api/preview/thumbnail")
    @Streaming
    suspend fun previewThumbnailByUuid(
        @Query("uuid") uuid: String,
        @Query("size") size: Int = 300
    ): Response<ResponseBody>

    /**
     * 通过 UUID 获取文件完整内容
     * @param uuid 文件 UUID
     */
    @GET("/api/preview/content/_")
    @Streaming
    suspend fun previewContentByUuid(
        @Query("uuid") uuid: String
    ): Response<ResponseBody>

    // ─── 源文件夹配置 ──────────────────────────────────────────────────────

    /** 获取源文件夹列表（当前 + 备用） */
    @GET("/api/config/sources")
    suspend fun configSources(): SourceFoldersResponse

    /** 切换到指定源文件夹 */
    @POST("/api/config/sources/switch")
    suspend fun configSourcesSwitch(@Body body: SwitchSourceFolderRequest): StatusResponse
}

data class StatusResponse(val status: String)
