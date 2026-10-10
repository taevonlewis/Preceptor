//
//  SourceAssetFilesTests.swift
//  PreceptorKit
//
//  Created by TaeVon Lewis on 10/8/26.
//

import Foundation
import PreceptorCore
import PreceptorExtract
import Testing
@testable import PreceptorStore

@Suite("Owned original publication")
struct SourceAssetFilesTests {
    @Test("Published bytes survive removal of the selected original") func ownsPublishedBytes() throws {
        let fixture = try SourceAssetFilesFixture()

        defer {
            fixture.remove()
        }

        let files = try SourceAssetFiles(rootURL: fixture.assetsURL)
        let selectedURL = try fixture.externalFile(named: "source-a")
        let member = try fixture.member()
        let expectedBytes = try fixture.bytes(named: "source-a")
        let relativePath = try files.publish(originalAt: selectedURL, expectedMember: member)

        #expect(relativePath == "published/\(member.contentHash.hexDigest).asset")

        try FileManager.default.removeItem(at: selectedURL)

        let ownedBytes = try Data(contentsOf: fixture.ownedURL(for: relativePath))

        #expect(ownedBytes == expectedBytes)
        #expect(Int64(ownedBytes.count) == 47)
        #expect(try SourceContentHasher.hash(originalBytes: ownedBytes) == member.contentHash)
        #expect(try fixture.entries(in: ".staging").isEmpty)
    }

    @Test("Renamed identical bytes reuse the published original") func reusesIdenticalBytes() throws {
        let fixture = try SourceAssetFilesFixture()

        defer {
            fixture.remove()
        }

        let first = try SourceAssetFiles(rootURL: fixture.assetsURL)
        let firstURL = try fixture.externalFile(named: "source-a")
        let firstPath = try first.publish(originalAt: firstURL, expectedMember: fixture.member())

        let reopened = try SourceAssetFiles(rootURL: fixture.assetsURL)
        let renamedURL = try fixture.externalFile(named: "identical-renamed")
        let secondPath = try reopened.publish(originalAt: renamedURL, expectedMember: fixture.member(displayName: "renamed.txt"))

        #expect(secondPath == firstPath)
        #expect(try fixture.entries(in: "published").count == 1)
        #expect(try Data(contentsOf: fixture.ownedURL(for: secondPath)) == fixture.bytes(named: "source-a"))
        #expect(try fixture.entries(in: ".staging").isEmpty)
    }

    @Test("A copy that returns incomplete bytes cannot publish") func rejectsTruncatedCopy() throws {
        let fixture = try SourceAssetFilesFixture()

        defer {
            fixture.remove()
        }

        let selectedURL = try fixture.externalFile(named: "source-a")
        let member = try fixture.member()
        let truncatedBytes = try fixture.bytes(named: "truncated-source-a")
        try #require(truncatedBytes.count == 42)

        let files = try SourceAssetFiles(rootURL: fixture.assetsURL, copyOriginal: { _, destinationURL in
            try truncatedBytes.write(to: destinationURL)
        })

        #expect(throws: SourceStoreError.localAssetContentMismatch) {
            try files.publish(originalAt: selectedURL, expectedMember: member)
        }

