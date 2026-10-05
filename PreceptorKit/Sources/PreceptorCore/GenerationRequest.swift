import Foundation

public struct GenerationRequest: Sendable, Equatable {
    public let documentID: UUID
    public let sourceRevisionID: UUID
    public let extractionRevisionID: UUID
    public let sourceTextID: UUID
    public let text: String

    public init(documentID: UUID, sourceRevisionID: UUID, extractionRevisionID: UUID, sourceTextID: UUID, text: String) {
        self.documentID = documentID
        self.sourceRevisionID = sourceRevisionID
        self.extractionRevisionID = extractionRevisionID
        self.sourceTextID = sourceTextID
        self.text = text
    }
}
