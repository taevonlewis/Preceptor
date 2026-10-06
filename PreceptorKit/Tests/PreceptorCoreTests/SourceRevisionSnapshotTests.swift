//
//  SourceRevisionSnapshotTests.swift
//  PreceptorKit
//
//  Created by TaeVon Lewis on 10/5/26.
//


import Foundation
import PreceptorCore
import Testing

@Suite("Immutable source and extraction snapshots")
struct SourceRevisionSnapshotTests {
    @Test("Source snapshots retain intentional document identity")
    func sourceSnapshotsRetainDocumentIdentity() throws {
        let hash = try SourceContentHash(hexDigest: String(repeating: "0", count: 64))
        let member = try SourceAssetMember(contentHash: hash, byteCount: 0, displayName: "original.pdf")
        let manifest = try SourceManifest(mediaKind: .pdf, members: [member])
        let first = SourceRevisionSnapshot(id: Self.id(1), documentID: Self.id(2), contentHash: hash,
            manifest: manifest, createdAt: Self.createdAt)
        let second = SourceRevisionSnapshot(id: Self.id(3), documentID: Self.id(4), contentHash: hash,
            manifest: manifest, createdAt: Self.createdAt)

        #expect(first.encodingVersion == 1)
        #expect(first.id == Self.id(1))
        #expect(first.documentID == Self.id(2))
        #expect(first.contentHash == hash)
        #expect(first.manifest == manifest)
        #expect(first.createdAt == Self.createdAt)
        #expect(first.documentID != second.documentID)
        #expect(first.contentHash == second.contentHash)
        #expect(first != second)
    }

