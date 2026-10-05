//
//  PreceptorGenerate.swift
//  PreceptorKit
//
//  Created by TaeVon Lewis on 10/4/26.
//

import PreceptorCore

public struct DeterministicStudyGenerator: StudyGenerating {
    public init() { }

    public func generate(_ request: GenerationRequest) async throws -> GeneratedBatch {
        try Task.checkCancellation()

        let cleanedText: String = request.text.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !cleanedText.isEmpty else {
            throw GenerationError.emptySource
        }

        let proposal = GeneratedProposal(
            question: "What does the source state?",
            quote: request.text)

        return GeneratedBatch(request: request, array: [proposal])
    }
}
