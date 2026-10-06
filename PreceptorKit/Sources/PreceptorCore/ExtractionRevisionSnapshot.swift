//
//  ExtractionRevisionSnapshot.swift
//  PreceptorKit
//
//  Created by TaeVon Lewis on 10/5/26.
//

import Foundation

public struct ExtractionRevisionSnapshot: Sendable, Equatable {
    public static let currentEncodingVersion = 1

    public let encodingVersion: Int
    public let id: UUID
    public let sourceRevisionID: UUID
    public let predecessorIDs: [UUID]
    public let origin: ExtractionOrigin
    public let extractorVersion: String
    public let units: [SourceUnitSnapshot]
    public let createdAt: Date

    public init(id: UUID, sourceRevisionID: UUID,
        predecessorIDs: [UUID], origin: ExtractionOrigin, extractorVersion: String,
        units: [SourceUnitSnapshot], createdAt: Date) throws {
        guard !extractorVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SourceIdentityError.invalidExtractorVersion
        }

        guard Set(predecessorIDs).count == predecessorIDs.count,
              !predecessorIDs.contains(id),
              origin == .automatic || !predecessorIDs.isEmpty else {
            throw SourceIdentityError.invalidPredecessorIDs
        }

        guard Set(units.map(\.id)).count == units.count else {
            throw SourceIdentityError.duplicateUnitID
        }

        guard units.enumerated().allSatisfy({ index, unit in
            unit.unitIndex == index
        }) else {
            throw SourceIdentityError.invalidUnitOrdering
        }

        encodingVersion = Self.currentEncodingVersion
        self.id = id
        self.sourceRevisionID = sourceRevisionID
        self.predecessorIDs = predecessorIDs.sorted {
            $0.uuidString.lowercased() < $1.uuidString.lowercased()
        }

        self.origin = origin
        self.extractorVersion = extractorVersion
        self.units = units
        self.createdAt = createdAt
    }

    public static func == (lhs: ExtractionRevisionSnapshot, rhs: ExtractionRevisionSnapshot) -> Bool {
        lhs.encodingVersion == rhs.encodingVersion
            && lhs.id == rhs.id
            && lhs.sourceRevisionID == rhs.sourceRevisionID
            && lhs.predecessorIDs == rhs.predecessorIDs
            && lhs.origin == rhs.origin
            && lhs.extractorVersion.utf8.elementsEqual(rhs.extractorVersion.utf8)
            && lhs.units == rhs.units
            && lhs.createdAt == rhs.createdAt
    }

    public var canonicalIdentityData: Data {
        var data = Data()
        Self.append("preceptor.extraction-revision", to: &data)
        Self.append(UInt64(encodingVersion), to: &data)
        Self.append(sourceRevisionID.uuidString.lowercased(), to: &data)
        Self.append(UInt64(predecessorIDs.count), to: &data)
        for predecessorID in predecessorIDs {
            Self.append(predecessorID.uuidString.lowercased(), to: &data)
        }
        Self.append(origin.rawValue, to: &data)
        Self.append(extractorVersion, to: &data)
        Self.append(UInt64(units.count), to: &data)
        for unit in units {
            Self.append(UInt64(unit.encodingVersion), to: &data)
            Self.append(UInt64(unit.unitIndex), to: &data)
            Self.append(UInt64(unit.canonicalTextVersion), to: &data)
            Self.append(unit.text, to: &data)
            Self.append(UInt64(unit.provenance.encodingVersion), to: &data)
            Self.append(UInt64(unit.provenance.assetMemberIndex), to: &data)
            Self.append(UInt64(unit.provenance.unitIndexInAsset), to: &data)
            Self.append(unit.provenance.extractionPath.rawValue, to: &data)
        }

        return data
    }

    private static func append(_ value: String, to data: inout Data) {
        Self.append(UInt64(value.utf8.count), to: &data)
        data.append(contentsOf: value.utf8)
    }

    private static func append(_ value: UInt64, to data: inout Data) {
        // Explicit shifts define a stable byte order independently of the host.
        for shift in stride(from: 56, through: 0, by: -8) {
            data.append(UInt8(truncatingIfNeeded: value >> shift))
        }
    }
}
