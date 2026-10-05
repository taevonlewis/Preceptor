import Foundation
import Testing
@testable import PreceptorCore
import PreceptorGenerate

@Suite("PreceptorCore Tests")
struct PreceptorCoreTests {

    let generator = DeterministicStudyGenerator()

    func makeRequestTemplate(text: String) -> GenerationRequest {
        return GenerationRequest(
            documentID: UUID(),
            sourceRevisionID: UUID(),
            extractionRevisionID: UUID(),
            sourceTextID: UUID(),
            text: text
        )
    }

    @Test("Valid request produces expected question, exact quote, and preserved requrest") func testSuccessfulProposalGeneration() async throws {
        let textInput = "test txt"
        let request = makeRequestTemplate(text: textInput)

        let batch = try await generator.generate(request)

        #expect(batch.request == request)
        #expect(batch.array.count == 1)

        let proposal = try #require(batch.array.first)
        #expect(proposal.question == "What does the source state?")
        #expect(batch.array[0].quote == textInput)
    }

    @Test("Repeated invocations with matching inputs yield completely identical results") func testDeterministicEquality() async throws {
        let identicalTexts = "test text identical"
        let request1 = makeRequestTemplate(text: identicalTexts)
        let request2 = request1

        let batch1 = try await generator.generate(request1)
        let batch2 = try await generator.generate(request2)

        #expect(batch1 == batch2)
    }

    @Test("Empty or whitespace-only inputs trigger emptySource generation errors", arguments: [
        "",
        " ",
        "   ",
        "\n",
        " \t \n "
    ]) func testInvalidInputsThrowEmptySource(invalidText: String) async throws {
        let badRequest = makeRequestTemplate(text: invalidText)

        await #expect(throws: GenerationError.emptySource) {
            try await generator.generate(badRequest)
        }
    }

    @Test("Task cancellation proprogated as CancellationError") func testTaskCancellationProgrogationError() async throws {
        let request = makeRequestTemplate(text: "test string for cancellation")

        let isolatedTask = Task {
            withUnsafeCurrentTask { task in
                task?.cancel()
            }

            return try await generator.generate(request)
        }

        await #expect(throws: CancellationError.self) {
            try await isolatedTask.value
        }
    }
}
