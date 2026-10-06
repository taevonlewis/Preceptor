//
//  SourceManifestTests.swift
//  PreceptorKit
//
//  Created by TaeVon Lewis on 10/5/26.
//


import Foundation
import PreceptorCore
import Testing

@Suite("Source manifests")
struct SourceManifestTests {
    private static let abcDigest =
        "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
    private static let binaryDigest =
        "a33bb2aed757bc839807d7a9deab0688c3cf06d36e53cb428f2e539c8dc76c5b"

    @Test("Canonical encoding matches the fixed version-1 fixture")
    func canonicalEncodingMatchesFixture() throws {
        let first = try SourceAssetMember(contentHash: SourceContentHash(hexDigest: Self.abcDigest),
            byteCount: 3, displayName: "first.pdf")
        let second = try SourceAssetMember(contentHash: SourceContentHash(hexDigest: Self.binaryDigest),
            byteCount: 4, displayName: "second.pdf")
        let manifest = try SourceManifest(mediaKind: .pdf, members: [first, second])
        // Independently produced with Python struct.pack('>Q', ...) and hashlib.
        let expectedHex =
            "707265636570746f722e736f757263652d6d616e696665737400" +
            "0000000000000001" +
            "0000000000000003706466" +
            "0000000000000002" +
            "0000000000000003" + Self.abcDigest +
            "0000000000000004" + Self.binaryDigest
        let actualHex = manifest.canonicalIdentityData.map {
            String(format: "%02x", $0)
        }.joined()

        #expect(actualHex == expectedHex)
        #expect(manifest.canonicalIdentityData.count == 133)
        #expect(manifest.encodingVersion == 1)
        #expect(manifest.byteCount == 7)
        #expect(manifest.members == [first, second])
    }

    @Test("A negative asset byte count is rejected")
    func negativeByteCountIsRejected() throws {
        let hash = try SourceContentHash(hexDigest: Self.abcDigest)

        #expect(throws: SourceIdentityError.invalidByteCount) {
            _ = try SourceAssetMember(contentHash: hash, byteCount: -1, displayName: "source.pdf")
        }
    }

    @Test("An empty manifest is rejected")
    func emptyManifestIsRejected() {
        #expect(throws: SourceIdentityError.emptyManifest) {
            _ = try SourceManifest(mediaKind: .pdf, members: [])
        }
    }

    @Test("Total byte-count overflow is rejected")
    func totalByteCountOverflowIsRejected() throws {
        let hash = try SourceContentHash(hexDigest: Self.abcDigest)
        let maximum = try SourceAssetMember(contentHash: hash, byteCount: .max, displayName: "large.pdf")
        let extra = try SourceAssetMember(contentHash: hash, byteCount: 1, displayName: "extra.pdf")

        #expect(throws: SourceIdentityError.byteCountOverflow) {
            _ = try SourceManifest(mediaKind: .pdf, members: [maximum, extra])
        }
        let validMaximum = try SourceManifest(mediaKind: .pdf, members: [maximum])
        #expect(validMaximum.byteCount == Int64.max)
    }

    @Test("Zero-byte assets and empty display names are valid")
    func zeroByteAssetIsValid() throws {
        let hash = try SourceContentHash(hexDigest: "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        let member = try SourceAssetMember(contentHash: hash, byteCount: 0, displayName: "")
        let manifest = try SourceManifest(mediaKind: .typed, members: [member])

        #expect(manifest.byteCount == 0)
        #expect(manifest.members == [member])
    }
}
