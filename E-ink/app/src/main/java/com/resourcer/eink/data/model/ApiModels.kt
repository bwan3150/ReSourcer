package com.resourcer.eink.data.model

import com.google.gson.annotations.SerializedName

// ─────────────────────────────────────────────────────────────────────────────
// 认证
// ─────────────────────────────────────────────────────────────────────────────

data class AuthCheckResponse(
    val status: String
)

// ─────────────────────────────────────────────────────────────────────────────
// 源文件夹（/api/folder/list）
// ─────────────────────────────────────────────────────────────────────────────

data class GalleryFolderInfo(
    val name: String,
    val path: String,
    @SerializedName("is_source") val isSource: Boolean,
    @SerializedName("file_count") val fileCount: Int = 0
)

data class GalleryFolderListResponse(
    val folders: List<GalleryFolderInfo>
)

// ─────────────────────────────────────────────────────────────────────────────
// 索引文件夹（/api/indexer/folders）
// ─────────────────────────────────────────────────────────────────────────────

data class IndexedFolder(
    val path: String,
    @SerializedName("parent_path") val parentPath: String?,
    @SerializedName("source_folder") val sourceFolder: String,
    val name: String,
    val depth: Int,
    @SerializedName("file_count") val fileCount: Int,
    @SerializedName("subfolder_count") val subfolderCount: Int = 0
) {
    val contentDescription: String
        get() {
            val parts = buildList {
                if (fileCount > 0) add("$fileCount 个文件")
                if (subfolderCount > 0) add("$subfolderCount 个文件夹")
            }
            return parts.joinToString(" · ").ifEmpty { "空文件夹" }
        }
}

data class IndexedFoldersResponse(
    val folders: List<IndexedFolder>
)

// ─────────────────────────────────────────────────────────────────────────────
// 索引文件（/api/indexer/files）
// ─────────────────────────────────────────────────────────────────────────────

data class IndexedFile(
    val uuid: String,
    val fingerprint: String,
    @SerializedName("current_path") val currentPath: String?,
    @SerializedName("folder_path") val folderPath: String,
    @SerializedName("file_name") val fileName: String,
    @SerializedName("file_type") val fileType: String,
    val extension: String,
    @SerializedName("file_size") val fileSize: Long,
    @SerializedName("created_at") val createdAt: String,
    @SerializedName("modified_at") val modifiedAt: String,
    @SerializedName("indexed_at") val indexedAt: String,
    @SerializedName("source_url") val sourceUrl: String?,
    /** 视频时长（秒），仅视频文件有值 */
    val duration: Double? = null,
    val width: Int? = null,
    val height: Int? = null
) {
    val isImage: Boolean get() = fileType == "image"
    val isVideo: Boolean get() = fileType == "video"
    val isGif: Boolean get() = fileType == "gif"
    val isAudio: Boolean get() = fileType == "audio"
    val isPdf: Boolean get() = fileType == "pdf"

    /** 可直接预览（图片 / 视频 / GIF） */
    val isPreviewable: Boolean get() = isImage || isVideo || isGif

    /** 扩展名标签，如 "MP4"、"PNG" */
    val extensionLabel: String
        get() = extension.trimStart('.').uppercase().ifEmpty { fileName.uppercase() }

    /** 格式化文件大小 */
    fun formattedSize(): String {
        return when {
            fileSize < 1024 -> "${fileSize}B"
            fileSize < 1024 * 1024 -> "${fileSize / 1024}KB"
            fileSize < 1024L * 1024 * 1024 -> "${fileSize / (1024 * 1024)}MB"
            else -> String.format("%.1fGB", fileSize / (1024.0 * 1024 * 1024))
        }
    }

    /** 格式化视频时长 */
    fun formattedDuration(): String? {
        val d = duration ?: return null
        val totalSec = d.toInt()
        val min = totalSec / 60
        val sec = totalSec % 60
        return String.format("%d:%02d", min, sec)
    }
}

data class IndexedFilesResponse(
    val files: List<IndexedFile>,
    val total: Int,
    val offset: Int,
    val limit: Int,
    @SerializedName("has_more") val hasMore: Boolean
)

// ─────────────────────────────────────────────────────────────────────────────
// 面包屑（/api/indexer/breadcrumb）
// ─────────────────────────────────────────────────────────────────────────────

data class BreadcrumbItem(
    val name: String,
    val path: String
)

data class BreadcrumbResponse(
    val breadcrumb: List<BreadcrumbItem>
)

// ─────────────────────────────────────────────────────────────────────────────
// 源文件夹配置（/api/config/sources）
// ─────────────────────────────────────────────────────────────────────────────

data class SourceFoldersResponse(
    val current: String,
    val backups: List<String>
)

data class SwitchSourceFolderRequest(
    @SerializedName("source_folder") val sourceFolder: String
)
