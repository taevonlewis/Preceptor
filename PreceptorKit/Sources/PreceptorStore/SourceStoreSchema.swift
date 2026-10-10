//
//  SourceStoreSchema.swift
//  PreceptorKit
//
//  Created by TaeVon Lewis on 10/5/26.
//


import Foundation
import SwiftData

enum SourceStoreSchema: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }
    static var models: [any PersistentModel.Type] {
        [SourceRecord.self, ExtractionRecord.self, UnitRecord.self, LocalAssetRecord.self, ImportAttemptRecord.self]
    }

    @Model final class SourceRecord {
        var id: UUID = UUID()
        var recordVersion: Int = 1
        var createdAt: Date = Date(timeIntervalSince1970: 0)
        var documentID: UUID = UUID()
        var contentHash: String = ""
        var mediaKindRaw: String = ""
        var byteCount: Int64 = 0
        var manifestJSON: String = ""

        init() {}
    }

    @Model final class ExtractionRecord {
        var id: UUID = UUID()
        var recordVersion: Int = 1
        var createdAt: Date = Date(timeIntervalSince1970: 0)
        var sourceRevisionID: UUID = UUID()
        var predecessorIDsJSON: String = ""
        var originRaw: String = ""
        var extractorVersion: String = ""
        var textDigest: String = ""
        var unitCount: Int = 0

        init() {}
    }

    @Model final class UnitRecord {
        var id: UUID = UUID()
        var recordVersion: Int = 1
        var extractionRevisionID: UUID = UUID()
        var unitIndex: Int = 0
        var text: String = ""
        var canonicalTextVersion: Int = 1
        var provenanceJSON: String = ""

        init() {}
    }

    @Model final class LocalAssetRecord {
        var id: UUID = UUID()
        var recordVersion: Int = 1
        var sourceRevisionID: UUID = UUID()
        var memberIndex: Int = 0
        var relativePath: String = ""
        var contentHash: String = ""

        init() {}
    }

    @Model final class ImportAttemptRecord {
        var id: UUID = UUID()
        var recordVersion: Int = 1
        var createdAt: Date = Date(timeIntervalSince1970: 0)
        var documentID: UUID = UUID()
        var contentHash: String = ""
        var stateRaw: String = "started"
        var finishedAt: Date? = nil
        var sourceRevisionID: UUID? = nil

        init() {}
    }
}
