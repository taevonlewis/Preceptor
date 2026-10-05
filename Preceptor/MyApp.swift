import SwiftUI
import PreceptorCore
import PreceptorExtract
import PreceptorGenerate
import PreceptorStore

@main struct MyApp: App {
    private let generator: any StudyGenerating = DeterministicStudyGenerator()
    private let store: any GeneratedBatchStoring = InMemoryGeneratedBatchStore()

    var body: some Scene {
        WindowGroup {
            ContentView(generator: generator, store: store)
        }
    }
}
