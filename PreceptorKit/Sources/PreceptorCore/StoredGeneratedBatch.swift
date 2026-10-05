//
//  StoredGeneratedBatch.swift
//  PreceptorKit
//
//  Created by TaeVon Lewis on 10/4/26.
//

import Foundation

public struct StoredGeneratedBatch: Sendable, Equatable {
    public let recordID: UUID
    public let generatedBatch: GeneratedBatch
    public let saveDate: Date

    public init(recordID: UUID, generatedBatch: GeneratedBatch, saveDate: Date) {
        self.recordID = recordID
        self.generatedBatch = generatedBatch
        self.saveDate = saveDate
    }
}
