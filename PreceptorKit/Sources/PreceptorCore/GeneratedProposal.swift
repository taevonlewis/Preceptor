//
//  GeneratedProposal.swift
//  PreceptorKit
//
//  Created by TaeVon Lewis on 10/4/26.
//


public struct GeneratedProposal: Sendable, Equatable {
    public let question: String
    public let quote: String

    public init(question: String, quote: String) {
        self.question = question
        self.quote = quote
    }
}
