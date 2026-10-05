//
//  StudyGenerating.swift
//  PreceptorKit
//
//  Created by TaeVon Lewis on 10/4/26.
//


public protocol StudyGenerating: Sendable {
    func generate(_ request: GenerationRequest) async throws -> GeneratedBatch
}
