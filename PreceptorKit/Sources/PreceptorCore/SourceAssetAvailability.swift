//
//  SourceAssetAvailability.swift
//  PreceptorKit
//
//  Created by TaeVon Lewis on 10/5/26.
//

import Foundation

public enum SourceAssetAvailability: Sendable, Equatable {
    case unregistered
    case missing
    case contentMismatch
    case available(URL)
}
