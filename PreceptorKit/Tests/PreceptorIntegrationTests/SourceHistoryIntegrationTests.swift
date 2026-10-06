//
//  SourceHistoryIntegrationTests.swift
//  PreceptorKit
//
//  Created by TaeVon Lewis on 10/5/26.
//


import Foundation
import PreceptorCore
import PreceptorExtract
import PreceptorGenerate
import PreceptorStore
import Testing

@Suite("Source history integration")
struct SourceHistoryIntegrationTests {
    @Test("Reopened storage preserves sources, units, correction history and lineage")
    func reopenSourceHistory() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("preceptor-source-integration-\(UUID().uuidString)")
            .standardizedFileURL.resolvingSymlinksInPath()
        defer { try? FileManager.default.removeItem(at: directory) }
        let assetsURL = directory.appendingPathComponent("originals")
        try FileManager.default.createDirectory(at: assetsURL, withIntermediateDirectories: true)
        let storeURL = directory.appendingPathComponent("history.store")
        let snapshots = try await writeHistory(storeURL: storeURL, assetsURL: assetsURL)

        let reopened = try SwiftDataSourceStore(storeURL: storeURL, localAssetsDirectoryURL: assetsURL)
        let source = try #require(await reopened.sourceRevision(id: snapshots.source.id))
        let original = try #require(await reopened.extractionRevision(id: snapshots.original.id))
        let correction = try #require(await reopened.extractionRevision(id: snapshots.correction.id))
        #expect(source == snapshots.source)
        #expect(original == snapshots.original)
        #expect(correction == snapshots.correction)
        #expect(original.units[0].text.utf8.elementsEqual("Cafe\u{301}\r\n".utf8))
        #expect(correction.predecessorIDs == [original.id])
        #expect(correction.units[0].provenance == original.units[0].provenance)
        #expect(try await reopened.availability(sourceRevisionID: source.id)
            == [.available(assetsURL.appendingPathComponent("original.txt"))])

        let retry = SourceRevisionSnapshot(id: UUID(), documentID: source.documentID,
            contentHash: source.contentHash, manifest: try SourceManifest(mediaKind: .typed, members: [
                SourceAssetMember(contentHash: source.manifest.members[0].contentHash,
                    byteCount: source.manifest.members[0].byteCount, displayName: "renamed.txt")
            ]), createdAt: Date(timeIntervalSince1970: 2_000))
        #expect(try await reopened.saveSource(retry) == source)
        #expect(try await reopened.sourceRevision(id: retry.id) == nil)

        let request = GenerationRequest(documentID: source.documentID, sourceRevisionID: source.id,
            extractionRevisionID: correction.id, sourceTextID: correction.units[0].id, text: correction.units[0].text)
        let generated = try await DeterministicStudyGenerator().generate(request)
        #expect(generated.request == request)
        #expect(generated.array.first?.quote == correction.units[0].text)
        #expect(try await reopened.extractionRevision(id: original.id) == original)
    }

    private func writeHistory(storeURL: URL, assetsURL: URL) async throws -> (source: SourceRevisionSnapshot,
        original: ExtractionRevisionSnapshot, correction: ExtractionRevisionSnapshot) {
        let store = try SwiftDataSourceStore(storeURL: storeURL, localAssetsDirectoryURL: assetsURL)
        let bytes = Data("Cafe\u{301}\r\n".utf8)
        try bytes.write(to: assetsURL.appendingPathComponent("original.txt"))
        let manifest = try SourceManifest(mediaKind: .typed, members: [
            SourceAssetMember(contentHash: SourceContentHasher.hash(originalBytes: bytes),
                byteCount: Int64(bytes.count), displayName: "original.txt")
        ])
        let source = SourceRevisionSnapshot(id: UUID(), documentID: UUID(),
            contentHash: try SourceContentHasher.hash(manifest: manifest),
            manifest: manifest, createdAt: Date(timeIntervalSince1970: 1_000))
        _ = try await store.saveSource(source)
        let provenance = try SourceUnitProvenance(assetMemberIndex: 0, unitIndexInAsset: 0, extractionPath: .typed)
        let original = try ExtractionRevisionSnapshot(id: UUID(), sourceRevisionID: source.id, predecessorIDs: [],
            origin: .automatic, extractorVersion: "typed-1", units: [
                SourceUnitSnapshot(id: UUID(), unitIndex: 0,
                    text: String(decoding: bytes, as: UTF8.self), provenance: provenance)
            ], createdAt: Date(timeIntervalSince1970: 1_001))
        _ = try await store.saveExtraction(original)
        let correction = try ExtractionRevisionSnapshot(id: UUID(), sourceRevisionID: source.id,
            predecessorIDs: [original.id], origin: .userCorrection, extractorVersion: "typed-1", units: [
                SourceUnitSnapshot(id: UUID(), unitIndex: 0, text: "Corrected cafe\u{301}\r\n", provenance: provenance)
            ], createdAt: Date(timeIntervalSince1970: 1_002))
        _ = try await store.saveExtraction(correction)
        try await store.registerLocalAsset(LocalAssetReference(sourceRevisionID: source.id, memberIndex: 0,
            relativePath: "original.txt"))
        return (source, original, correction)
    }
}
