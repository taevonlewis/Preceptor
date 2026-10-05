import Foundation
import Testing
import PreceptorCore
import PreceptorStore

@Suite("PreceptorStore Tests")
struct PreceptorStoreTests {

    func makeRequestTemplate(text: String) -> GenerationRequest {
        return GenerationRequest(
            documentID: UUID(),
            sourceRevisionID: UUID(),
            extractionRevisionID: UUID(),
            sourceTextID: UUID(),
            text: text
        )
    }

    @Test("Loading an unknown record returns nil") func loadUnknownRecordReturnsNil() async throws {
        let store = InMemoryGeneratedBatchStore(now: { Date() })
        let recordID = UUID()
        let loadedRecord = try await store.load(recordID: recordID)

        #expect(loadedRecord == nil)
    }

    @Test("Saving then loading a record equal the same record") func saveAndLoadRecordIsIdentical() async throws {
        let fixedDate = Date(timeIntervalSince1970: 1_000)
        let store = InMemoryGeneratedBatchStore(now: { fixedDate })
        let request = makeRequestTemplate(text: "test text")
        let batch = GeneratedBatch(request: request, array: [GeneratedProposal(question: "What does the source state?", quote: "test text")])
        let recordID = UUID()
        let expectedRecord = StoredGeneratedBatch(recordID: recordID, generatedBatch: batch, saveDate: fixedDate)

        let savedRecord = try await store.save(batch, recordID: recordID)
        let loadedRecord = try await store.load(recordID: recordID)

        #expect(savedRecord == expectedRecord)
        #expect(loadedRecord == expectedRecord)
    }

    @Test("Saving identical content with the same ID returns the original record") func twoIdenticalRecordsWithSameIDReturnsOriginal() async throws {
        let fixedDate = Date(timeIntervalSince1970: 1_000)
        let request = makeRequestTemplate(text: "test text")
        let batch = GeneratedBatch(request: request, array: [GeneratedProposal(question: "What does the source state?", quote: "test text")])
        let recordID = UUID()

        try await confirmation("The date supplier is called exactly once", expectedCount: 1) { dateSupplierCalled in
            let store = InMemoryGeneratedBatchStore(now: {
                dateSupplierCalled()
                return fixedDate
            })

            let savedRecord1 = try await store.save(batch, recordID: recordID)
            let savedRecord2 = try await store.save(batch, recordID: recordID)
            let loadedRecord = try await store.load(recordID: recordID)

            #expect(savedRecord1.saveDate == fixedDate)
            #expect(savedRecord1 == savedRecord2)
            #expect(savedRecord1 == loadedRecord)
        }
    }

    @Test("Saving two different tests with same ID throws conflictingRecordID error") func twoDifferentRecordsWithSameIDThrowsConflictError() async throws {
        let store = InMemoryGeneratedBatchStore(now: { Date() })
        let request = makeRequestTemplate(text: "test text")
        let batch1 = GeneratedBatch(request: request, array: [GeneratedProposal(question: "What does the source state?", quote: "first test text")])
        let batch2 = GeneratedBatch(request: request, array: [GeneratedProposal(question: "What does the source state?", quote: "second test text")])
        let recordID = UUID()

        let savedRecord1 = try await store.save(batch1, recordID: recordID)

        await #expect(throws: StorageError.conflictingRecordID) {
            try await store.save(batch2, recordID: recordID)
        }

        let loadedRecord = try await store.load(recordID: recordID)
        #expect(savedRecord1 == loadedRecord)
    }

    @Test("Saving the same content with different IDs preserves both records") func twoDifferentRecordsLoadBoth() async throws {
        let store = InMemoryGeneratedBatchStore(now: { Date() })
        let request = makeRequestTemplate(text: "test text")
        let batch = GeneratedBatch(request: request, array: [GeneratedProposal(question: "What does the source state?", quote: "test text")])
        let recordID1 = UUID()
        let recordID2 = UUID()

        let savedRecord1 = try await store.save(batch, recordID: recordID1)
        let savedRecord2 = try await store.save(batch, recordID: recordID2)

        let loadedRecord1 = try await store.load(recordID: recordID1)
        #expect(savedRecord1 == loadedRecord1)

        let loadedRecord2 = try await store.load(recordID: recordID2)
        #expect(savedRecord2 == loadedRecord2)

        #expect(savedRecord1.recordID == recordID1)
        #expect(savedRecord2.recordID == recordID2)
        #expect(savedRecord1.generatedBatch == batch)
        #expect(savedRecord2.generatedBatch == batch)
    }

    @Test("Cancelling before calling save or load throws CancellationError") func cancelBeforeSaveOrLoadThrowsCancelError() async throws {
        let store = InMemoryGeneratedBatchStore(now: { Date() })
        let request = makeRequestTemplate(text: "test text")
        let batch = GeneratedBatch(request: request, array: [GeneratedProposal(question: "What does the source state?", quote: "test text")])
        let recordID = UUID()

        let saveTask = Task {
            withUnsafeCurrentTask { task in
                task?.cancel()
            }

            return try await store.save(batch, recordID: recordID)
        }

        await #expect(throws: CancellationError.self) {
            try await saveTask.value
        }

        let loadedRecord = try await store.load(recordID: recordID)
        #expect(loadedRecord == nil)

        let loadTask = Task {
            withUnsafeCurrentTask { task in
                task?.cancel()
            }

            return try await store.load(recordID: recordID)
        }

        await #expect(throws: CancellationError.self) {
            try await loadTask.value
        }
    }
}
