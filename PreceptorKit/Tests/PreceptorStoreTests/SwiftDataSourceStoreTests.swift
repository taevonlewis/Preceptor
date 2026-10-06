//
//  SwiftDataSourceStoreTests.swift
//  PreceptorKit
//
//  Created by TaeVon Lewis on 10/5/26.
//


import Foundation
import PreceptorCore
import PreceptorExtract
import SwiftData
import Testing
@testable import PreceptorStore

@Suite("Durable source history")
struct SwiftDataSourceStoreTests {
    @Test("Unknown source and extraction IDs return nil")
    func unknownIDs() async throws {
        let fixture = try SourceStoreFixture()
        defer { fixture.remove() }
        let store = try fixture.store()

        #expect(try await store.sourceRevision(id: UUID()) == nil)
        #expect(try await store.extractionRevision(id: UUID()) == nil)
    }

    @Test("Renamed reimports preserve original IDs, names and dates")
    func documentScopedReuse() async throws {
        let fixture = try SourceStoreFixture()
        defer { fixture.remove() }
        let store = try fixture.store()
        let source = try fixture.source()
        let renamed = try fixture.source(documentID: source.documentID, names: ["renamed.png", "other.png"],
            createdAt: Date(timeIntervalSince1970: 2_000))

        #expect(try await store.saveSource(source) == source)
        #expect(try await store.saveSource(renamed) == source)
        #expect(try await store.sourceRevision(id: renamed.id) == nil)
        #expect(try await store.sourceRevision(id: source.id) == source)

        let otherDocument = try fixture.source()
        #expect(try await store.saveSource(otherDocument) == otherDocument)
        #expect(otherDocument.contentHash == source.contentHash)
        #expect(try await store.sourceRevision(id: otherDocument.id)
            == otherDocument)
    }

    @Test("Order and duplicate multiplicity produce distinct source revisions")
    func orderedManifestReuse() async throws {
        let fixture = try SourceStoreFixture()
        defer { fixture.remove() }
        let store = try fixture.store()
        let documentID = UUID()
        let source = try fixture.source(documentID: documentID)
        let reordered = try fixture.source(documentID: documentID, bytes: Array(fixture.bytes.reversed()))
        let duplicate = try fixture.source(documentID: documentID,
            bytes: [fixture.bytes[0], fixture.bytes[0], fixture.bytes[1]])

        for value in [source, reordered, duplicate] {
            #expect(try await store.saveSource(value) == value)
            #expect(try await store.sourceRevision(id: value.id) == value)
        }
        #expect(source.contentHash != reordered.contentHash)
        #expect(source.contentHash != duplicate.contentHash)
        #expect(duplicate.manifest.members.count == 3)
        #expect(duplicate.manifest.members[0].contentHash
            == duplicate.manifest.members[1].contentHash)
    }

    @Test("Hash and record-ID conflicts cannot overwrite a source")
    func invalidSourceIdentity() async throws {
        let fixture = try SourceStoreFixture()
        defer { fixture.remove() }
        let store = try fixture.store()
        let source = try fixture.source()
        _ = try await store.saveSource(source)
        let wrongHash = SourceRevisionSnapshot(id: UUID(), documentID: source.documentID,
            contentHash: try SourceContentHash(hexDigest: String(repeating: "0", count: 64)),
            manifest: source.manifest, createdAt: source.createdAt)
        await #expect(throws: SourceStoreError.contentHashMismatch) {
            try await store.saveSource(wrongHash)
        }
        let conflicting = try fixture.source(id: source.id, documentID: source.documentID,
            bytes: [Data("different original".utf8)])
        await #expect(throws: SourceStoreError.conflictingRecordID) {
            try await store.saveSource(conflicting)
        }
        #expect(try await store.sourceRevision(id: source.id) == source)
        #expect(try await store.sourceRevision(id: wrongHash.id) == nil)
    }

    @Test("Nonfinite source and extraction dates are rejected before insertion")
    func invalidDates() async throws {
        let fixture = try SourceStoreFixture()
        defer { fixture.remove() }
        let store = try fixture.store()
        let invalidSource = try fixture.source(createdAt: Date(timeIntervalSince1970: .infinity))
        await #expect(throws: SourceStoreError.corruptRecord) {
            try await store.saveSource(invalidSource)
        }
        #expect(try await store.sourceRevision(id: invalidSource.id) == nil)
        let source = try fixture.source()
        _ = try await store.saveSource(source)
        let invalidExtraction = try fixture.extraction(sourceID: source.id,
            createdAt: Date(timeIntervalSince1970: .infinity))
        await #expect(throws: SourceStoreError.corruptRecord) {
            try await store.saveExtraction(invalidExtraction)
        }
        #expect(try await store.extractionRevision(id: invalidExtraction.id) == nil)
    }

    @Test("Extraction reuse retains persisted unit IDs and original date")
    func extractionReuse() async throws {
        let fixture = try SourceStoreFixture()
        defer { fixture.remove() }
        let store = try fixture.store()
        let source = try fixture.source()
        _ = try await store.saveSource(source)
        let original = try fixture.extraction(sourceID: source.id)
        let retry = try fixture.extraction(sourceID: source.id, createdAt: Date(timeIntervalSince1970: 2_000))

        #expect(try await store.saveExtraction(original) == original)
        #expect(try await store.saveExtraction(retry) == original)
        #expect(try await store.extractionRevision(id: original.id) == original)
        #expect(try await store.extractionRevision(id: retry.id) == nil)
        #expect(original.units.map(\.id) != retry.units.map(\.id))
    }

    @Test("Complete corrections retain old text and recognition provenance")
    func immutableCompleteCorrection() async throws {
        let fixture = try SourceStoreFixture()
        defer { fixture.remove() }
        let store = try fixture.store()
        let source = try fixture.source()
        _ = try await store.saveSource(source)
        let original = try fixture.extraction(sourceID: source.id)
        _ = try await store.saveExtraction(original)
        let corrected = try fixture.extraction(sourceID: source.id, predecessors: [original.id],
            origin: .userCorrection, texts: ["corrected first", "second unit"])

        #expect(try await store.saveExtraction(corrected) == corrected)
        #expect(try await store.extractionRevision(id: original.id) == original)
        #expect(try await store.extractionRevision(id: corrected.id) == corrected)
        #expect(corrected.units.map(\.provenance)
            == original.units.map(\.provenance))
        #expect(Set(corrected.units.map(\.id)).isDisjoint(with: original.units.map(\.id)))
        #expect(original.units[0].text == "first unit")
    }

    @Test("Corrections cannot omit, reorder, or relabel predecessor units", arguments: CorrectionFault.allCases)
    private func incompleteCorrections(_ fault: CorrectionFault) async throws {
        let fixture = try SourceStoreFixture()
        defer { fixture.remove() }
        let store = try fixture.store()
        let source = try fixture.source()
        _ = try await store.saveSource(source)
        let original = try fixture.extraction(sourceID: source.id)
        _ = try await store.saveExtraction(original)
        let correction = try fault.snapshot(fixture: fixture, predecessor: original)

        await #expect(throws: SourceStoreError.invalidProvenance) {
            try await store.saveExtraction(correction)
        }
        #expect(try await store.extractionRevision(id: correction.id) == nil)
        #expect(try await store.extractionRevision(id: original.id) == original)
    }

    @Test("Extraction and unit IDs cannot overwrite immutable history")
    func immutableExtractionIDs() async throws {
        let fixture = try SourceStoreFixture()
        defer { fixture.remove() }
        let store = try fixture.store()
        let source = try fixture.source()
        _ = try await store.saveSource(source)
        let original = try fixture.extraction(sourceID: source.id)
        _ = try await store.saveExtraction(original)
        let overwrite = try fixture.extraction(id: original.id, sourceID: source.id, texts: ["changed", "second unit"])
        await #expect(throws: SourceStoreError.conflictingRecordID) {
            try await store.saveExtraction(overwrite)
        }
        let reusedUnit = try fixture.extraction(sourceID: source.id, texts: ["changed", "second unit"],
            unitIDs: original.units.map(\.id))
        await #expect(throws: SourceStoreError.conflictingRecordID) {
            try await store.saveExtraction(reusedUnit)
        }
        #expect(try await store.extractionRevision(id: original.id) == original)
        #expect(try await store.extractionRevision(id: reusedUnit.id) == nil)
    }

    @Test("Missing source, missing predecessor, and foreign lineage fail")
    func invalidLineage() async throws {
        let fixture = try SourceStoreFixture()
        defer { fixture.remove() }
        let store = try fixture.store()
        let source = try fixture.source()
        let original = try fixture.extraction(sourceID: source.id)
        await #expect(throws: SourceStoreError.missingSourceRevision) {
            try await store.saveExtraction(original)
        }
        _ = try await store.saveSource(source)
        let missing = try fixture.extraction(sourceID: source.id, predecessors: [UUID()], origin: .userCorrection)
        await #expect(throws: SourceStoreError.missingPredecessor) {
            try await store.saveExtraction(missing)
        }
        _ = try await store.saveExtraction(original)
        let foreign = try fixture.source()
        _ = try await store.saveSource(foreign)
        let crossed = try fixture.extraction(sourceID: foreign.id, predecessors: [original.id], origin: .userCorrection)
        await #expect(throws: SourceStoreError.conflictingLineage) {
            try await store.saveExtraction(crossed)
        }
        #expect(try await store.extractionRevision(id: crossed.id) == nil)
    }

    @Test("Source-member bounds and recognition path are validated", arguments: [true, false])
    func invalidProvenance(memberOutOfBounds: Bool) async throws {
        let fixture = try SourceStoreFixture()
        defer { fixture.remove() }
        let store = try fixture.store()
        let source = try fixture.source()
        _ = try await store.saveSource(source)
        let provenance = try SourceUnitProvenance(assetMemberIndex: memberOutOfBounds ? 2 : 0,
            unitIndexInAsset: 0, extractionPath: memberOutOfBounds ? .imageOCR : .typed)
        let extraction = try fixture.extraction(sourceID: source.id, texts: ["text"], provenances: [provenance])
        await #expect(throws: SourceStoreError.invalidProvenance) {
            try await store.saveExtraction(extraction)
        }
        #expect(try await store.extractionRevision(id: extraction.id) == nil)
        let writer = SourceIntegrityWriter(modelContainer: store.modelContainer)
        try await writer.installExtractions([extraction])
        let reopened = try fixture.store()
        await #expect(throws: SourceStoreError.invalidProvenance) {
            try await reopened.extractionRevision(id: extraction.id)
        }
    }

    @Test("Pre-cancelled writes and reads publish no history or registration")
    func cancellationBeforeOperations() async throws {
        let fixture = try SourceStoreFixture()
        defer { fixture.remove() }
        let store = try fixture.store()
        let source = try fixture.source()
        let sourceTask = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await store.saveSource(source)
        }
        await #expect(throws: CancellationError.self) {
            try await sourceTask.value
        }
        #expect(try await store.sourceRevision(id: source.id) == nil)
        _ = try await store.saveSource(source)
        let extraction = try fixture.extraction(sourceID: source.id)
        let extractionTask = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await store.saveExtraction(extraction)
        }
        await #expect(throws: CancellationError.self) {
            try await extractionTask.value
        }
        #expect(try await store.extractionRevision(id: extraction.id) == nil)
        let readTask = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await store.sourceRevision(id: source.id)
        }
        await #expect(throws: CancellationError.self) {
            try await readTask.value
        }
        let path = try fixture.writeOriginal()
        let reference = LocalAssetReference(sourceRevisionID: source.id, memberIndex: 0, relativePath: path)
        let registrationTask = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await store.registerLocalAsset(reference)
        }
        await #expect(throws: CancellationError.self) {
            try await registrationTask.value
        }
        #expect(try await store.availability(sourceRevisionID: source.id)
            == [.unregistered, .unregistered])
    }

    @Test("Failed or cancelled commit rolls back complete headers and units", arguments: CommitFault.allCases)
    private func failedCommitAtomicity(_ fault: CommitFault) async throws {
        let fixture = try SourceStoreFixture()
        defer { fixture.remove() }
        let source = try fixture.source()
        let failing = try SwiftDataSourceStore(storeURL: fixture.storeURL,
            localAssetsDirectoryURL: fixture.assetsURL, beforeSave: { try fault.inject() })
        let sourceTask = Task { try await failing.saveSource(source) }
        switch fault {
        case .failure:
            await #expect(throws: SourceSaveFailure.simulated) {
                try await sourceTask.value
            }
        case .cancellation:
            await #expect(throws: CancellationError.self) {
                try await sourceTask.value
            }
        }
        #expect(try await failing.sourceRevision(id: source.id) == nil)
        let initialInspector = SourceIntegrityWriter(modelContainer: failing.modelContainer)
        #expect(try await initialInspector.counts() == [0, 0, 0, 0])

        let normal = try fixture.store()
        _ = try await normal.saveSource(source)
        let extraction = try fixture.extraction(sourceID: source.id)
        let extractionTask = Task { try await failing.saveExtraction(extraction) }
        switch fault {
        case .failure:
            await #expect(throws: SourceSaveFailure.simulated) {
                try await extractionTask.value
            }
        case .cancellation:
            await #expect(throws: CancellationError.self) {
                try await extractionTask.value
            }
        }
        #expect(try await failing.extractionRevision(id: extraction.id) == nil)
        #expect(try await initialInspector.counts() == [1, 0, 0, 0])

        let reopened = try fixture.store()
        #expect(try await reopened.sourceRevision(id: source.id) == source)
        #expect(try await reopened.extractionRevision(id: extraction.id) == nil)
        #expect(try await reopened.saveExtraction(extraction) == extraction)
        let inspector = SourceIntegrityWriter(modelContainer: reopened.modelContainer)
        #expect(try await inspector.counts() == [1, 1, 2, 0])
    }

    @Test("Failed registration changes retain the prior durable path")
    func failedRegistrationRollback() async throws {
        let fixture = try SourceStoreFixture()
        defer { fixture.remove() }
        let source = try fixture.source()
        let normal = try fixture.store()
        _ = try await normal.saveSource(source)
        let originalPath = try fixture.writeOriginal()
        try await normal.registerLocalAsset(LocalAssetReference(sourceRevisionID: source.id, memberIndex: 0,
            relativePath: originalPath))
        let nextPath = "renamed.png"
        try fixture.bytes[0].write(to: fixture.assetsURL.appendingPathComponent(nextPath))
        let failing = try SwiftDataSourceStore(storeURL: fixture.storeURL,
            localAssetsDirectoryURL: fixture.assetsURL, beforeSave: { throw SourceSaveFailure.simulated })
        await #expect(throws: SourceSaveFailure.simulated) {
            try await failing.registerLocalAsset(LocalAssetReference(sourceRevisionID: source.id, memberIndex: 0,
                relativePath: nextPath))
        }
        let expected: [SourceAssetAvailability] = [
            .available(fixture.assetsURL.appendingPathComponent(originalPath)),
            .unregistered
        ]
        #expect(try await failing.availability(sourceRevisionID: source.id) == expected)
        let reopened = try fixture.store()
        #expect(try await reopened.availability(sourceRevisionID: source.id) == expected)
        #expect(try await reopened.sourceRevision(id: source.id) == source)
    }

    @Test("Availability changes never mutate source or extraction history")
    func mutableAvailabilityImmutableHistory() async throws {
        let fixture = try SourceStoreFixture()
        defer { fixture.remove() }
        let store = try fixture.store()
        let source = try fixture.source()
        _ = try await store.saveSource(source)
        let extraction = try fixture.extraction(sourceID: source.id)
        _ = try await store.saveExtraction(extraction)
        #expect(try await store.availability(sourceRevisionID: source.id)
            == [.unregistered, .unregistered])
        let path = try fixture.writeOriginal()
        let url = fixture.assetsURL.appendingPathComponent(path)
        try await store.registerLocalAsset(LocalAssetReference(sourceRevisionID: source.id, memberIndex: 0,
            relativePath: path))
        #expect(try await store.availability(sourceRevisionID: source.id)
            == [.available(url), .unregistered])
        try FileManager.default.removeItem(at: url)
        #expect(try await store.availability(sourceRevisionID: source.id)
            == [.missing, .unregistered])
        // Equal byte count ensures availability checks the digest, too.
        try Data([0, 1, 2, 4]).write(to: url)
        #expect(try await store.availability(sourceRevisionID: source.id)
            == [.contentMismatch, .unregistered])
        try fixture.bytes[0].write(to: url)
        #expect(try await store.availability(sourceRevisionID: source.id)
            == [.available(url), .unregistered])
        #expect(try await store.sourceRevision(id: source.id) == source)
        #expect(try await store.extractionRevision(id: extraction.id) == extraction)
    }

    @Test("Registration requires a known member and matching original bytes")
    func registrationValidation() async throws {
        let fixture = try SourceStoreFixture()
        defer { fixture.remove() }
        let store = try fixture.store()
        let source = try fixture.source()
        let path = try fixture.writeOriginal()
        await #expect(throws: SourceStoreError.missingSourceRevision) {
            try await store.registerLocalAsset(LocalAssetReference(sourceRevisionID: source.id, memberIndex: 0,
                relativePath: path))
        }
        _ = try await store.saveSource(source)
        await #expect(throws: SourceStoreError.invalidProvenance) {
            try await store.registerLocalAsset(LocalAssetReference(sourceRevisionID: source.id, memberIndex: 2,
                relativePath: path))
        }
        await #expect(throws: SourceStoreError.localAssetContentMismatch) {
            try await store.registerLocalAsset(LocalAssetReference(sourceRevisionID: source.id, memberIndex: 1,
                relativePath: path))
        }
        #expect(try await store.availability(sourceRevisionID: source.id)
            == [.unregistered, .unregistered])
    }

    @Test("Local paths cannot traverse, be absolute, or contain empty segments",
        arguments: ["", "../outside", "/absolute", ".", "./original",
            "folder/../original", "folder//original", "original/",
            "original\0.png"])
    func invalidPaths(_ path: String) async throws {
        let fixture = try SourceStoreFixture()
        defer { fixture.remove() }
        let store = try fixture.store()
        let source = try fixture.source()
        _ = try await store.saveSource(source)
        await #expect(throws: SourceStoreError.invalidLocalAssetPath) {
            try await store.registerLocalAsset(LocalAssetReference(sourceRevisionID: source.id, memberIndex: 0,
                relativePath: path))
        }
        #expect(try await store.availability(sourceRevisionID: source.id)
            == [.unregistered, .unregistered])
    }

    @Test("Symlinks cannot register or later expose originals outside the root")
    func symlinkContainment() async throws {
        let fixture = try SourceStoreFixture()
        defer { fixture.remove() }
        let store = try fixture.store()
        let source = try fixture.source()
        _ = try await store.saveSource(source)
        let outside = fixture.directoryURL.appendingPathComponent("outside.png")
        try fixture.bytes[0].write(to: outside)
        let link = fixture.assetsURL.appendingPathComponent("linked.png")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        await #expect(throws: SourceStoreError.invalidLocalAssetPath) {
            try await store.registerLocalAsset(LocalAssetReference(sourceRevisionID: source.id, memberIndex: 0,
                relativePath: "linked.png"))
        }

        let path = try fixture.writeOriginal()
        let original = fixture.assetsURL.appendingPathComponent(path)
        try await store.registerLocalAsset(LocalAssetReference(sourceRevisionID: source.id, memberIndex: 0,
            relativePath: path))
        try FileManager.default.removeItem(at: original)
        try FileManager.default.createSymbolicLink(at: original, withDestinationURL: outside)
        await #expect(throws: SourceStoreError.invalidLocalAssetPath) {
            try await store.availability(sourceRevisionID: source.id)
        }
        #expect(try await store.sourceRevision(id: source.id) == source)
    }

    @Test("Corrupt source encodings fail explicitly", arguments: SourceFault.allCases)
    private func corruptSources(_ fault: SourceFault) async throws {
        let fixture = try SourceStoreFixture()
        defer { fixture.remove() }
        let source = try fixture.source()
        let seed = try fixture.store()
        let writer = SourceIntegrityWriter(modelContainer: seed.modelContainer)
        try await writer.install(source: source, extractions: [])
        try await writer.corruptSource(id: source.id, fault: fault)
        let reopened = try fixture.store()
        switch fault {
        case .recordVersion, .manifestVersion:
            await #expect(throws: SourceStoreError.unsupportedRecordVersion(2)) {
                try await reopened.sourceRevision(id: source.id)
            }
        case .malformedJSON:
            await #expect(throws: DecodingError.self) {
                try await reopened.sourceRevision(id: source.id)
            }
        case .hash:
            await #expect(throws: SourceStoreError.contentHashMismatch) {
                try await reopened.sourceRevision(id: source.id)
            }
        case .byteCount, .mediaKind, .duplicateRecord:
            await #expect(throws: SourceStoreError.corruptRecord) {
                try await reopened.sourceRevision(id: source.id)
            }
        }
    }

    @Test("Corrupt extraction, unit and provenance encodings fail explicitly", arguments: ExtractionFault.allCases)
    private func corruptExtractions(_ fault: ExtractionFault) async throws {
        let fixture = try SourceStoreFixture()
        defer { fixture.remove() }
        let source = try fixture.source()
        let extraction = try fixture.extraction(sourceID: source.id)
        let seed = try fixture.store()
        let writer = SourceIntegrityWriter(modelContainer: seed.modelContainer)
        try await writer.install(source: source, extractions: [extraction])
        try await writer.corruptExtraction(id: extraction.id, fault: fault)
        let reopened = try fixture.store()
        switch fault {
        case .recordVersion, .predecessorVersion, .unitVersion, .provenanceVersion:
            await #expect(throws: SourceStoreError.unsupportedRecordVersion(2)) {
                try await reopened.extractionRevision(id: extraction.id)
            }
        case .predecessorJSON, .provenanceJSON:
            await #expect(throws: DecodingError.self) {
                try await reopened.extractionRevision(id: extraction.id)
            }
        case .canonicalTextVersion:
            await #expect(throws: SourceIdentityError.unsupportedCanonicalTextVersion(2)) {
                try await reopened.extractionRevision(id: extraction.id)
            }
        case .unitIndex:
            await #expect(throws: SourceIdentityError.invalidUnitOrdering) {
                try await reopened.extractionRevision(id: extraction.id)
            }
        case .textDigest, .changedText:
            await #expect(throws: SourceStoreError.contentHashMismatch) {
                try await reopened.extractionRevision(id: extraction.id)
            }
        case .missingUnit, .unitCount, .origin, .path:
            await #expect(throws: SourceStoreError.corruptRecord) {
                try await reopened.extractionRevision(id: extraction.id)
            }
        }
    }

    @Test("A child cannot hide corrupt predecessor units")
    func corruptPredecessor() async throws {
        let fixture = try SourceStoreFixture()
        defer { fixture.remove() }
        let source = try fixture.source()
        let parent = try fixture.extraction(sourceID: source.id)
        let child = try fixture.extraction(sourceID: source.id, predecessors: [parent.id], origin: .userCorrection)
        let seed = try fixture.store()
        let writer = SourceIntegrityWriter(modelContainer: seed.modelContainer)
        try await writer.install(source: source, extractions: [parent, child])
        try await writer.corruptExtraction(id: parent.id, fault: .changedText)
        let reopened = try fixture.store()
        await #expect(throws: SourceStoreError.contentHashMismatch) {
            try await reopened.extractionRevision(id: child.id)
        }
    }

    @Test("Persisted predecessor cycles fail without recursive overflow")
    func predecessorCycle() async throws {
        let fixture = try SourceStoreFixture()
        defer { fixture.remove() }
        let source = try fixture.source()
        let firstID = UUID()
        let secondID = UUID()
        let first = try fixture.extraction(id: firstID, sourceID: source.id, predecessors: [secondID])
        let second = try fixture.extraction(id: secondID, sourceID: source.id, predecessors: [firstID])
        let seed = try fixture.store()
        let writer = SourceIntegrityWriter(modelContainer: seed.modelContainer)
        try await writer.install(source: source, extractions: [first, second])
        let reopened = try fixture.store()
        await #expect(throws: SourceStoreError.corruptRecord) {
            try await reopened.extractionRevision(id: firstID)
        }
    }

    @Test("Persisted missing predecessors and incomplete corrections fail")
    func corruptStoredLineage() async throws {
        let fixture = try SourceStoreFixture()
        defer { fixture.remove() }
        let source = try fixture.source()
        let parent = try fixture.extraction(sourceID: source.id)
        let missing = try fixture.extraction(sourceID: source.id, predecessors: [UUID()])
        let incomplete = try fixture.extraction(sourceID: source.id, predecessors: [parent.id],
            origin: .userCorrection, texts: ["only one unit"])
        let seed = try fixture.store()
        let writer = SourceIntegrityWriter(modelContainer: seed.modelContainer)
        try await writer.install(source: source, extractions: [parent, missing, incomplete])
        let reopened = try fixture.store()
        await #expect(throws: SourceStoreError.missingPredecessor) {
            try await reopened.extractionRevision(id: missing.id)
        }
        await #expect(throws: SourceStoreError.invalidProvenance) {
            try await reopened.extractionRevision(id: incomplete.id)
        }
    }

    @Test("Persisted foreign lineage and missing sources fail on read")
    func corruptStoredSources() async throws {
        let fixture = try SourceStoreFixture()
        defer { fixture.remove() }
        let source = try fixture.source()
        let foreign = try fixture.source()
        let foreignParent = try fixture.extraction(sourceID: foreign.id)
        let crossed = try fixture.extraction(sourceID: source.id, predecessors: [foreignParent.id])
        let missingSource = try fixture.extraction(sourceID: UUID())
        let seed = try fixture.store()
        let writer = SourceIntegrityWriter(modelContainer: seed.modelContainer)
        try await writer.install(source: source, extractions: [crossed, missingSource])
        try await writer.install(source: foreign, extractions: [foreignParent])
        let reopened = try fixture.store()
        await #expect(throws: SourceStoreError.conflictingLineage) {
            try await reopened.extractionRevision(id: crossed.id)
        }
        await #expect(throws: SourceStoreError.missingSourceRevision) {
            try await reopened.extractionRevision(id: missingSource.id)
        }
    }

    @Test("Unit IDs are globally unique across stored extraction headers")
    func duplicateUnitIDAcrossExtractions() async throws {
        let fixture = try SourceStoreFixture()
        defer { fixture.remove() }
        let source = try fixture.source()
        let original = try fixture.extraction(sourceID: source.id)
        let conflicting = try fixture.extraction(sourceID: source.id, texts: ["different", "second unit"],
            unitIDs: [original.units[0].id, UUID()])
        let seed = try fixture.store()
        let writer = SourceIntegrityWriter(modelContainer: seed.modelContainer)
        try await writer.install(source: source, extractions: [original, conflicting])
        let reopened = try fixture.store()
        for id in [original.id, conflicting.id] {
            await #expect(throws: SourceStoreError.corruptRecord) {
                try await reopened.extractionRevision(id: id)
            }
        }
        let retry = try fixture.extraction(sourceID: source.id)
        await #expect(throws: SourceStoreError.corruptRecord) {
            try await reopened.saveExtraction(retry)
        }
    }

    @Test("Source reuse cannot conceal duplicate IDs with different hashes")
    func duplicateSourceIDOnReuse() async throws {
        let fixture = try SourceStoreFixture()
        defer { fixture.remove() }
        let original = try fixture.source()
        let conflicting = try fixture.source(id: original.id, documentID: original.documentID,
            bytes: [Data("different source".utf8)])
        let seed = try fixture.store()
        let writer = SourceIntegrityWriter(modelContainer: seed.modelContainer)
        try await writer.install(source: original, extractions: [])
        try await writer.install(source: conflicting, extractions: [])
        let reopened = try fixture.store()
        await #expect(throws: SourceStoreError.corruptRecord) {
            try await reopened.sourceRevision(id: original.id)
        }
        let retry = try fixture.source(documentID: original.documentID)
        await #expect(throws: SourceStoreError.corruptRecord) {
            try await reopened.saveSource(retry)
        }
        #expect(try await reopened.sourceRevision(id: retry.id) == nil)
    }

    @Test("Extraction reuse cannot conceal duplicate IDs with different digests")
    func duplicateExtractionIDOnReuse() async throws {
        let fixture = try SourceStoreFixture()
        defer { fixture.remove() }
        let source = try fixture.source()
        let original = try fixture.extraction(sourceID: source.id)
        let conflicting = try fixture.extraction(id: original.id, sourceID: source.id,
            texts: ["different", "second unit"])
        let seed = try fixture.store()
        let writer = SourceIntegrityWriter(modelContainer: seed.modelContainer)
        try await writer.install(source: source, extractions: [original, conflicting])
        let reopened = try fixture.store()
        await #expect(throws: SourceStoreError.corruptRecord) {
            try await reopened.extractionRevision(id: original.id)
        }
        let retry = try fixture.extraction(sourceID: source.id)
        await #expect(throws: SourceStoreError.corruptRecord) {
            try await reopened.saveExtraction(retry)
        }
        #expect(try await reopened.extractionRevision(id: retry.id) == nil)
    }

    @Test("A converging predecessor graph is valid and preserves both parents")
    func convergingGraph() async throws {
        let fixture = try SourceStoreFixture()
        defer { fixture.remove() }
        let store = try fixture.store()
        let source = try fixture.source()
        _ = try await store.saveSource(source)
        let root = try fixture.extraction(sourceID: source.id)
        _ = try await store.saveExtraction(root)
        let left = try fixture.extraction(sourceID: source.id, predecessors: [root.id],
            origin: .userCorrection, texts: ["left", "second unit"])
        let right = try fixture.extraction(sourceID: source.id, predecessors: [root.id],
            origin: .userCorrection, texts: ["right", "second unit"])
        _ = try await store.saveExtraction(left)
        _ = try await store.saveExtraction(right)
        let resolution = try fixture.extraction(sourceID: source.id, predecessors: [left.id, right.id],
            origin: .resolution, texts: ["resolved", "second unit"])
        #expect(try await store.saveExtraction(resolution) == resolution)
        #expect(try await store.extractionRevision(id: resolution.id) == resolution)
        #expect(try await store.extractionRevision(id: root.id) == root)
    }

    @Test("Resolution must preserve the complete basis of every predecessor")
    func incompatibleResolution() async throws {
        let fixture = try SourceStoreFixture()
        defer { fixture.remove() }
        let store = try fixture.store()
        let source = try fixture.source()
        _ = try await store.saveSource(source)
        let first = try fixture.extraction(sourceID: source.id)
        let second = try fixture.extraction(sourceID: source.id, texts: ["one-unit reprocessing"])
        _ = try await store.saveExtraction(first)
        _ = try await store.saveExtraction(second)
        let resolution = try fixture.extraction(sourceID: source.id, predecessors: [first.id, second.id],
            origin: .resolution)
        await #expect(throws: SourceStoreError.invalidProvenance) {
            try await store.saveExtraction(resolution)
        }
        #expect(try await store.extractionRevision(id: resolution.id) == nil)
    }

    @Test("Corrupt local registrations cannot become availability states", arguments: RegistrationFault.allCases)
    private func corruptRegistrations(_ fault: RegistrationFault) async throws {
        let fixture = try SourceStoreFixture()
        defer { fixture.remove() }
        let store = try fixture.store()
        let source = try fixture.source()
        _ = try await store.saveSource(source)
        let path = try fixture.writeOriginal()
        try await store.registerLocalAsset(LocalAssetReference(sourceRevisionID: source.id, memberIndex: 0,
            relativePath: path))
        let writer = SourceIntegrityWriter(modelContainer: store.modelContainer)
        try await writer.corruptRegistration(sourceID: source.id, fault: fault)
        let reopened = try fixture.store()
        switch fault {
        case .recordVersion:
            await #expect(throws: SourceStoreError.unsupportedRecordVersion(2)) {
                try await reopened.availability(sourceRevisionID: source.id)
            }
        case .hash, .duplicateRecord:
            await #expect(throws: SourceStoreError.corruptRecord) {
                try await reopened.availability(sourceRevisionID: source.id)
            }
        case .path:
            await #expect(throws: SourceStoreError.invalidLocalAssetPath) {
                try await reopened.availability(sourceRevisionID: source.id)
            }
        }
    }
}

