//
//  SourceRecordMapper.swift
//  PreceptorKit
//
//  Created by TaeVon Lewis on 10/5/26.
//


import CryptoKit
import Foundation
import PreceptorCore

enum SourceRecordMapper {
    typealias Schema = SourceStoreSchema

    private struct ManifestPayload: Codable {
        let version: Int
        let mediaKind: String
        let members: [MemberPayload]
    }

    private struct MemberPayload: Codable {
        let contentHash: String
        let byteCount: Int64
        let displayName: String
    }

    private struct PredecessorPayload: Codable {
        let version: Int
        let ids: [UUID]
    }

    private struct ProvenancePayload: Codable {
        let version: Int
        let assetMemberIndex: Int
        let unitIndexInAsset: Int
        let extractionPath: String
    }

    static func hash(_ bytes: Data) -> String {
        let digits = Array("0123456789abcdef".utf8)
        let digest = SHA256.hash(data: bytes)
        var result = [UInt8]()
        result.reserveCapacity(64)
        for byte in digest {
            result.append(digits[Int(byte >> 4)])
            result.append(digits[Int(byte & 15)])
        }

        return String(decoding: result, as: UTF8.self)
    }

    static func validateSource(_ value: SourceRevisionSnapshot) throws {
        guard value.createdAt.timeIntervalSince1970.isFinite else {
            throw SourceStoreError.corruptRecord
        }

        guard hash(value.manifest.canonicalIdentityData)
            == value.contentHash.hexDigest else {
            throw SourceStoreError.contentHashMismatch
        }
    }

    static func source(_ row: Schema.SourceRecord) throws -> SourceRevisionSnapshot {
        try supported(row.recordVersion)
        let payload = try decode(ManifestPayload.self, from: row.manifestJSON)
        try supported(payload.version)
        guard let kind = SourceMediaKind(rawValue: payload.mediaKind),
              row.mediaKindRaw == payload.mediaKind else {
            throw SourceStoreError.corruptRecord
        }

        let members = try payload.members.map {
            try SourceAssetMember(contentHash: SourceContentHash(hexDigest: $0.contentHash), byteCount: $0.byteCount,
                displayName: $0.displayName)
        }

        let manifest = try SourceManifest(mediaKind: kind, members: members)
        guard row.byteCount == manifest.byteCount else {
            throw SourceStoreError.corruptRecord
        }

        let value = SourceRevisionSnapshot(id: row.id, documentID: row.documentID,
            contentHash: try SourceContentHash(hexDigest: row.contentHash),
            manifest: manifest, createdAt: row.createdAt)
        try validateSource(value)
        return value
    }

    static func sourceRecord(_ value: SourceRevisionSnapshot) throws -> Schema.SourceRecord {
        let row = Schema.SourceRecord()
        row.id = value.id
        row.recordVersion = value.encodingVersion
        row.createdAt = value.createdAt
        row.documentID = value.documentID
        row.contentHash = value.contentHash.hexDigest
        row.mediaKindRaw = value.manifest.mediaKind.rawValue
        row.byteCount = value.manifest.byteCount
        row.manifestJSON = try encode(ManifestPayload(version: value.manifest.encodingVersion,
            mediaKind: value.manifest.mediaKind.rawValue,
            members: value.manifest.members.map {
                MemberPayload(contentHash: $0.contentHash.hexDigest,
                    byteCount: $0.byteCount, displayName: $0.displayName)
            }))
        return row
    }

    static func extraction(_ row: Schema.ExtractionRecord, units: [Schema.UnitRecord]) throws -> ExtractionRevisionSnapshot {
        try supported(row.recordVersion)
        let predecessors = try decode(PredecessorPayload.self, from: row.predecessorIDsJSON)
        try supported(predecessors.version)
        guard let origin = ExtractionOrigin(rawValue: row.originRaw),
              row.unitCount == units.count,
              row.createdAt.timeIntervalSince1970.isFinite else {
            throw SourceStoreError.corruptRecord
        }

        let mappedUnits = try units.sorted { $0.unitIndex < $1.unitIndex }.map {
            guard $0.extractionRevisionID == row.id else {
                throw SourceStoreError.conflictingLineage
            }

            return try unit($0)
        }

        let value = try ExtractionRevisionSnapshot(id: row.id, sourceRevisionID: row.sourceRevisionID,
            predecessorIDs: predecessors.ids, origin: origin, extractorVersion: row.extractorVersion,
            units: mappedUnits, createdAt: row.createdAt)
        guard row.textDigest == hash(value.canonicalIdentityData) else {
            throw SourceStoreError.contentHashMismatch
        }

        return value
    }

    static func extractionRecord(_ value: ExtractionRevisionSnapshot) throws -> Schema.ExtractionRecord {
        let row = Schema.ExtractionRecord()
        row.id = value.id
        row.recordVersion = value.encodingVersion
        row.createdAt = value.createdAt
        row.sourceRevisionID = value.sourceRevisionID
        row.predecessorIDsJSON = try encode(PredecessorPayload(version: 1, ids: value.predecessorIDs))
        row.originRaw = value.origin.rawValue
        row.extractorVersion = value.extractorVersion
        row.textDigest = hash(value.canonicalIdentityData)
        row.unitCount = value.units.count
        return row
    }

    static func unitRecord(_ value: SourceUnitSnapshot, extractionID: UUID) throws -> Schema.UnitRecord {
        let row = Schema.UnitRecord()
        row.id = value.id
        row.recordVersion = value.encodingVersion
        row.extractionRevisionID = extractionID
        row.unitIndex = value.unitIndex
        row.text = value.text
        row.canonicalTextVersion = value.canonicalTextVersion
        row.provenanceJSON = try encode(ProvenancePayload(version: value.provenance.encodingVersion,
            assetMemberIndex: value.provenance.assetMemberIndex, unitIndexInAsset: value.provenance.unitIndexInAsset,
            extractionPath: value.provenance.extractionPath.rawValue))
        return row
    }

    private static func unit(_ row: Schema.UnitRecord) throws -> SourceUnitSnapshot {
        try supported(row.recordVersion)
        let provenance = try decode(ProvenancePayload.self, from: row.provenanceJSON)
        try supported(provenance.version)
        guard let path = ExtractionPath(rawValue: provenance.extractionPath)
        else { throw SourceStoreError.corruptRecord }
        return try SourceUnitSnapshot(id: row.id, unitIndex: row.unitIndex, text: row.text,
            canonicalTextVersion: row.canonicalTextVersion,
            provenance: SourceUnitProvenance(assetMemberIndex: provenance.assetMemberIndex,
                unitIndexInAsset: provenance.unitIndexInAsset, extractionPath: path))
    }

    static func supported(_ version: Int) throws {
        guard version == 1 else {
            throw SourceStoreError.unsupportedRecordVersion(version)
        }
    }

    private static func encode<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }

    private static func decode<T: Decodable>(_ type: T.Type, from text: String) throws -> T {
        // DecodingError retains its coding path; no empty/default fallback.
        try JSONDecoder().decode(type, from: Data(text.utf8))
    }
}
