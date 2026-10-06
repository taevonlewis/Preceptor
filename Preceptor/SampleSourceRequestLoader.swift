//
//  SampleSourceRequestLoader.swift
//  PreceptorKit
//
//  Created by TaeVon Lewis on 10/5/26.
//


import Foundation
import PreceptorCore
import PreceptorExtract
import PreceptorStore

nonisolated struct SampleSourceRequestLoader: Sendable {
    private let store: any SourceRevisionStoring
    private static let text = "sample text"
    private static let documentID = UUID(uuid: (0x7c, 0x94, 0x67, 0x28, 0xd5, 0xb8, 0x49, 0x85,
        0xa9, 0x61, 0x9c, 0x67, 0x07, 0xd6, 0x30, 0x44))

    init(store: any SourceRevisionStoring) {
        self.store = store
    }

    @concurrent static func persistent() async throws -> Self {
        try Task.checkCancellation()
        let directory = try FileManager.default.url(for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true).appendingPathComponent("SourceHistory", isDirectory: true)
        let store = try SwiftDataSourceStore(storeURL: directory.appendingPathComponent("sources.store"),
            localAssetsDirectoryURL: directory.appendingPathComponent("Originals", isDirectory: true))
        try Task.checkCancellation()
        return Self(store: store)
    }

    func load() async throws -> GenerationRequest {
        try Task.checkCancellation()
        let bytes = Data(Self.text.utf8)
        let member = try SourceAssetMember(contentHash: SourceContentHasher.hash(originalBytes: bytes),
            byteCount: Int64(bytes.count),
            displayName: "Sample text")
        let manifest = try SourceManifest(mediaKind: .typed, members: [member])
        let source = try await store.saveSource(SourceRevisionSnapshot(id: UUID(),
            documentID: Self.documentID,
            contentHash: SourceContentHasher.hash(manifest: manifest),
            manifest: manifest,
            createdAt: Date()))
        let unit = try SourceUnitSnapshot(id: UUID(),
            unitIndex: 0,
            text: Self.text,
            provenance: SourceUnitProvenance(assetMemberIndex: 0,
                unitIndexInAsset: 0,
                extractionPath: .typed))
        let extraction = try await store.saveExtraction(ExtractionRevisionSnapshot(id: UUID(),
            sourceRevisionID: source.id,
            predecessorIDs: [],
            origin: .automatic,
            extractorVersion: "typed-sample-v1",
            units: [unit],
            createdAt: Date()))
        guard let loadedSource = try await store.sourceRevision(id: source.id),
              let loadedExtraction = try await store.extractionRevision(id: extraction.id),
              loadedSource == source,
              loadedExtraction == extraction,
              loadedExtraction.sourceRevisionID == loadedSource.id,
              loadedExtraction.units.count == 1,
              let loadedUnit = loadedExtraction.units.first else {
            throw LoadingError.incompleteSavedSample
        }
        try Task.checkCancellation()
        return GenerationRequest(documentID: loadedSource.documentID,
            sourceRevisionID: loadedSource.id,
            extractionRevisionID: loadedExtraction.id,
            sourceTextID: loadedUnit.id,
            text: loadedUnit.text)
    }

    private enum LoadingError: LocalizedError, Sendable {
        case incompleteSavedSample

        var errorDescription: String? {
            "The saved sample source could not be loaded completely."
        }
    }
}
