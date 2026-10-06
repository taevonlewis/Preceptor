//
//  ExtractionPath.swift
//  PreceptorKit
//
//  Created by TaeVon Lewis on 10/5/26.
//

public enum ExtractionPath: String, Sendable, Equatable {
    case pdfText
    case pdfOCR
    case imageOCR
    case asr
    case typed
}
