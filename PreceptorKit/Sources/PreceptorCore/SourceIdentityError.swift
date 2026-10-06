//
//  SourceIdentityError.swift
//  PreceptorKit
//
//  Created by TaeVon Lewis on 10/5/26.
//

import Foundation

public enum SourceIdentityError: Error, Equatable {
    case invalidContentHash
    case invalidByteCount
    case emptyManifest
    case byteCountOverflow
    case invalidAssetMemberIndex
    case invalidUnitIndexInAsset
    case invalidUnitIndex
    case unsupportedCanonicalTextVersion(Int)
    case invalidExtractorVersion
    case invalidPredecessorIDs
    case duplicateUnitID
    case invalidUnitOrdering
}
