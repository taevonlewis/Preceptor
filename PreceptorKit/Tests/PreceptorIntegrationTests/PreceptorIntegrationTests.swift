//
//  PreceptorIntegrationTests.swift
//  PreceptorKit
//
//  Created by TaeVon Lewis on 10/4/26.
//

import Foundation
import Testing
import PreceptorCore
import PreceptorGenerate
import PreceptorStore

@Suite("PreceptorIntegrationTests")
struct PreceptorIntegrationTests {
    @Test("Generated content survives saving and loading") func generateSaveAndLoadPreservesBatch() async throws {
        let generator = DeterministicStudyGenerator()
        let fixedDate = Date(timeIntervalSince1970: 1_000)
        let store = InMemoryGeneratedBatchStore(now: { fixedDate })
        let batch = try await generator.generate(GenerationRequest(documentID: UUID(), sourceRevisionID: UUID(), extractionRevisionID: UUID(), sourceTextID: UUID(), text: "test text"))
        let recordID = UUID()
        let expectedRecord = StoredGeneratedBatch(recordID: recordID, generatedBatch: batch, saveDate: fixedDate)

        let savedRecord = try await store.save(batch, recordID: recordID)
        let loadedRecord = try await store.load(recordID: recordID)

        #expect(savedRecord == expectedRecord)
        #expect(loadedRecord == expectedRecord)
    }
}
