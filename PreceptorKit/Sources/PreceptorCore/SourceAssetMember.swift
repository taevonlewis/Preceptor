//
//  SourceAssetMember.swift
//  PreceptorKit
//
//  Created by TaeVon Lewis on 10/5/26.
//

import Foundation

public struct SourceAssetMember: Sendable, Equatable {
    public let contentHash: SourceContentHash
    public let byteCount: Int64
    public let displayName: String

    public init(contentHash: SourceContentHash, byteCount: Int64, displayName: String) throws {
        guard byteCount >= 0 else {
            throw SourceIdentityError.invalidByteCount
        }

        self.contentHash = contentHash
        self.byteCount = byteCount
        self.displayName = displayName
    }
}
