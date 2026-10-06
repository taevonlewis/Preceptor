//
//  SourceManifest.swift
//  PreceptorKit
//
//  Created by TaeVon Lewis on 10/5/26.
//


import Foundation

public struct SourceManifest: Sendable, Equatable {
    public static let currentEncodingVersion = 1

    public let encodingVersion: Int
    public let mediaKind: SourceMediaKind
    public let members: [SourceAssetMember]
    public let byteCount: Int64

    public init(mediaKind: SourceMediaKind, members: [SourceAssetMember]) throws {
        guard !members.isEmpty else {
            throw SourceIdentityError.emptyManifest
        }

        var total: Int64 = 0
        for member in members {
            let addition = total.addingReportingOverflow(member.byteCount)
            guard !addition.overflow else {
                throw SourceIdentityError.byteCountOverflow
            }
            total = addition.partialValue
        }

        self.encodingVersion = Self.currentEncodingVersion
        self.mediaKind = mediaKind
        self.members = members
        self.byteCount = total
    }

    public var canonicalIdentityData: Data {
        var data = Data("preceptor.source-manifest\0".utf8)
        Self.append(UInt64(encodingVersion), to: &data)

        let mediaBytes = mediaKind.rawValue.utf8
        Self.append(UInt64(mediaBytes.count), to: &data)
        data.append(contentsOf: mediaBytes)
        Self.append(UInt64(members.count), to: &data)

        for member in members {
            Self.append(UInt64(member.byteCount), to: &data)
            let digest = Array(member.contentHash.hexDigest.utf8)
            // SourceContentHash guarantees 64 lowercase ASCII hexadecimal
            // digits, so every pair safely decodes to exactly one byte.
            for index in stride(from: 0, to: digest.count, by: 2) {
                let high = Self.hexValue(digest[index])
                let low = Self.hexValue(digest[index + 1])
                data.append((high << 4) | low)
            }
        }

        return data
    }

    private static func append(_ value: UInt64, to data: inout Data) {
        var encoded = value.bigEndian
        withUnsafeBytes(of: &encoded) { bytes in
            data.append(contentsOf: bytes)
        }
    }

    private static func hexValue(_ digit: UInt8) -> UInt8 {
        digit <= 57 ? digit - 48 : digit - 87
    }
}
