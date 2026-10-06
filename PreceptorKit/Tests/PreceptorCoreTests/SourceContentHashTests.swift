//
//  SourceContentHashTests.swift
//  PreceptorKit
//
//  Created by TaeVon Lewis on 10/5/26.
//

import Testing
import PreceptorCore

@Suite("SourceContentHashTests")
struct SourceContentHashTests {
    private static let input =
        "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"

    @Test("Valid input remains unchanged")
    func validInputRemainsUnchanged() throws {
        let hash = try SourceContentHash(hexDigest: Self.input)

        #expect(hash.hexDigest == Self.input)
    }

    @Test("Equal values work as keys")
    func equalValuesWorkAsKeys() throws {
        let first = try SourceContentHash(hexDigest: Self.input)
        let second = try SourceContentHash(hexDigest: Self.input)

        #expect(first == second)

        let hashes = Set([first, second])
        #expect(hashes.count == 1)

        let dictionary = [first: "saved value"]
        #expect(dictionary[second] == "saved value")
    }

    @Test("Different digests remain distinct")
    func differentDigestsRemainDistinct() throws {
        let differentInput = String(Self.input.dropLast()) + "e"
        let first = try SourceContentHash(hexDigest: Self.input)
        let second = try SourceContentHash(hexDigest: differentInput)

        #expect(first != second)

        let hashes = Set([first, second])
        #expect(hashes.count == 2)
    }

    @Test("All-zero digest is syntactically valid")
    func allZeroDigestIsValid() throws {
        let input = String(repeating: "0", count: 64)
        let hash = try SourceContentHash(hexDigest: input)

        #expect(hash.hexDigest == input)
    }

    @Test("Invalid forms throw invalidContentHash", arguments: [
        "",
        String(repeating: "0", count: 63),
        String(repeating: "0", count: 65),
        String(repeating: "A", count: 64),
        String(repeating: "0", count: 63) + "g",
        " " + SourceContentHashTests.input,
        SourceContentHashTests.input + "\n",
        "sha256:" + SourceContentHashTests.input,
        String(repeating: "０", count: 64)
    ])
    func invalidFormsThrowExactError(input: String) {
        #expect(throws: SourceIdentityError.invalidContentHash) {
            _ = try SourceContentHash(hexDigest: input)
        }
    }
}
