//
//  SourceAssetFiles.swift
//  PreceptorKit
//
//  Created by TaeVon Lewis on 10/8/26.
//

import Foundation
import PreceptorCore
import CryptoKit

struct SourceAssetFiles: Sendable {
    private let rootURL: URL
    private let copyOriginal: @Sendable (URL, URL) throws -> Void

    struct CleanupFailure: Error {
        let operationError: any Error
        let cleanupError: any Error
    }

    init(rootURL: URL) throws {
        try self.init(rootURL: rootURL, copyOriginal: { sourceURL, destinationURL in
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        })
    }

    init(rootURL: URL, copyOriginal: @escaping @Sendable (URL, URL) throws -> Void) throws {
        guard rootURL.isFileURL else {
            throw SourceStoreError.invalidLocalAssetPath
        }

        let normalizeRoot: URL = rootURL.standardizedFileURL.resolvingSymlinksInPath()
        let fileManager: FileManager = .default
        let directoryURLs: [URL] = [normalizeRoot, normalizeRoot.appending(path: ".staging", directoryHint: .isDirectory), normalizeRoot.appending(path: "published", directoryHint: .isDirectory)]

        for directoryURL in directoryURLs {
            do {
                let attributes = try fileManager.attributesOfItem(atPath: directoryURL.path)

                guard (attributes[.type] as? FileAttributeType) == .typeDirectory else {
                    throw SourceStoreError.invalidLocalAssetPath
                }
            } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
                try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            }
        }

        self.rootURL = normalizeRoot
        self.copyOriginal = copyOriginal
    }

    func publish(originalAt: URL, expectedMember: SourceAssetMember) throws -> String {
        try Task.checkCancellation()

        guard originalAt.isFileURL else {
            throw SourceStoreError.invalidLocalAssetPath
        }

        try requireManagedDirectories()
        try requireRegularFile(at: originalAt)

        let filename: String = "\(expectedMember.contentHash.hexDigest).asset"
        let relativePath: String = "published/\(filename)"
        let publishedURL: URL = rootURL.appending(path: relativePath, directoryHint: .notDirectory)

        if try itemExists(at: publishedURL) {
            try verifyBytes(at: publishedURL, expectedMember: expectedMember)
            return relativePath
        }

        let stagingPath: String = ".staging/\(UUID().uuidString).partial"
        let stagingURL: URL = rootURL.appending(path: stagingPath, directoryHint: .notDirectory)

        do {
            try copyOriginal(originalAt, stagingURL)
            try Task.checkCancellation()

            try verifyBytes(at: stagingURL, expectedMember: expectedMember)
            try Task.checkCancellation()
            try FileManager.default.moveItem(at: stagingURL, to: publishedURL)

            return relativePath
        } catch {
            let operationError = error

            do {
                try removeStagingFile(at: stagingURL)
            } catch {
                throw CleanupFailure(operationError: operationError, cleanupError: error)
            }

            throw operationError
        }
    }

    private func removeStagingFile(at url: URL) throws {
        try requireManagedDirectories()

        do {
            try FileManager.default.removeItem(at: url)
        } catch let error as CocoaError where error.code == .fileNoSuchFile {

        }
    }
    private func requireManagedDirectories() throws {
        let directoryURLs: [URL] = [rootURL, rootURL.appending(path: ".staging", directoryHint: .isDirectory), rootURL.appending(path: "published", directoryHint: .isDirectory)]

        for directoryURL in directoryURLs {
            let attributes = try FileManager.default.attributesOfItem(atPath: directoryURL.path)

            guard (attributes[.type] as? FileAttributeType) == .typeDirectory else {
                throw SourceStoreError.invalidLocalAssetPath
            }
        }
    }

    private func requireRegularFile(at url: URL) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)

        guard (attributes[.type] as? FileAttributeType) == .typeRegular else {
            throw SourceStoreError.invalidLocalAssetPath
        }
    }

    private func itemExists(at url: URL) throws -> Bool {
        do {
            _ = try FileManager.default.attributesOfItem(atPath: url.path)
            return true
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return false
        }
    }

    private func verifyBytes(at url: URL, expectedMember: SourceAssetMember) throws {
        try requireRegularFile(at: url)
        let handle: FileHandle = try FileHandle(forReadingFrom: url)

        let verification = Result<Void, any Error> {
            var byteCount: Int64 = 0
            var hasher = SHA256()

            while true {
                try Task.checkCancellation()

                guard let chunk = try handle.read(upToCount: 65_536), !chunk.isEmpty else {
                    break
                }

                let chunkCount: Int64 = Int64(chunk.count)
                let remainingCount: Int64 = expectedMember.byteCount - byteCount

                guard chunkCount <= remainingCount else {
                    throw SourceStoreError.localAssetContentMismatch
                }

                byteCount += chunkCount
                hasher.update(data: chunk)
            }

            guard byteCount == expectedMember.byteCount else {
                throw SourceStoreError.localAssetContentMismatch
            }

            let digits: [UInt8] = Array("0123456789abcdef".utf8)
            var hexadecimal: [UInt8] = []
            hexadecimal.reserveCapacity(64)

            for byte in hasher.finalize() {
                hexadecimal.append(digits[Int(byte >> 4)])
                hexadecimal.append(digits[Int(byte & 15)])
            }

            let actualDigest: String = String(decoding: hexadecimal, as: UTF8.self)

            guard actualDigest == expectedMember.contentHash.hexDigest else {
                throw SourceStoreError.localAssetContentMismatch
            }
        }

        let closing = Result<Void, any Error> {
            try handle.close()
        }

        try verification.get()
        try closing.get()
    }
}