        #expect(try fixture.entries(in: "published").isEmpty)
        #expect(try fixture.entries(in: ".staging").isEmpty)
    }

    @Test("Equal-length changed bytes fail digest verification") func rejectsChangedBytes() throws {
        let fixture = try SourceAssetFilesFixture()

        defer {
            fixture.remove()
        }

        let files = try SourceAssetFiles(rootURL: fixture.assetsURL)
        let selectedURL = try fixture.externalFile(named: "source-a-revised")
        let member = try fixture.member()
        try #require(Data(contentsOf: selectedURL).count == 47)

        #expect(throws: SourceStoreError.localAssetContentMismatch) {
            try files.publish(originalAt: selectedURL, expectedMember: member)
        }

        #expect(try fixture.entries(in: "published").isEmpty)
        #expect(try fixture.entries(in: ".staging").isEmpty)
    }

    @Test("Bytes beyond the declared count cannot publish") func rejectsExcessBytes() throws {
        let fixture = try SourceAssetFilesFixture()

        defer {
            fixture.remove()
        }

        let files = try SourceAssetFiles(rootURL: fixture.assetsURL)
        let selectedURL = try fixture.externalFile(named: "source-a")
        let originalMember = try fixture.member()

        let wrongCountMember = try SourceAssetMember(contentHash: originalMember.contentHash, byteCount: 46,
                                                     displayName: originalMember.displayName)

        #expect(throws: SourceStoreError.localAssetContentMismatch) {
            try files.publish(originalAt: selectedURL, expectedMember: wrongCountMember)
        }

        #expect(try fixture.entries(in: "published").isEmpty)
        #expect(try fixture.entries(in: ".staging").isEmpty)
    }

    @Test("A mismatched existing original is rejected without replacement") func preservesMismatchedExistingFile() throws {
        let fixture = try SourceAssetFilesFixture()

        defer {
            fixture.remove()
        }

        let files = try SourceAssetFiles(rootURL: fixture.assetsURL)
        let selectedURL = try fixture.externalFile(named: "source-a")
        let member = try fixture.member()
        let relativePath = "published/\(member.contentHash.hexDigest).asset"
        let existingURL = fixture.ownedURL(for: relativePath)
        let wrongBytes = try fixture.bytes(named: "source-a-revised")

        try wrongBytes.write(to: existingURL)

        #expect(throws: SourceStoreError.localAssetContentMismatch) {
            try files.publish(originalAt: selectedURL, expectedMember: member)
        }

        #expect(try Data(contentsOf: existingURL) == wrongBytes)
        #expect(try fixture.entries(in: ".staging").isEmpty)
    }

    @Test("Copy failures clear staging and preserve previously published bytes", arguments: [false, true])
    func preservesOriginalAfterStorageFailure(_ writesPartialCopy: Bool) throws {
        let fixture = try SourceAssetFilesFixture()

        defer {
            fixture.remove()
        }

        let normal = try SourceAssetFiles(rootURL: fixture.assetsURL)
        let previousURL = try fixture.seedPreviousOriginal(using: normal)
        let previousBytes = try Data(contentsOf: previousURL)
        let selectedURL = try fixture.externalFile(named: "source-a")
        let member = try fixture.member()
        let truncatedBytes = try fixture.bytes(named: "truncated-source-a")
        try #require(truncatedBytes.count == 42)

        let failing = try SourceAssetFiles(rootURL: fixture.assetsURL, copyOriginal: { _, destinationURL in
            if writesPartialCopy {
                try truncatedBytes.write(to: destinationURL)
            }

            throw CocoaError(.fileWriteOutOfSpace)
        })

        let error = try #require(throws: CocoaError.self) {
            try failing.publish(originalAt: selectedURL, expectedMember: member)
        }

        #expect(error.code == .fileWriteOutOfSpace)
        #expect(try fixture.entries(in: ".staging").isEmpty)
        #expect(try fixture.entries(in: "published").count == 1)
        #expect(try Data(contentsOf: previousURL) == previousBytes)
    }

    @Test("Cancellation clears staging and preserves previously published bytes", arguments: [false, true])
    func cancellationBeforePublication(_ copiesOriginal: Bool) async throws {
        let fixture = try SourceAssetFilesFixture()

        defer {
            fixture.remove()
        }

        let normal = try SourceAssetFiles(rootURL: fixture.assetsURL)
        let previousURL = try fixture.seedPreviousOriginal(using: normal)
        let previousBytes = try Data(contentsOf: previousURL)
        let selectedURL = try fixture.externalFile(named: "source-a")
        let member = try fixture.member()

        let cancelling = try SourceAssetFiles(rootURL: fixture.assetsURL, copyOriginal: { sourceURL, destinationURL in
            if copiesOriginal {
                try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
            }

            withUnsafeCurrentTask {
                $0?.cancel()
            }
        })

        let task = Task {
            try cancelling.publish(originalAt: selectedURL, expectedMember: member)
        }

        await #expect(throws: CancellationError.self) {
            try await task.value
        }

        #expect(try fixture.entries(in: ".staging").isEmpty)
        #expect(try fixture.entries(in: "published").count == 1)
        #expect(try Data(contentsOf: previousURL) == previousBytes)
    }

    @Test("Cleanup retains both failures and refuses a replaced staging directory")
    func preservesCleanupFailure() throws {
        let fixture = try SourceAssetFilesFixture()

        defer {
            fixture.remove()
        }

        let selectedURL = try fixture.externalFile(named: "source-a")
        let member = try fixture.member()
        let truncatedBytes = try fixture.bytes(named: "truncated-source-a")
        let outsideBytes = Data("External file must survive".utf8)
        let stagingDirectoryURL = fixture.assetsURL.appending(path: ".staging", directoryHint: .isDirectory)
        let retainedDirectoryURL = fixture.assetsURL.appending(path: "retained-staging", directoryHint: .isDirectory)

        let failing = try SourceAssetFiles(rootURL: fixture.assetsURL, copyOriginal: { _, destinationURL in
            try truncatedBytes.write(to: destinationURL)
            try FileManager.default.moveItem(at: stagingDirectoryURL, to: retainedDirectoryURL)

            let outsideURL = fixture.externalURL.appending(path: destinationURL.lastPathComponent, directoryHint: .notDirectory)

            try outsideBytes.write(to: outsideURL)
            try FileManager.default.createSymbolicLink(at: stagingDirectoryURL, withDestinationURL: fixture.externalURL)

            throw CocoaError(.fileWriteOutOfSpace)
        })

        let failure = try #require(throws: SourceAssetFiles.CleanupFailure.self) {
            try failing.publish(originalAt: selectedURL, expectedMember: member)
        }

        let operationError = try #require(failure.operationError as? CocoaError)

        #expect(operationError.code == .fileWriteOutOfSpace)
        #expect((failure.cleanupError as? SourceStoreError) == .invalidLocalAssetPath)
        #expect(try fixture.entries(in: "published").isEmpty)

        let retainedEntries = try FileManager.default.contentsOfDirectory(at: retainedDirectoryURL, includingPropertiesForKeys: nil)
        let retainedURL = try #require(retainedEntries.first)

        #expect(retainedEntries.count == 1)
        #expect(try Data(contentsOf: retainedURL) == truncatedBytes)

        let outsideURL = fixture.externalURL.appending(path: retainedURL.lastPathComponent, directoryHint: .notDirectory)

        #expect(try Data(contentsOf: outsideURL) == outsideBytes)
    }

    @Test("Directories and symbolic links cannot be selected",
          arguments: [false, true]) func rejectsNonRegularOriginals(_ useSymbolicLink: Bool) throws {
        let fixture = try SourceAssetFilesFixture()

        defer {
            fixture.remove()
        }

        let files = try SourceAssetFiles(rootURL: fixture.assetsURL)
        let selectedURL: URL

        if useSymbolicLink {
            let targetURL = try fixture.externalFile(named: "source-a")
            selectedURL = fixture.externalURL.appending(path: "selected-link", directoryHint: .notDirectory)

            try FileManager.default.createSymbolicLink(at: selectedURL, withDestinationURL: targetURL)
        } else {
            selectedURL = fixture.externalURL
        }

        #expect(throws: SourceStoreError.invalidLocalAssetPath) {
            try files.publish(originalAt: selectedURL, expectedMember: fixture.member())
        }

        #expect(try fixture.entries(in: "published").isEmpty)
    }

    @Test("Non-file URLs are rejected") func rejectsNonFileURL() throws {
        let fixture = try SourceAssetFilesFixture()

        defer {
            fixture.remove()
        }

        let files = try SourceAssetFiles(rootURL: fixture.assetsURL)
        let selectedURL = try #require(URL(string: "https://example.invalid/original"))

        #expect(throws: SourceStoreError.invalidLocalAssetPath) {
            try files.publish(originalAt: selectedURL, expectedMember: fixture.member())
        }

        #expect(try fixture.entries(in: "published").isEmpty)
    }

    @Test("Replaced managed directories cannot redirect writes",
          arguments: [".staging", "published"]) func rejectsManagedDirectoryLinks(_ directoryName: String) throws {
        let fixture = try SourceAssetFilesFixture()

        defer {
            fixture.remove()
        }

        let files = try SourceAssetFiles(rootURL: fixture.assetsURL)
        let selectedURL = try fixture.externalFile(named: "source-a")
        let managedURL = fixture.assetsURL.appending(path: directoryName, directoryHint: .notDirectory)

        try FileManager.default.removeItem(at: managedURL)
        try FileManager.default.createSymbolicLink(at: managedURL, withDestinationURL: fixture.externalURL)

        #expect(throws: SourceStoreError.invalidLocalAssetPath) {
            try files.publish(originalAt: selectedURL, expectedMember: fixture.member())
        }

        let outsideEntries = try FileManager.default.contentsOfDirectory(at: fixture.externalURL, includingPropertiesForKeys: nil)

        let normalizedEntries = outsideEntries.map { $0.standardizedFileURL.resolvingSymlinksInPath() }

        #expect(normalizedEntries == [selectedURL.standardizedFileURL.resolvingSymlinksInPath()])
    }

    @Test("Verification handles empty files and chunk boundaries", arguments: [0, 65_536, 65_537])
    func verifiesChunkBoundaries(_ count: Int) throws {
        let fixture = try SourceAssetFilesFixture()

        defer {
            fixture.remove()
        }

        let files = try SourceAssetFiles(rootURL: fixture.assetsURL)
        let originalBytes = Data(repeating: 0x41, count: count)
        let selectedURL = fixture.externalURL.appending(path: "boundary.bin", directoryHint: .notDirectory)

        try originalBytes.write(to: selectedURL)

        let member = try SourceAssetMember(contentHash: SourceContentHasher.hash(originalBytes: originalBytes),
                                           byteCount: Int64(count), displayName: "boundary.bin")

        let relativePath = try files.publish(originalAt: selectedURL, expectedMember: member)

        #expect(try Data(contentsOf: fixture.ownedURL(for: relativePath)) == originalBytes)
        #expect(try fixture.entries(in: ".staging").isEmpty)
    }
}

