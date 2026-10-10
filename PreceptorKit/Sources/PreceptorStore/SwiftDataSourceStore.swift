//
//  SwiftDataSourceStore.swift
//  PreceptorKit
//
//  Created by TaeVon Lewis on 10/5/26.
//


import Foundation
import PreceptorCore
import SwiftData

public actor SwiftDataSourceStore: ModelActor, SourceRevisionStoring {
    public nonisolated let modelContainer: ModelContainer
    public nonisolated let modelExecutor: any ModelExecutor

    private typealias Schema = SourceStoreSchema

    private let localAssetsDirectoryURL: URL
    private let beforeSave: @Sendable () throws -> Void

    public init(storeURL: URL, localAssetsDirectoryURL: URL) throws {
        try self.init(storeURL: storeURL, localAssetsDirectoryURL: localAssetsDirectoryURL, beforeSave: {})
    }

    init(storeURL: URL, localAssetsDirectoryURL: URL, beforeSave: @escaping @Sendable () throws -> Void) throws {
        guard storeURL.isFileURL, localAssetsDirectoryURL.isFileURL else {
            throw SourceStoreError.invalidLocalAssetPath
        }

        try FileManager.default.createDirectory(at: storeURL.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        let schema = SwiftData.Schema(versionedSchema: Schema.self)
        let configuration = ModelConfiguration("SourceHistory", schema: schema, url: storeURL, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)
        context.autosaveEnabled = false
        modelContainer = container
        modelExecutor = DefaultSerialModelExecutor(modelContext: context)
        self.localAssetsDirectoryURL = localAssetsDirectoryURL
            .standardizedFileURL.resolvingSymlinksInPath()
        self.beforeSave = beforeSave
    }

    func beginImportAttempt(id: UUID, source: SourceRevisionSnapshot, createdAt: Date) throws -> SourceImportAttempt {
        try Task.checkCancellation()
        try SourceRecordMapper.validateSource(source)

        guard createdAt.timeIntervalSince1970.isFinite else {
            throw SourceStoreError.corruptRecord
        }

        guard try importAttemptRow(id: id) == nil else {
            throw SourceStoreError.conflictingRecordID
        }

        let row = Schema.ImportAttemptRecord()
        row.id = id
        row.createdAt = createdAt
        row.documentID = source.documentID
        row.contentHash = source.contentHash.hexDigest
        row.stateRaw = SourceImportAttempt.State.started.rawValue

        let attempt = try mappedImportAttempt(row)

        try commit {
            modelContext.insert(row)
        }

        return attempt
    }

    public func importAttempt(id: UUID) throws -> SourceImportAttempt? {
        try Task.checkCancellation()
        return try importAttemptRow(id: id).map(mappedImportAttempt)
    }

    public func saveSource(_ revision: SourceRevisionSnapshot) throws -> SourceRevisionSnapshot {
        try Task.checkCancellation()
        try SourceRecordMapper.validateSource(revision)
        if let existing = try source(id: revision.id) {
            guard existing.documentID == revision.documentID,
                  sameSourceContent(existing, revision) else {
                throw SourceStoreError.conflictingRecordID
            }

            return existing
        }

        let documentID = revision.documentID
        let contentHash = revision.contentHash.hexDigest
        let rows = try modelContext.fetch(FetchDescriptor<Schema.SourceRecord>(predicate: #Predicate {
            $0.documentID == documentID && $0.contentHash == contentHash
        }))
        guard rows.count <= 1 else { throw SourceStoreError.corruptRecord }
        if let row = rows.first {
            guard let existing = try source(id: row.id) else {
                throw SourceStoreError.corruptRecord
            }

            guard sameSourceContent(existing, revision) else {
                throw SourceStoreError.contentHashMismatch
            }
            // Reimport does not rewrite original names, IDs, or timestamps.
            return existing
        }

        let row = try SourceRecordMapper.sourceRecord(revision)
        try commit {
            modelContext.insert(row)
        }

        return revision
    }

    public func sourceRevision(id: UUID) throws -> SourceRevisionSnapshot? {
        try Task.checkCancellation()
        return try source(id: id)
    }

    public func saveExtraction(_ revision: ExtractionRevisionSnapshot) throws -> ExtractionRevisionSnapshot {
        try Task.checkCancellation()
        guard revision.createdAt.timeIntervalSince1970.isFinite else {
            throw SourceStoreError.corruptRecord
        }

        guard let source = try source(id: revision.sourceRevisionID) else {
            throw SourceStoreError.missingSourceRevision
        }

        try validateProvenance(revision, source: source)
        let predecessors = try revision.predecessorIDs.map { id in
            guard let predecessor = try extraction(id: id) else {
                throw SourceStoreError.missingPredecessor
            }

            guard predecessor.sourceRevisionID == revision.sourceRevisionID else {
                throw SourceStoreError.conflictingLineage
            }

            return predecessor
        }

        try validateCorrection(revision, predecessors: predecessors)
        if let existing = try extraction(id: revision.id) {
            guard existing.canonicalIdentityData == revision.canonicalIdentityData
            else { throw SourceStoreError.conflictingRecordID }
            return existing
        }

        let sourceID = revision.sourceRevisionID
        let textDigest = SourceRecordMapper.hash(revision.canonicalIdentityData)
        let matches = try modelContext.fetch(FetchDescriptor<Schema.ExtractionRecord>(predicate: #Predicate {
            $0.sourceRevisionID == sourceID && $0.textDigest == textDigest
        }))
        guard matches.count <= 1 else { throw SourceStoreError.corruptRecord }
        if let row = matches.first {
            guard let existing = try extraction(id: row.id) else {
                throw SourceStoreError.corruptRecord
            }

            guard existing.canonicalIdentityData == revision.canonicalIdentityData
            else { throw SourceStoreError.contentHashMismatch }
            return existing
        }
        // Unit UUIDs identify immutable records, not reusable mutable slots.
        for unit in revision.units {
            try Task.checkCancellation()
            let unitID = unit.id
            let rows = try modelContext.fetch(FetchDescriptor<Schema.UnitRecord>(
                predicate: #Predicate { $0.id == unitID }))
            guard rows.isEmpty else { throw SourceStoreError.conflictingRecordID }
        }

        let header = try SourceRecordMapper.extractionRecord(revision)
        let units = try revision.units.map {
            try SourceRecordMapper.unitRecord($0, extractionID: revision.id)
        }

        try commit {
            modelContext.insert(header)
            for unit in units { modelContext.insert(unit) }
        }

        return revision
    }

    public func extractionRevision(id: UUID) throws -> ExtractionRevisionSnapshot? {
        try Task.checkCancellation()
        return try extraction(id: id)
    }

    public func registerLocalAsset(_ reference: LocalAssetReference) throws {
        try Task.checkCancellation()
        guard let source = try source(id: reference.sourceRevisionID) else {
            throw SourceStoreError.missingSourceRevision
        }

        guard source.manifest.members.indices.contains(reference.memberIndex)
        else { throw SourceStoreError.invalidProvenance }
        let url = try localURL(for: reference.relativePath)
        let member = source.manifest.members[reference.memberIndex]
        guard try matchingBytes(at: url, member: member) else {
            throw SourceStoreError.localAssetContentMismatch
        }

        let rows = try registrations(sourceID: reference.sourceRevisionID, index: reference.memberIndex)
        guard rows.count <= 1 else { throw SourceStoreError.corruptRecord }
        let row = rows.first ?? Schema.LocalAssetRecord()
        try SourceRecordMapper.supported(row.recordVersion)
        try commit {
            row.sourceRevisionID = reference.sourceRevisionID
            row.memberIndex = reference.memberIndex
            row.relativePath = reference.relativePath
            row.contentHash = member.contentHash.hexDigest
            if rows.isEmpty { modelContext.insert(row) }
        }
    }

    public func availability(sourceRevisionID: UUID) throws -> [SourceAssetAvailability] {
        try Task.checkCancellation()
        guard let source = try source(id: sourceRevisionID) else {
            throw SourceStoreError.missingSourceRevision
        }

        return try source.manifest.members.enumerated().map { index, member in
            try Task.checkCancellation()
            let rows = try registrations(sourceID: sourceRevisionID, index: index)
            guard rows.count <= 1 else { throw SourceStoreError.corruptRecord }
            guard let row = rows.first else { return .unregistered }
            try SourceRecordMapper.supported(row.recordVersion)
            guard row.contentHash == member.contentHash.hexDigest else {
                throw SourceStoreError.corruptRecord
            }

            let url = try localURL(for: row.relativePath)
            do {
                return try matchingBytes(at: url, member: member)
                    ? .available(url) : .contentMismatch
            } catch let error as CocoaError where
                error.code == .fileReadNoSuchFile {
                return .missing
            }
        }
    }

    private func importAttemptRow(id: UUID) throws -> Schema.ImportAttemptRecord? {
        let rows = try modelContext.fetch(FetchDescriptor<Schema.ImportAttemptRecord>(
            predicate: #Predicate { $0.id == id }))

        guard rows.count <= 1 else {
            throw SourceStoreError.corruptRecord
        }

        return rows.first
    }

    private func mappedImportAttempt(_ row: Schema.ImportAttemptRecord) throws -> SourceImportAttempt {
        try SourceRecordMapper.supported(row.recordVersion)

        guard row.createdAt.timeIntervalSince1970.isFinite, let state = SourceImportAttempt.State(rawValue: row.stateRaw) else {
            throw SourceStoreError.corruptRecord
        }

        let contentHash = try SourceContentHash(hexDigest: row.contentHash)

        if state == .started {
            guard row.finishedAt == nil, row.sourceRevisionID == nil else {
                throw SourceStoreError.corruptRecord
            }
        } else {
            guard let finishedAt = row.finishedAt, finishedAt.timeIntervalSince1970.isFinite else {
                throw SourceStoreError.corruptRecord
            }

            if state == .completed {
                guard let sourceID = row.sourceRevisionID, let committedSource = try source(id: sourceID),
                      committedSource.documentID == row.documentID, committedSource.contentHash == contentHash else {
                    throw SourceStoreError.corruptRecord
                }
            } else {
                guard row.sourceRevisionID == nil else {
                    throw SourceStoreError.corruptRecord
                }
            }
        }

        return SourceImportAttempt(encodingVersion: row.recordVersion, id: row.id, documentID: row.documentID,
                                   contentHash: contentHash, createdAt: row.createdAt, state: state,
                                   finishedAt: row.finishedAt, sourceRevisionID: row.sourceRevisionID)
    }


    private func source(id: UUID) throws -> SourceRevisionSnapshot? {
        let rows = try modelContext.fetch(FetchDescriptor<Schema.SourceRecord>(predicate: #Predicate { $0.id == id }))
        guard rows.count <= 1 else { throw SourceStoreError.corruptRecord }
        return try rows.first.map(SourceRecordMapper.source)
    }

    private func extractionRow(id: UUID) throws -> Schema.ExtractionRecord? {
        let rows = try modelContext.fetch(FetchDescriptor<Schema.ExtractionRecord>(predicate: #Predicate {
            $0.id == id
        }))
        guard rows.count <= 1 else { throw SourceStoreError.corruptRecord }
        return rows.first
    }

    private func extraction(id: UUID) throws -> ExtractionRevisionSnapshot? {
        try extractionRow(id: id).map(mappedExtraction)
    }

    private func mappedExtraction(_ row: Schema.ExtractionRecord) throws -> ExtractionRevisionSnapshot {
        // Postorder traversal validates complete ancestors once each. Explicit
        // stack storage avoids call-stack growth; active IDs reject cycles while
        // completed IDs allow shared ancestry in a valid predecessor DAG.
        let root = try localExtraction(row)
        var values = [root.id: root]
        var completed = [UUID: ExtractionRevisionSnapshot]()
        var active = Set<UUID>()
        var stack = [(id: root.id, finish: false)]
        while let entry = stack.popLast() {
            try Task.checkCancellation()
            if completed[entry.id] != nil { continue }
            let value: ExtractionRevisionSnapshot
            if let loaded = values[entry.id] {
                value = loaded
            } else {
                guard let predecessor = try extractionRow(id: entry.id) else {
                    throw SourceStoreError.missingPredecessor
                }
                value = try localExtraction(predecessor)
                values[entry.id] = value
            }

            guard value.sourceRevisionID == root.sourceRevisionID else {
                throw SourceStoreError.conflictingLineage
            }

            if entry.finish {
                let predecessors = try value.predecessorIDs.map { id in
                    guard let predecessor = completed[id] else {
                        throw SourceStoreError.corruptRecord
                    }

                    return predecessor
                }

                try validateCorrection(value, predecessors: predecessors)
                active.remove(entry.id)
                completed[entry.id] = value
            } else {
                guard active.insert(entry.id).inserted else {
                    throw SourceStoreError.corruptRecord
                }
                stack.append((entry.id, true))
                for id in value.predecessorIDs.reversed() {
                    stack.append((id, false))
                }
            }
        }

        return root
    }

    private func localExtraction(_ row: Schema.ExtractionRecord) throws -> ExtractionRevisionSnapshot {
        try Task.checkCancellation()
        let id = row.id
        let rows = try modelContext.fetch(FetchDescriptor<Schema.UnitRecord>(
            predicate: #Predicate { $0.extractionRevisionID == id }))
        for unit in rows {
            let unitID = unit.id
            let matches = try modelContext.fetch(FetchDescriptor<Schema.UnitRecord>(
                predicate: #Predicate { $0.id == unitID }))
            guard matches.count == 1 else {
                throw SourceStoreError.corruptRecord
            }
        }

        let value = try SourceRecordMapper.extraction(row, units: rows)
        guard let source = try source(id: value.sourceRevisionID) else {
            throw SourceStoreError.missingSourceRevision
        }

        try validateProvenance(value, source: source)
        return value
    }

    private func validateProvenance(_ revision: ExtractionRevisionSnapshot, source: SourceRevisionSnapshot) throws {
        for unit in revision.units {
            guard source.manifest.members.indices.contains(unit.provenance.assetMemberIndex) else {
                throw SourceStoreError.invalidProvenance
            }

            let path = unit.provenance.extractionPath
            let compatible: Bool
            switch source.manifest.mediaKind {
            case .pdf: compatible = path == .pdfText || path == .pdfOCR
            case .image: compatible = path == .imageOCR
            case .audio: compatible = path == .asr
            case .typed: compatible = path == .typed
            }

            guard compatible else { throw SourceStoreError.invalidProvenance }
        }
    }

    private func validateCorrection(_ revision: ExtractionRevisionSnapshot,
        predecessors: [ExtractionRevisionSnapshot]) throws {
        guard revision.origin != .automatic else { return }
        // A text correction retains recognition provenance; it cannot relabel
        // OCR/ASR as typed text and bypass later verification requirements.
        for predecessor in predecessors {
            guard revision.units.count == predecessor.units.count,
                  zip(revision.units, predecessor.units).allSatisfy({ unit, old in
                      unit.unitIndex == old.unitIndex
                          && unit.provenance == old.provenance
                  }) else { throw SourceStoreError.invalidProvenance }
        }
    }

    private func sameSourceContent(_ first: SourceRevisionSnapshot, _ second: SourceRevisionSnapshot) -> Bool {
        first.contentHash == second.contentHash
            && first.manifest.canonicalIdentityData
                == second.manifest.canonicalIdentityData
    }

    private func registrations(sourceID: UUID, index: Int) throws -> [Schema.LocalAssetRecord] {
        try modelContext.fetch(FetchDescriptor<Schema.LocalAssetRecord>(predicate: #Predicate {
            $0.sourceRevisionID == sourceID && $0.memberIndex == index
        }))
    }

    private func localURL(for path: String) throws -> URL {
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !path.isEmpty, !path.contains("\0"),
              !components.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." })
        else { throw SourceStoreError.invalidLocalAssetPath }
        let url = localAssetsDirectoryURL.appendingPathComponent(path)
            .standardizedFileURL.resolvingSymlinksInPath()
        let root = localAssetsDirectoryURL.pathComponents
        guard url.pathComponents.count > root.count,
              url.pathComponents.starts(with: root) else {
            throw SourceStoreError.invalidLocalAssetPath
        }

        return url
    }

    private func matchingBytes(at url: URL, member: SourceAssetMember) throws -> Bool {
        let attributes = try url.resourceValues(forKeys: [.isRegularFileKey])
        guard attributes.isRegularFile == true else {
            throw SourceStoreError.invalidLocalAssetPath
        }

        let bytes = try Data(contentsOf: url)
        try Task.checkCancellation()
        return Int64(bytes.count) == member.byteCount
            && SourceRecordMapper.hash(bytes) == member.contentHash.hexDigest
    }

    private func commit(_ mutation: () throws -> Void) throws {
        do {
            try Task.checkCancellation()
            try mutation()
            try Task.checkCancellation()
            try beforeSave()
            try Task.checkCancellation()
            try modelContext.save()
        } catch {
            // Rollback discards every unsaved row, including partial units.
            modelContext.rollback()
            throw error
        }
    }
}
