//
//  GeneratedBatch.swift
//  PreceptorKit
//
//  Created by TaeVon Lewis on 10/4/26.
//


public struct GeneratedBatch: Sendable, Equatable {
    public let request: GenerationRequest
    public let array: [GeneratedProposal]

    public init(request: GenerationRequest, array: [GeneratedProposal]) {
        self.request = request
        self.array = array
    }
}
