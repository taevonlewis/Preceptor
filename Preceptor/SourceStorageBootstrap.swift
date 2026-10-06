//
//  SourceStorageBootstrap.swift
//  PreceptorKit
//
//  Created by TaeVon Lewis on 10/5/26.
//


import Foundation
import Observation

@Observable @MainActor final class SourceStorageBootstrap {
    private(set) var state: State = .loading
    @ObservationIgnored private var task: Task<Void, Never>?

    func start() {
        guard task == nil else { return }
        if case .ready = state { return }
        state = .loading
        task = Task { [weak self] in
            do {
                let loader = try await SampleSourceRequestLoader.persistent()
                try Task.checkCancellation()
                self?.state = .ready(loader)
            } catch is CancellationError {
                // Cancellation is teardown, not a user-visible storage failure.
            } catch {
                self?.state = .failed(error.localizedDescription)
            }
            self?.task = nil
        }
    }

    deinit {
        task?.cancel()
    }

    enum State {
        case loading
        case ready(SampleSourceRequestLoader)
        case failed(String)
    }
}
