import SwiftUI
import PreceptorCore
import PreceptorGenerate
import PreceptorStore

@main struct MyApp: App {
    private let generator: any StudyGenerating = DeterministicStudyGenerator()
    private let store: any GeneratedBatchStoring = InMemoryGeneratedBatchStore()
    @State private var sourceStorage = SourceStorageBootstrap()

    var body: some Scene {
        WindowGroup {
            Group {
                switch sourceStorage.state {
                case .loading:
                    ProgressView("Loading Source...")
                case .ready(let loader):
                    ContentView(generator: generator,
                        store: store,
                        loadRequest: { try await loader.load() })
                case .failed(let message):
                    ContentUnavailableView {
                        Label("Source Storage Unavailable",
                            systemImage: "externaldrive.badge.exclamationmark")
                    } description: {
                        Text(message)
                    } actions: {
                        Button("Try Again") {
                            sourceStorage.start()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
            .task {
                sourceStorage.start()
            }
        }
    }
}