private struct SourceStoreFixture {
    let directoryURL: URL
    let storeURL: URL
    let assetsURL: URL
    let bytes = [Data([0, 1, 2, 3]), Data([255, 0, 128, 42])]

    init() throws {
        directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("preceptor-source-store-\(UUID().uuidString)")
            .standardizedFileURL.resolvingSymlinksInPath()
        storeURL = directoryURL.appendingPathComponent("history.store")
        assetsURL = directoryURL.appendingPathComponent("originals")
        try FileManager.default.createDirectory(at: assetsURL, withIntermediateDirectories: true)
    }

    func remove() {
        try? FileManager.default.removeItem(at: directoryURL)
    }

    func store() throws -> SwiftDataSourceStore {
        try SwiftDataSourceStore(storeURL: storeURL, localAssetsDirectoryURL: assetsURL)
    }

    func source(id: UUID = UUID(), documentID: UUID = UUID(),
        bytes: [Data]? = nil, names: [String]? = nil,
        createdAt: Date = Date(timeIntervalSince1970: 1_000)) throws -> SourceRevisionSnapshot {
        let originals = bytes ?? self.bytes
        let members = try originals.enumerated().map { index, data in
            try SourceAssetMember(contentHash: SourceContentHasher.hash(originalBytes: data),
                byteCount: Int64(data.count), displayName: names?[index] ?? "original-\(index).png")
        }
        let manifest = try SourceManifest(mediaKind: .image, members: members)
        return SourceRevisionSnapshot(id: id, documentID: documentID,
            contentHash: try SourceContentHasher.hash(manifest: manifest), manifest: manifest, createdAt: createdAt)
    }