private struct SourceAssetFilesFixture {
    let directoryURL: URL
    let externalURL: URL
    let assetsURL: URL

    init() throws {
        directoryURL = FileManager.default.temporaryDirectory.appending(path: "SourceAssetFilesTests-\(UUID().uuidString)",
                                                                        directoryHint: .isDirectory).standardizedFileURL.resolvingSymlinksInPath()
        externalURL = directoryURL.appending(path: "External", directoryHint: .isDirectory)
        assetsURL = directoryURL.appending(path: "Assets", directoryHint: .isDirectory)

        try FileManager.default.createDirectory(at: externalURL, withIntermediateDirectories: true)
    }

    func resource(named name: String) throws -> URL {
        try #require(Bundle.module.url(forResource: name, withExtension: "txt", subdirectory: "OriginalAssets"))
    }

    func bytes(named name: String) throws -> Data {
        try Data(contentsOf: resource(named: name))
    }

    func externalFile(named name: String) throws -> URL {
        let destination = externalURL.appending(path: "\(name).txt", directoryHint: .notDirectory)
        try FileManager.default.copyItem(at: resource(named: name), to: destination)

        return destination
    }

    func member(displayName: String = "source-a.txt") throws -> SourceAssetMember {
        try SourceAssetMember(contentHash: SourceContentHash(hexDigest:"dfcf32da152f5d4a328ff56853fd3023d3bc87c71f251cb52284ce0358175d79"),
                              byteCount: 47, displayName: displayName)
    }

    func ownedURL(for relativePath: String) -> URL {
        assetsURL.appending(path: relativePath, directoryHint: .notDirectory)
    }

    func entries(in directoryName: String) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: assetsURL.appending(path: directoryName, directoryHint: .isDirectory), includingPropertiesForKeys: nil)
    }

    func seedPreviousOriginal(using files: SourceAssetFiles) throws -> URL {
        let originalBytes = Data("Previously published original".utf8)
        let sourceURL = externalURL.appending(path: "previous.txt", directoryHint: .notDirectory)

        try originalBytes.write(to: sourceURL)

        let previousMember = try SourceAssetMember(contentHash: SourceContentHasher.hash(originalBytes: originalBytes), byteCount: Int64(originalBytes.count), displayName: "previous.txt")
        let relativePath = try files.publish(originalAt: sourceURL,
                                             expectedMember: previousMember)

        return ownedURL(for: relativePath)
    }

    func remove() {
        do {
            try FileManager.default.removeItem(at: directoryURL)
        } catch {
            Issue.record(error, "Temporary fixture cleanup failed")
        }
    }
}
