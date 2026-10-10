//
//  SourceImportAttempt.swift
//  PreceptorKit
//
//  Created by TaeVon Lewis on 10/9/26.
//

import Foundation
import PreceptorCore

public struct SourceImportAttempt: Sendable, Equatable {
    public enum State: String, Sendable {
        case started
        case completed
        case failed
        case cancelled
        case interrupted
    }

    public let encodingVersion: Int
    public let id: UUID
    public let documentID: UUID
    public let contentHash: SourceContentHash
    public let createdAt: Date
    public let state: State
    public let finishedAt: Date?
    public let sourceRevisionID: UUID?
}
