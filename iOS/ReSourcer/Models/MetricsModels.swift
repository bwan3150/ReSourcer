//
//  MetricsModels.swift
//  ReSourcer
//
//  Server metrics data models
//

import Foundation

// MARK: - Playlist

struct PlaylistResponse: Codable {
    let items: [IndexedFile]
    let currentIndex: Int
}

// MARK: - Metrics

struct MetricsSnapshot: Codable {
    let timestamp: String
    let cpuUsagePercent: Double
    let memoryTotalBytes: Int64
    let memoryUsedBytes: Int64
    let memoryAvailableBytes: Int64
    let diskTotalBytes: Int64
    let diskUsedBytes: Int64
    let diskAvailableBytes: Int64
    let loadAvg1M: Double
    let loadAvg5M: Double
    let loadAvg15M: Double
    let processMemoryBytes: Int64
    let uptimeSeconds: Int64
    let systemUptimeSeconds: Int64?
    let indexedFiles: Int64?
    let dbSizeBytes: Int64?
    let dbWalSizeBytes: Int64?
}

struct MetricsHistoryResponse: Codable {
    let snapshots: [MetricsSnapshot]
    let count: Int
    let rangeMinutes: Int
}

struct MetricsDiskInfo: Codable {
    let name: String
    let mountPoint: String
    let totalBytes: Int64
    let usedBytes: Int64
    let availableBytes: Int64
    let filesystem: String
}

struct MetricsDiskResponse: Codable {
    let disks: [MetricsDiskInfo]
}

struct MetricsSystemInfo: Codable {
    let osName: String
    let osVersion: String
    let arch: String
    let hostname: String
    let cpuCount: Int
}
