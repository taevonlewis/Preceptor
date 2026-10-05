import SwiftUI
import PreceptorCore
import PreceptorGenerate
import PreceptorStore

struct ContentView: View {
    let generator: any StudyGenerating
    let store: any GeneratedBatchStoring
    @State private var storedRecord: StoredGeneratedBatch? = nil
    @State private var recordID: UUID = UUID()
    @State private var errorMessage: String? = nil
    @State private var wasCancelled: Bool = false
    @State private var isLoading: Bool = false
    @State private var attempt: Int = 0

    private var proposals: [GeneratedProposal] {
        storedRecord?.generatedBatch.array ?? []
    }

    private static let sampleRequest = GenerationRequest(
        documentID: UUID(),
        sourceRevisionID: UUID(),
        extractionRevisionID: UUID(),
        sourceTextID: UUID(),
        text: "sample text"
    )

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Generating...")
                } else if let errorMessage {
                    ContentUnavailableView {
                        Label("Preview Failed", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(errorMessage)
                    } actions: {
                        Button("Try Again") {
                            attempt += 1
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else if wasCancelled {
                    ContentUnavailableView {
                        Label("Preview Cancelled", systemImage: "stop.circle")
                    } description: {
                        Text("The request stopped before it was finished.")
                    } actions: {
                        Button("Start Again") {
                            attempt += 1
                        }
                    }
                } else if proposals.isEmpty {
                    ContentUnavailableView(
                        "No Questions",
                        systemImage: "text.magnifyingglass",
                        description: Text("The source didn't produce any proposals.")
                    )
                } else {
                    List(proposals.indices, id: \.self) { index in
                        if let record = storedRecord {
                            ProposalRow(proposal: proposals[index], storedRecord: record)
                        }
                    }
                }
            }
            .navigationTitle("Stub preview")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Regenerate", systemImage: "arrow.clockwise") {
                        attempt += 1
                    }
                    .disabled(isLoading)
                }
            }
        }
        .task(id: attempt) {
            await generateAndStore()
        }

    }

    private func generateAndStore() async {
        isLoading = true
        errorMessage = nil
        wasCancelled = false
        storedRecord = nil

        defer {
            isLoading = false
        }

        do {
            let batch = try await generator.generate(Self.sampleRequest)
            _ = try await store.save(batch, recordID: recordID)
            let loadedRecord = try await store.load(recordID: recordID)

            if loadedRecord == nil {
                errorMessage = "The saved preview could not be loaded."
                return
            }

            try Task.checkCancellation()
            storedRecord = loadedRecord
        } catch is CancellationError {
            wasCancelled = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct ProposalRow: View {
    let proposal: GeneratedProposal
    let storedRecord: StoredGeneratedBatch

    var body: some View {
        HStack {
            VStack {
                Text(proposal.question)
                Text(proposal.quote)
            }

            Text("Saved in memory")

            Text(storedRecord.saveDate, format: .dateTime.year().month().day().hour().minute().second())
        }
    }
}

#Preview("Live clock — verify Regenerate") {
    ContentView(generator: DeterministicStudyGenerator(), store: InMemoryGeneratedBatchStore(now: { Date() }))
}

#Preview("Fixed date — timestamp display") {
    ContentView(generator: DeterministicStudyGenerator(), store: InMemoryGeneratedBatchStore(
            now: {
                Date(timeIntervalSince1970: 1_000)
            }
        )
    )
}
