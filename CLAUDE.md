# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**JPBT** is an iOS/macOS/visionOS photo library browsing app written in Swift using SwiftUI and PhotoKit. It targets iOS 26.2, macOS 26.2, and xrOS 26.2.

## Build & Test Commands

This is an Xcode project — use Xcode or `xcodebuild`:

```bash
# Build
xcodebuild -project JPBT.xcodeproj -scheme JPBT -destination 'platform=iOS Simulator,name=iPhone 16' build

# Run tests
xcodebuild -project JPBT.xcodeproj -scheme JPBT -destination 'platform=iOS Simulator,name=iPhone 16' test

# Run a single test
xcodebuild -project JPBT.xcodeproj -scheme JPBTTests -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:JPBTTests/JPBTTests/testName test
```

For development, open `JPBT.xcodeproj` in Xcode.

## Architecture

**Entry point:** `JPBTApp.swift` — sets up the SwiftData model container with the `Item` model.

**Main flow:**
1. `ContentView.swift` — requests photo library authorization, fetches `PHAsset`s sorted by creation date, and drives navigation. Routes to `AssetImageView` or `AssetVideoView` based on asset media type.
2. `AssetImageView.swift` — loads images and Live Photos via `PHImageManager`. Uses `PHLivePhotoView` wrapped in platform-specific representables (`UIViewRepresentable` on iOS, `NSViewRepresentable` on macOS).
3. `AssetVideoView.swift` — loads video assets via `PHImageManager` and plays them using SwiftUI's `VideoPlayer` with `AVPlayer`.

**Key patterns:**
- All `PHImageManager` calls are bridged from callback-based API to async/await using `withCheckedContinuation`.
- `@MainActor` is the default actor isolation (`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` in build settings).
- `Item.swift` (SwiftData model) is wired up but currently unused in the UI.

**Multi-platform:** The codebase uses `#if canImport(UIKit)` / `#if canImport(AppKit)` guards to provide platform-specific view representables within shared files.

## S3 / AWS SDK

The project uses **`AWSS3`** from [aws-sdk-swift](https://github.com/awslabs/aws-sdk-swift). The package was added via Xcode's Package Dependencies UI (pinned in `JPBT.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`).

The macOS App Sandbox `ENABLE_OUTGOING_NETWORK_CONNECTIONS = YES` build setting is set in `project.pbxproj` to allow outbound HTTPS to S3.

**Local S3 emulator (LocalStack):**

```bash
docker run --rm -p 4566:4566 localstack/localstack
```

Configure the SDK via environment variables — no code changes needed to switch between real AWS and LocalStack:

```bash
export AWS_ENDPOINT_URL=http://localhost:4566
export AWS_ACCESS_KEY_ID=test
export AWS_SECRET_ACCESS_KEY=test
export AWS_REGION=us-east-1
```

Initialize the client normally in Swift; it picks up `AWS_ENDPOINT_URL` automatically:

```swift
import AWSS3
let s3 = try await S3Client(region: "us-east-1")
```

## CI

GitHub Actions workflow at `.github/workflows/ci.yml`:
- Installs and starts LocalStack before tests
- Passes LocalStack env vars to `xcodebuild test`
- Targets `platform=macOS` (avoids simulator provisioning on CI)
- **Note:** The workflow uses `macos-latest`; pin to a runner image with Xcode 26 once one is available.
