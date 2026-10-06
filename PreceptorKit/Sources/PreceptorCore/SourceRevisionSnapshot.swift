//
//  SourceRevisionSnapshot.swift
//  PreceptorKit
//
//  Created by TaeVon Lewis on 10/5/26.
//


import Foundation

public struct SourceRevisionSnapshot: Sendable, Equatable {
    public static let currentEncodingVersion = 1

    public let encodingVersion: Int
    public let id: UUID
    public let documentID: UUID
    public let contentHash: SourceContentHash
    public let manifest: SourceManifest
    public let createdAt: Date

    public init(id: UUID, documentID: UUID, contentHash: SourceContentHash, manifest: SourceManifest, createdAt: Date) {
        encodingVersion = Self.currentEncodingVersion
        self.id = id
        self.documentID = documentID
        self.contentHash = contentHash
        self.manifest = manifest
        self.createdAt = createdAt
    }
}
