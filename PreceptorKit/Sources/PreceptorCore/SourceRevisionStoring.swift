//
//  SourceRevisionStoring.swift
//  PreceptorKit
//
//  Created by TaeVon Lewis on 10/5/26.
//


import Foundation

public protocol SourceRevisionStoring: Sendable {
    func saveSource(_ revision: SourceRevisionSnapshot) async throws -> SourceRevisionSnapshot
    func sourceRevision(id: UUID) async throws -> SourceRevisionSnapshot?
    func saveExtraction(_ revision: ExtractionRevisionSnapshot) async throws -> ExtractionRevisionSnapshot
    func extractionRevision(id: UUID) async throws -> ExtractionRevisionSnapshot?
}
