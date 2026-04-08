//
//  MetricsService.swift
//  ReSourcer
//
//  Server metrics API service
//

import Foundation

actor MetricsService {

    private let networkManager: NetworkManager

    init(networkManager: NetworkManager) {
        self.networkManager = networkManager
    }

    func getCurrent() async throws -> MetricsSnapshot {
        return try await networkManager.request(.metricsCurrent)
    }

    func getHistory(minutes: Int = 60) async throws -> MetricsHistoryResponse {
        return try await networkManager.request(.metricsHistory(minutes: minutes))
    }

    func getDiskDetails() async throws -> MetricsDiskResponse {
        return try await networkManager.request(.metricsDisk)
    }

    func getSystemInfo() async throws -> MetricsSystemInfo {
        return try await networkManager.request(.metricsSystem)
    }
}
