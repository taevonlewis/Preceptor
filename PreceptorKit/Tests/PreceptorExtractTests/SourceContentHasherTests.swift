import Foundation
import PreceptorCore
import PreceptorExtract
import Testing

@Suite("Original source hashing")
struct SourceContentHasherTests {
    @Test("SHA-256 matches fixed empty, text, and binary fixtures", arguments: [
        (Data(),
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"),
        (Data("abc".utf8),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"),
        (Data([0, 255, 16, 128]),
            "a33bb2aed757bc839807d7a9deab0688c3cf06d36e53cb428f2e539c8dc76c5b")
    ])
    func hashesKnownBytes(bytes: Data, expected: String) throws {
        let result = try SourceContentHasher.hash(originalBytes: bytes)

        #expect(result.hexDigest == expected)
    }

    @Test("Original bytes are not normalized as text")
    func originalBytesAreNotNormalized() throws {
        let composed = try SourceContentHasher.hash(originalBytes: Data("é".utf8))
        let decomposed = try SourceContentHasher.hash(originalBytes: Data("e\u{301}".utf8))

        #expect(composed != decomposed)
    }

    @Test("The manifest identity matches an independent golden digest")
    func manifestMatchesGoldenDigest() throws {
        let members = try Self.fixtureMembers()
        let manifest = try SourceManifest(mediaKind: .pdf, members: members)
        let identity = try SourceContentHasher.hash(manifest: manifest)

        #expect(identity.hexDigest ==
            "cd337f8752f153cac9f64d76bd2ce8f114705869b09100d1ea967f91d00cce72")
    }

    @Test("Member order and exact duplicates participate in identity")
    func orderAndDuplicatesAffectIdentity() throws {
        let members = try Self.fixtureMembers()
        let original = try SourceManifest(mediaKind: .pdf, members: members)
        let reordered = try SourceManifest(mediaKind: .pdf, members: members.reversed())
        let repeated = try SourceManifest(mediaKind: .pdf, members: members + [members[0]])
        let originalHash = try SourceContentHasher.hash(manifest: original)
        let reorderedHash = try SourceContentHasher.hash(manifest: reordered)
        let repeatedHash = try SourceContentHasher.hash(manifest: repeated)

        #expect(originalHash != reorderedHash)
        #expect(originalHash != repeatedHash)
        #expect(repeated.members.count == 3)
        #expect(repeated.byteCount == 10)
    }

    @Test("Renaming display metadata preserves content identity")
    func renamingDoesNotAffectIdentity() throws {
        let members = try Self.fixtureMembers()
        let renamed = try members.map { member in
            try SourceAssetMember(contentHash: member.contentHash,
                byteCount: member.byteCount, displayName: "renamed-" + member.displayName)
        }
        let original = try SourceManifest(mediaKind: .pdf, members: members)
        let updated = try SourceManifest(mediaKind: .pdf, members: renamed)
        let originalHash = try SourceContentHasher.hash(manifest: original)
        let updatedHash = try SourceContentHasher.hash(manifest: updated)

        #expect(original != updated)
        #expect(originalHash == updatedHash)
    }

    @Test("Media interpretation and byte counts participate in identity")
    func interpretationAndByteCountAffectIdentity() throws {
        let members = try Self.fixtureMembers()
        let original = try SourceManifest(mediaKind: .pdf, members: members)
        let image = try SourceManifest(mediaKind: .image, members: members)
        let changedCount = try SourceAssetMember(contentHash: members[0].contentHash,
            byteCount: 4, displayName: members[0].displayName)
        let changed = try SourceManifest(mediaKind: .pdf, members: [changedCount, members[1]])
        let originalHash = try SourceContentHasher.hash(manifest: original)
        let imageHash = try SourceContentHasher.hash(manifest: image)
        let changedHash = try SourceContentHasher.hash(manifest: changed)

        #expect(originalHash != imageHash)
        #expect(originalHash != changedHash)
    }

    private static func fixtureMembers() throws -> [SourceAssetMember] {
        let firstBytes = Data("abc".utf8)
        let secondBytes = Data([0, 255, 16, 128])
        return try [
            SourceAssetMember(contentHash: SourceContentHasher.hash(originalBytes: firstBytes),
                byteCount: Int64(firstBytes.count), displayName: "first.pdf"),
            SourceAssetMember(contentHash: SourceContentHasher.hash(originalBytes: secondBytes),
                byteCount: Int64(secondBytes.count), displayName: "second.pdf")
        ]
    }
}
