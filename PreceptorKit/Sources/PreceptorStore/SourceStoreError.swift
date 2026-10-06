//
//  SourceStoreError.swift
//  PreceptorKit
//
//  Created by TaeVon Lewis on 10/5/26.
//


import Foundation

public enum SourceStoreError: Error, Equatable {
    case conflictingRecordID
    case contentHashMismatch
    case missingSourceRevision
    case missingPredecessor
    case conflictingLineage
    case invalidProvenance
    case invalidLocalAssetPath
    case localAssetContentMismatch
    case corruptRecord
    case unsupportedRecordVersion(Int)
}
