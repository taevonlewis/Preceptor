//
//  SourceUnitProvenance.swift
//  PreceptorKit
//
//  Created by TaeVon Lewis on 10/5/26.
//


public struct SourceUnitProvenance: Sendable, Equatable {
    public static let currentEncodingVersion = 1

    public let encodingVersion: Int
    public let assetMemberIndex: Int
    public let unitIndexInAsset: Int
    public let extractionPath: ExtractionPath

    public init(assetMemberIndex: Int, unitIndexInAsset: Int, extractionPath: ExtractionPath) throws {
        guard assetMemberIndex >= 0 else {
            throw SourceIdentityError.invalidAssetMemberIndex
        }

        guard unitIndexInAsset >= 0 else {
            throw SourceIdentityError.invalidUnitIndexInAsset
        }

        encodingVersion = Self.currentEncodingVersion
        self.assetMemberIndex = assetMemberIndex
        self.unitIndexInAsset = unitIndexInAsset
        self.extractionPath = extractionPath
    }
}
