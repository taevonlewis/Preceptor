//
//  SourceContentHasher.swift
//  PreceptorKit
//
//  Created by TaeVon Lewis on 10/5/26.
//


import CryptoKit
import Foundation
import PreceptorCore

public enum SourceContentHasher {
    public static func hash(originalBytes: Data) throws -> SourceContentHash {
        let alphabet = Array("0123456789abcdef".utf8)
        let hexadecimal = SHA256.hash(data: originalBytes).flatMap { byte in
            [alphabet[Int(byte >> 4)], alphabet[Int(byte & 0x0f)]]
        }

        return try SourceContentHash(hexDigest: String(decoding: hexadecimal, as: UTF8.self))
    }

    public static func hash(manifest: SourceManifest) throws -> SourceContentHash {
        try hash(originalBytes: manifest.canonicalIdentityData)
    }
}
