//
//  InMemoryGeneratedBatchStore.swift
//  PreceptorKit
//
//  Created by TaeVon Lewis on 10/4/26.
//

import Foundation
import PreceptorCore

public actor InMemoryGeneratedBatchStore: GeneratedBatchStoring {
    private var storage: [UUID: StoredGeneratedBatch] = [:]
    private let now: @Sendable () -> Date

    public init(now: @Sendable @escaping () -> Date = { Date() }) {
        self.now = now
    }

    public func save(_ batch: GeneratedBatch, recordID: UUID) async throws -> StoredGeneratedBatch {
        try Task.checkCancellation()

        if let existingRecord = storage[recordID] {
            guard existingRecord.generatedBatch == batch else {
                throw StorageError.conflictingRecordID
            }

            return existingRecord
        }

        let record = StoredGeneratedBatch(recordID: recordID, generatedBatch: batch, saveDate: now())
        storage[recordID] = record

        return record
    }

    public func load(recordID: UUID) async throws -> StoredGeneratedBatch? {
        try Task.checkCancellation()

        return storage[recordID]
    }


}