    func extraction(id: UUID = UUID(), sourceID: UUID, predecessors: [UUID] = [],
        origin: ExtractionOrigin = .automatic, texts: [String] = ["first unit", "second unit"],
        provenances: [SourceUnitProvenance]? = nil, unitIDs: [UUID]? = nil,
        createdAt: Date = Date(timeIntervalSince1970: 1_000)) throws -> ExtractionRevisionSnapshot {
        let units = try texts.enumerated().map { index, text in
            try SourceUnitSnapshot(id: unitIDs?[index] ?? UUID(), unitIndex: index, text: text,
                provenance: provenances?[index] ?? SourceUnitProvenance(assetMemberIndex: index, unitIndexInAsset: 0,
                    extractionPath: .imageOCR))
        }
        return try ExtractionRevisionSnapshot(id: id, sourceRevisionID: sourceID, predecessorIDs: predecessors,
            origin: origin, extractorVersion: "image-recognizer-1", units: units, createdAt: createdAt)
    }

    func writeOriginal() throws -> String {
        let path = "member-0.png"
        try bytes[0].write(to: assetsURL.appendingPathComponent(path))
        return path
    }
}

private enum CorrectionFault: CaseIterable, Sendable {
    case omittedUnit, emptyUnits, reorderedProvenance, changedRecognitionUnit, typedPath

