//
//  SourceUnitSnapshot.swift
//  PreceptorKit
//
//  Created by TaeVon Lewis on 10/5/26.
//


import Foundation

public struct SourceUnitSnapshot: Sendable, Equatable {
    public static let currentEncodingVersion = 1
    public static let currentCanonicalTextVersion = 1

    public let encodingVersion: Int
    public let id: UUID
    public let unitIndex: Int
    public let text: String
    public let canonicalTextVersion: Int
    public let provenance: SourceUnitProvenance

    public init(id: UUID, unitIndex: Int, text: String,
        canonicalTextVersion: Int = 1, provenance: SourceUnitProvenance) throws {
        guard unitIndex >= 0 else {
            throw SourceIdentityError.invalidUnitIndex
        }

        guard canonicalTextVersion == Self.currentCanonicalTextVersion else {
            throw SourceIdentityError.unsupportedCanonicalTextVersion(canonicalTextVersion)
        }

        encodingVersion = Self.currentEncodingVersion
        self.id = id
        self.unitIndex = unitIndex
        self.text = text
        self.canonicalTextVersion = canonicalTextVersion
        self.provenance = provenance
    }

    public static func == (lhs: SourceUnitSnapshot, rhs: SourceUnitSnapshot) -> Bool {
        lhs.encodingVersion == rhs.encodingVersion
            && lhs.id == rhs.id
            && lhs.unitIndex == rhs.unitIndex
            && lhs.text.utf8.elementsEqual(rhs.text.utf8)
            && lhs.canonicalTextVersion == rhs.canonicalTextVersion
            && lhs.provenance == rhs.provenance
    }
}
