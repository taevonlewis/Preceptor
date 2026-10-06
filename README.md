# Preceptor

Preceptor is an iPhone and iPad study app in development, with an eventual
App Store release as its goal. It is intended to turn a learner's own PDFs,
lecture recordings, photos, screenshots, and text into recall practice linked
to evidence in the original material.

The aim is to make practice easier to prepare and check. A learner should be
able to inspect a question's supporting passage, correct extraction errors,
and return to the original page, image region, or audio interval.

## Planned study workflow

1. Import course or self-study material and review the extracted content.
2. Check proposed fill-in-the-blank and short-answer items against their sources.
3. Practice, reveal the answer, and record a self-assessment.
4. Reopen the evidence when needed and continue reviewing with saved progress.

The planned mobile app will process material and generate practice locally.
Original files will remain on the device by default; text and study records
may sync through private iCloud. These are product goals, not features provided
by the current scaffold.

## Current state

The repository currently contains a SwiftUI scaffold and a local Swift package.
The app persists the typed sample's immutable source, extraction, and text-unit
identities in a local SwiftData store, then runs generation, in-memory generated
batch storage, and display. Repeated launches reuse those source identities.
It does not yet import materials, use a language model, persist generated batches,
or provide the complete study workflow.

The package separates responsibilities into four modules:

- **PreceptorCore:** Foundation-only source values and pipeline contracts.
- **PreceptorExtract:** deterministic original-byte and ordered-manifest hashing.
- **PreceptorGenerate:** deterministic sample generation.
- **PreceptorStore:** immutable SwiftData source history and in-memory generated
  batch storage with an injectable clock.

Unit and integration tests cover generation, cancellation, storage conflicts,
repeat saves, source identity and durability, and the generate-save-load flow.
Xcode Cloud configuration is tracked separately from the scaffold. The release
path is TestFlight validation
followed by App Store submission; the app is not currently distributed.

## Development

The scaffold uses Xcode 27.1 (build 27A9269), Swift 6.4 for the package, and an
iOS/iPadOS 27.0 deployment target. Select Xcode 27.1 under **Xcode > Settings >
Locations > Command Line Tools** before running the commands below.

Open `Preceptor.xcodeproj`, select the **Preceptor** scheme, and choose an iPhone
or iPad Simulator to run the sample. Simulator builds do not require signing.
For a physical device, choose your own development team and a unique bundle
identifier in the app target's **Signing & Capabilities** settings.

Verify the toolchain and run all package tests from the repository root:

```sh
xcodebuild -version
xcrun swift --version
xcrun swift test --package-path PreceptorKit --explicit-target-dependency-import-check error
```

For tests in Xcode, open `PreceptorKit/Package.swift` and use the shared
**PreceptorKit** scheme. Its test plan selects all four test targets.

Run a clean Simulator build:

```sh
xcodebuild -project Preceptor.xcodeproj -scheme Preceptor \
  -configuration Debug -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/PreceptorDerivedData \
  CODE_SIGNING_ALLOWED=NO clean build
```

## Licensing

This repository is publicly available for portfolio review and inspection.
It is not offered under an open-source license.

Unless otherwise stated, no permission is granted to reuse, modify, or
redistribute the source code. Rights provided by applicable law and
GitHub's terms of service are unaffected.

The distributed app is governed by its applicable end-user license
agreement.