    func snapshot(fixture: SourceStoreFixture,
        predecessor: ExtractionRevisionSnapshot) throws -> ExtractionRevisionSnapshot {
        var texts = ["changed", "second unit"]
        var provenances = predecessor.units.map(\.provenance)
        switch self {
        case .omittedUnit:
            texts = ["changed"]
            provenances = [provenances[0]]
        case .emptyUnits:
            texts = []
            provenances = []
        case .reorderedProvenance:
            provenances.reverse()
        case .changedRecognitionUnit:
            provenances[0] = try SourceUnitProvenance(assetMemberIndex: 0, unitIndexInAsset: 1,
                extractionPath: .imageOCR)
        case .typedPath:
            provenances[0] = try SourceUnitProvenance(assetMemberIndex: 0, unitIndexInAsset: 0, extractionPath: .typed)
        }
        return try fixture.extraction(sourceID: predecessor.sourceRevisionID, predecessors: [predecessor.id],
            origin: .userCorrection, texts: texts, provenances: provenances)
    }
}

private enum SourceFault: CaseIterable, Sendable {
    case recordVersion, manifestVersion, malformedJSON, hash, byteCount, mediaKind
    case duplicateRecord
}

private enum ExtractionFault: CaseIterable, Sendable {
    case recordVersion, predecessorVersion, predecessorJSON, unitVersion
    case provenanceVersion, provenanceJSON, canonicalTextVersion, unitIndex
    case textDigest, changedText, missingUnit, unitCount, origin, path
}

