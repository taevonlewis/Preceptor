//
//  GeneratedBatchStoring.swift
//  PreceptorKit
//
//  Created by TaeVon Lewis on 10/4/26.
//

import Foundation
// Public storage protocol

public protocol GeneratedBatchStoring: Sendable {
    func save(_ batch: GeneratedBatch, recordID: UUID) async throws -> StoredGeneratedBatch
    func load(recordID: UUID) async throws -> StoredGeneratedBatch?
}
