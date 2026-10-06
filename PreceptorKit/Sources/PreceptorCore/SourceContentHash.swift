//
//  SourceContentHash.swift
//  PreceptorKit
//
//  Created by TaeVon Lewis on 10/5/26.
//

import Foundation

public struct SourceContentHash: Sendable, Hashable {
    public let hexDigest: String

    public init(hexDigest: String) throws {
        guard Self.isValidHex(hexDigest) else {
            throw SourceIdentityError.invalidContentHash
        }

        self.hexDigest = hexDigest
    }

    private static func isValidHex(_ hexDigest: String) -> Bool {
        let bytes = hexDigest.utf8

        guard bytes.count == 64 else {
            return false
        }

        return bytes.allSatisfy { byte in
            switch byte {
            case 48...57, 97...102:
                return true
            default:
                return false
            }
        }
    }
}