private enum RegistrationFault: CaseIterable, Sendable {
    case recordVersion, hash, duplicateRecord, path
}

private enum SourceSaveFailure: Error, Equatable {
    case simulated
}

private enum CommitFault: CaseIterable, Sendable {
    case failure, cancellation

    func inject() throws {
        switch self {
        case .failure: throw SourceSaveFailure.simulated
        case .cancellation: withUnsafeCurrentTask { $0?.cancel() }
        }
    }
}

@ModelActor
private actor SourceIntegrityWriter {
    private typealias Schema = SourceStoreSchema

    func install(source: SourceRevisionSnapshot, extractions: [ExtractionRevisionSnapshot]) throws {
        modelContext.autosaveEnabled = false
        modelContext.insert(try SourceRecordMapper.sourceRecord(source))
        try installExtractions(extractions)
    }

    func installExtractions(_ extractions: [ExtractionRevisionSnapshot]) throws {
        modelContext.autosaveEnabled = false
        for extraction in extractions {
            modelContext.insert(try SourceRecordMapper.extractionRecord(extraction))
            for unit in extraction.units {
                modelContext.insert(try SourceRecordMapper.unitRecord(unit, extractionID: extraction.id))
            }
        }
        try modelContext.save()
    }

    func corruptSource(id: UUID, fault: SourceFault) throws {
        let row = try #require(modelContext.fetch(FetchDescriptor<Schema.SourceRecord>(predicate: #Predicate {
            $0.id == id
        })).first)
        switch fault {
        case .recordVersion: row.recordVersion = 2
        case .manifestVersion:
            row.manifestJSON = row.manifestJSON.replacingOccurrences(of: "\"version\":1", with: "\"version\":2")
        case .malformedJSON: row.manifestJSON = "{"
        case .hash: row.contentHash = String(repeating: "0", count: 64)
        case .byteCount: row.byteCount += 1
        case .mediaKind: row.mediaKindRaw = "future-media"
        case .duplicateRecord:
            modelContext.insert(try SourceRecordMapper.sourceRecord(SourceRecordMapper.source(row)))
        }
        try modelContext.save()
    }

    func corruptExtraction(id: UUID, fault: ExtractionFault) throws {
        let row = try #require(modelContext.fetch(FetchDescriptor<Schema.ExtractionRecord>(predicate: #Predicate {
            $0.id == id
        })).first)
        let units = try modelContext.fetch(FetchDescriptor<Schema.UnitRecord>(predicate: #Predicate {
            $0.extractionRevisionID == id
        }, sortBy: [SortDescriptor(\.unitIndex)]))
        let unit = try #require(units.first)
        switch fault {
        case .recordVersion: row.recordVersion = 2
        case .predecessorVersion:
            row.predecessorIDsJSON = "{\"version\":2,\"ids\":[]}"
        case .predecessorJSON: row.predecessorIDsJSON = "{"
        case .unitVersion: unit.recordVersion = 2
        case .provenanceVersion:
            unit.provenanceJSON = unit.provenanceJSON.replacingOccurrences(of: "\"version\":1", with: "\"version\":2")
        case .provenanceJSON: unit.provenanceJSON = "{"
        case .canonicalTextVersion: unit.canonicalTextVersion = 2
        case .unitIndex: unit.unitIndex = 9
        case .textDigest: row.textDigest = String(repeating: "0", count: 64)
        case .changedText: unit.text = "tampered text"
        case .missingUnit: modelContext.delete(unit)
        case .unitCount: row.unitCount += 1
        case .origin: row.originRaw = "future-origin"
        case .path:
            unit.provenanceJSON = unit.provenanceJSON.replacingOccurrences(of: "imageOCR", with: "future-path")
        }
        try modelContext.save()
    }

    func counts() throws -> [Int] {
        [
            try modelContext.fetchCount(FetchDescriptor<Schema.SourceRecord>()),
            try modelContext.fetchCount(FetchDescriptor<Schema.ExtractionRecord>()),
            try modelContext.fetchCount(FetchDescriptor<Schema.UnitRecord>()),
            try modelContext.fetchCount(FetchDescriptor<Schema.LocalAssetRecord>())
        ]
    }

    func corruptRegistration(sourceID: UUID, fault: RegistrationFault) throws {
        let row = try #require(modelContext.fetch(FetchDescriptor<Schema.LocalAssetRecord>(predicate: #Predicate {
            $0.sourceRevisionID == sourceID
        })).first)
        switch fault {
        case .recordVersion: row.recordVersion = 2
        case .hash: row.contentHash = String(repeating: "0", count: 64)
        case .path: row.relativePath = "../outside.png"
        case .duplicateRecord:
            let duplicate = Schema.LocalAssetRecord()
            duplicate.sourceRevisionID = row.sourceRevisionID
            duplicate.memberIndex = row.memberIndex
            duplicate.relativePath = row.relativePath
            duplicate.contentHash = row.contentHash
            modelContext.insert(duplicate)
        }
        try modelContext.save()
    }
}
