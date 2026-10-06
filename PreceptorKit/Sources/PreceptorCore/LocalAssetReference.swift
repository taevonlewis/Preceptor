//
//  LocalAssetReference.swift
//  PreceptorKit
//
//  Created by TaeVon Lewis on 10/5/26.
//

import Foundation

public struct LocalAssetReference: Sendable, Equatable {
    public let sourceRevisionID: UUID
    public let memberIndex: Int
    public let relativePath: String

    public init(sourceRevisionID: UUID, memberIndex: Int, relativePath: String) {
        self.sourceRevisionID = sourceRevisionID
        self.memberIndex = memberIndex
        self.relativePath = relativePath
    }
}