    @Test("Provenance rejects negative original-member indices", arguments: [-1, Int.min])
    func invalidMemberIndex(index: Int) {
        #expect(throws: SourceIdentityError.invalidAssetMemberIndex) {
            _ = try SourceUnitProvenance(assetMemberIndex: index, unitIndexInAsset: 0, extractionPath: .pdfText)
        }
    }

    @Test("Provenance rejects negative original-unit indices", arguments: [-1, Int.min])
    func invalidOriginalUnitIndex(index: Int) {
        #expect(throws: SourceIdentityError.invalidUnitIndexInAsset) {
            _ = try SourceUnitProvenance(assetMemberIndex: 0, unitIndexInAsset: index, extractionPath: .pdfText)
        }
    }

    @Test("Units reject negative snapshot positions", arguments: [-1, Int.min])
    func invalidSnapshotUnitIndex(index: Int) throws {
        let provenance = try Self.provenance()
        #expect(throws: SourceIdentityError.invalidUnitIndex) {
            _ = try SourceUnitSnapshot(id: Self.id(1), unitIndex: index, text: "text", provenance: provenance)
        }
    }

    @Test("Units reject unsupported canonical-text policy versions", arguments: [-1, 0, 2])
    func unsupportedCanonicalTextVersion(version: Int) throws {
        let provenance = try Self.provenance()
        #expect(throws: SourceIdentityError.unsupportedCanonicalTextVersion(version)) {
            _ = try SourceUnitSnapshot(id: Self.id(1), unitIndex: 0, text: "text",
                canonicalTextVersion: version, provenance: provenance)
        }
    }

    @Test("Canonical text preserves exact Unicode and line endings")
    func canonicalTextIsLossless() throws {
        let original = " \r\ne\u{301} 👩🏽‍🔬\t\n"
        let unit = try Self.unit(text: original)
        let composed = try Self.unit(text: " \r\né 👩🏽‍🔬\t\n")

        #expect(unit.text.utf8.elementsEqual(original.utf8))
        #expect(unit.encodingVersion == 1)
        #expect(unit.canonicalTextVersion == 1)
        #expect(unit.provenance.encodingVersion == 1)
        // String equality accepts canonical equivalence; record equality must
        // still distinguish the actual representation retained for coordinates.
        #expect(unit.text == composed.text)
        #expect(unit != composed)
        let decomposedRevision = try Self.revision(units: [unit])
        let composedRevision = try Self.revision(units: [composed])
        #expect(decomposedRevision.canonicalIdentityData != composedRevision.canonicalIdentityData)
    }

    @Test("Empty units and empty complete extractions remain representable")
    func emptyResultsAreValid() throws {
        let unit = try Self.unit(text: "")
        let revision = try Self.revision(units: [])

        #expect(unit.text.isEmpty)
        #expect(revision.units.isEmpty)
        #expect(revision.predecessorIDs.isEmpty)
        #expect(revision.origin == .automatic)
    }

    @Test("Missing extractor policy is rejected", arguments: ["", " ", "\t\r\n", "\u{2003}"])
    func invalidExtractorVersion(version: String) {
        #expect(throws: SourceIdentityError.invalidExtractorVersion) {
            _ = try Self.revision(extractorVersion: version)
        }
    }

    @Test("Nonempty extractor policy is retained without trimming")
    func extractorVersionIsPreserved() throws {
        let revision = try Self.revision(extractorVersion: " engine-v1 ")
        #expect(revision.extractorVersion == " engine-v1 ")
        let trimmed = try Self.revision(extractorVersion: "engine-v1")
        #expect(revision.canonicalIdentityData != trimmed.canonicalIdentityData)
    }

    @Test("Extractor policy equality agrees with exact identity bytes")
    func extractorPolicyUnicodeIsExact() throws {
        let composed = try Self.revision(extractorVersion: "café")
        let decomposed = try Self.revision(extractorVersion: "cafe\u{301}")

        #expect(composed.extractorVersion == decomposed.extractorVersion)
        #expect(composed != decomposed)
        #expect(composed.canonicalIdentityData != decomposed.canonicalIdentityData)
    }

    @Test("Duplicate and self-referencing predecessors are rejected")
    func invalidPredecessorIDs() {
        #expect(throws: SourceIdentityError.invalidPredecessorIDs) {
            _ = try Self.revision(predecessorIDs: [Self.id(8), Self.id(8)])
        }
        #expect(throws: SourceIdentityError.invalidPredecessorIDs) {
            _ = try Self.revision(predecessorIDs: [Self.id(1)])
        }
    }

    @Test("Correction and resolution name their predecessors",
        arguments: [ExtractionOrigin.userCorrection, .resolution])
    func correctionRequiresPredecessors(origin: ExtractionOrigin) {
        #expect(throws: SourceIdentityError.invalidPredecessorIDs) {
            _ = try Self.revision(origin: origin)
        }
    }

    @Test("Predecessor edge order has no effect on snapshot or identity")
    func predecessorOrderIsCanonical() throws {
        let first = try Self.revision(predecessorIDs: [Self.id(9), Self.id(8)], origin: .resolution)
        let second = try Self.revision(predecessorIDs: [Self.id(8), Self.id(9)], origin: .resolution)

        #expect(first.predecessorIDs == [Self.id(8), Self.id(9)])
        #expect(first == second)
        #expect(first.canonicalIdentityData == second.canonicalIdentityData)
    }

    @Test("Complete snapshots reject duplicate unit IDs")
    func duplicateUnitIDs() throws {
        let first = try Self.unit()
        let second = try Self.unit(unitIndex: 1)
        #expect(throws: SourceIdentityError.duplicateUnitID) {
            _ = try Self.revision(units: [first, second])
        }
    }

    @Test("Complete snapshots require contiguous ordered units")
    func completeUnitOrdering() throws {
        let first = try Self.unit(id: Self.id(5), unitIndex: 0)
        let gap = try Self.unit(id: Self.id(6), unitIndex: 2)
        let next = try Self.unit(id: Self.id(6), unitIndex: 1)
        #expect(throws: SourceIdentityError.invalidUnitOrdering) {
            _ = try Self.revision(units: [first, gap])
        }
        #expect(throws: SourceIdentityError.invalidUnitOrdering) {
            _ = try Self.revision(units: [next, first])
        }
        let valid = try Self.revision(units: [first, next])
        #expect(valid.units.map(\.unitIndex) == [0, 1])
    }

    @Test("Correction leaves previous text and recognition provenance intact")
    func correctionsPreserveHistory() throws {
        let originalUnit = try Self.unit(text: "recognised text", path: .imageOCR)
        let original = try Self.revision(units: [originalUnit])
        var replacementUnits = original.units
        replacementUnits[0] = try Self.unit(id: Self.id(6), text: "corrected text", path: .imageOCR)
        let correction = try Self.revision(id: Self.id(2), predecessorIDs: [original.id], origin: .userCorrection,
            units: replacementUnits)

        #expect(original.units[0].text == "recognised text")
        #expect(correction.units[0].text == "corrected text")
        #expect(correction.units[0].provenance.extractionPath == .imageOCR)
        #expect(original.units[0].provenance.extractionPath == .imageOCR)
        #expect(correction.predecessorIDs == [original.id])
        #expect(original.canonicalIdentityData != correction.canonicalIdentityData)
    }

    @Test("Generated IDs and timestamps do not change extraction content identity")
    func contentIdentityExcludesRecordMetadata() throws {
        let first = try Self.revision(units: [Self.unit(id: Self.id(5))])
        let second = try Self.revision(id: Self.id(2),
            units: [Self.unit(id: Self.id(6))], createdAt: Date(timeIntervalSince1970: 123))

        #expect(first != second)
        #expect(first.canonicalIdentityData == second.canonicalIdentityData)
    }

    @Test("Text, provenance and extractor policy change content identity")
    func contentIdentityIncludesTextAndPolicy() throws {
        let baseline = try Self.revision(units: [Self.unit(text: "original")])
        let variants = try [
            Self.revision(units: [Self.unit(text: "changed")]),
            Self.revision(units: [Self.unit(text: "original", path: .pdfOCR)]),
            Self.revision(units: [Self.unit(text: "original", memberIndex: 1)]),
            Self.revision(units: [Self.unit(text: "original", originalIndex: 1)]),
            Self.revision(extractorVersion: "engine-v2", units: [Self.unit(text: "original")]),
            Self.revision(sourceRevisionID: Self.id(4), units: [Self.unit(text: "original")]),
            Self.revision(predecessorIDs: [Self.id(8)], units: [Self.unit(text: "original")])
        ]
        for variant in variants {
            #expect(baseline.canonicalIdentityData != variant.canonicalIdentityData)
        }
        let automatic = try Self.revision(predecessorIDs: [Self.id(8)])
        let correction = try Self.revision(predecessorIDs: [Self.id(8)], origin: .userCorrection)
        #expect(automatic.canonicalIdentityData != correction.canonicalIdentityData)
    }

    @Test("Ordered text and length prefixes distinguish otherwise ambiguous joins")
    func identityEncodingPreservesUnitBoundaries() throws {
        let first = try Self.revision(units: [
            Self.unit(id: Self.id(5), unitIndex: 0, text: "ab"),
            Self.unit(id: Self.id(6), unitIndex: 1, text: "c")
        ])
        let second = try Self.revision(units: [
            Self.unit(id: Self.id(5), unitIndex: 0, text: "a"),
            Self.unit(id: Self.id(6), unitIndex: 1, text: "bc")
        ])
        let reordered = try Self.revision(units: [
            Self.unit(id: Self.id(6), unitIndex: 0, text: "c"),
            Self.unit(id: Self.id(5), unitIndex: 1, text: "ab")
        ])

        #expect(first.canonicalIdentityData != second.canonicalIdentityData)
        #expect(first.canonicalIdentityData != reordered.canonicalIdentityData)
    }

    @Test("Version-1 extraction identity has a frozen byte fixture")
    func canonicalEncodingFixture() throws {
        let revision = try Self.revision(units: [Self.unit()])
        // This independently encoded fixture fixes the domain tag, byte order,
        // length prefixes, policy versions and all version-1 field boundaries.
        let expectedHex = [
            "000000000000001d707265636570746f722e65787472616374696f6e2d726576",
            "6973696f6e0000000000000001000000000000002430303030303030302d3030",
            "30302d303030302d303030302d30303030303030303030303300000000000000",
            "0000000000000000096175746f6d617469630000000000000009656e67696e65",
            "2d76310000000000000001000000000000000100000000000000000000000000",
            "00000100000000000000086f726967696e616c00000000000000010000000000",
            "0000000000000000000000000000000000000770646654657874"
        ].joined()
        let actualHex = revision.canonicalIdentityData.map {
            String(format: "%02x", $0)
        }.joined()

        #expect(revision.encodingVersion == 1)
        #expect(revision.canonicalIdentityData.count == 218)
        #expect(actualHex == expectedHex)
    }

    private static let createdAt = Date(timeIntervalSince1970: 0)

    private static func id(_ lastByte: UInt8) -> UUID {
        UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, lastByte))
    }

    private static func provenance(path: ExtractionPath = .pdfText, memberIndex: Int = 0,
        originalIndex: Int = 0) throws -> SourceUnitProvenance {
        try SourceUnitProvenance(assetMemberIndex: memberIndex, unitIndexInAsset: originalIndex, extractionPath: path)
    }

    private static func unit(id: UUID = Self.id(5), unitIndex: Int = 0, text: String = "original",
        path: ExtractionPath = .pdfText, memberIndex: Int = 0, originalIndex: Int = 0) throws -> SourceUnitSnapshot {
        try SourceUnitSnapshot(id: id, unitIndex: unitIndex, text: text,
            provenance: Self.provenance(path: path, memberIndex: memberIndex, originalIndex: originalIndex))
    }

    private static func revision(id: UUID = Self.id(1),
        sourceRevisionID: UUID = Self.id(3), predecessorIDs: [UUID] = [],
        origin: ExtractionOrigin = .automatic, extractorVersion: String = "engine-v1",
        units: [SourceUnitSnapshot] = [], createdAt: Date = Self.createdAt) throws -> ExtractionRevisionSnapshot {
        try ExtractionRevisionSnapshot(id: id, sourceRevisionID: sourceRevisionID, predecessorIDs: predecessorIDs,
            origin: origin, extractorVersion: extractorVersion, units: units, createdAt: createdAt)
    }
}
