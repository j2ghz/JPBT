# JPBT S3 Glacier Backup — Implementation Plan

## Overview

Add the ability to back up iCloud photos to an AWS S3 Glacier Deep Archive bucket.
Photos are content-addressed by their xxHash digest so the same file is never uploaded
twice. Before uploading, files are compressed and encrypted client-side. Photo metadata
is stored as S3 user-defined metadata on the same object, which is readable via HEAD
requests without triggering a Glacier restore.

The core logic lives in a UI-agnostic module so it can be reused by a future CLI tool
that operates on arbitrary file paths.

---

## Architecture

```
┌─────────────────────────────────────────────────┐
│  JPBT App (SwiftUI + TCA)                       │
│  ┌───────────────┐  ┌────────────────────────┐  │
│  │ BackupFeature  │  │ PhotosDataProvider     │  │
│  │ (Reducer+View) │  │ (PHAsset → FileData)   │  │
│  └───────┬───────┘  └──────────┬─────────────┘  │
│          │                     │                 │
│          ▼                     ▼                 │
│  ┌─────────────────────────────────────────────┐ │
│  │           BackupCore (reusable)             │ │
│  │  ┌──────────┐ ┌───────────┐ ┌───────────┐  │ │
│  │  │ Hashing  │ │Compression│ │ Encryption│  │ │
│  │  └──────────┘ └───────────┘ └───────────┘  │ │
│  │  ┌───────────┐ ┌──────────────────────────┐ │ │
│  │  │ S3Client  │ │ BackupCoordinator        │ │ │
│  │  └───────────┘ └──────────────────────────┘ │ │
│  └─────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────┐
│  Future CLI                                      │
│  ┌──────────────────┐                            │
│  │ FileDataProvider  │                            │
│  │ (path → FileData) │                            │
│  └────────┬─────────┘                            │
│           ▼                                      │
│    BackupCore (same module)                      │
└─────────────────────────────────────────────────┘
```

### Module Boundaries

- **BackupCore** — Pure Swift. No `Photos`, no `AppKit`, no `SwiftUI`. Depends only
  on Foundation, CryptoKit, AWSS3, and an xxHash library. This is what the CLI will
  also link against.
- **PhotosDataProvider** — Bridges `PHAsset` into the `FileData` type that
  BackupCore consumes. Lives in the app target.
- **BackupFeature** — TCA reducer + SwiftUI views for the backup UI. Lives in the
  app target.

---

## Key Design Decisions

### Single S3 Object per Backup

Each backed-up file is a single S3 object. Photo metadata is stored as S3 user-defined
metadata (limited to 2KB, which is sufficient for our fields). This works because:

- S3 HEAD requests work on Glacier objects without triggering a restore.
- S3 stores ~8KB of metadata overhead at Standard rate for each Glacier object anyway.
- No extra sidecar objects needed — simpler layout, fewer API calls.

Limitation: `ListObjectsV2` does not return user metadata — only key, size,
LastModified, and ETag. To read metadata, a HEAD request per object is needed. For a
personal photo library (tens of thousands of objects), this is acceptable. We cache the
index locally to avoid repeated full scans.

### Storage Class

Default: **S3 Glacier Deep Archive** (~$1/TB/month). User can override to Glacier
Flexible Retrieval or another class in settings. Deep Archive has a 180-day minimum
storage duration and 12-48 hour retrieval time — acceptable for a photo archive.

### Content Addressing & iCloud Identifiers

- The S3 object key is the xxHash64 hex digest of the **original unencrypted file bytes**.
- iCloud edits are non-destructive — we always hash the original (unedited) version
  using `PHImageRequestOptions.version = .original`.
- The `localIdentifier` and `PHCloudIdentifier` are stored in object metadata so we
  can correlate backups to iCloud assets.
- If a user edits a photo, the original hash doesn't change, so no re-upload is needed.
- The user can optionally choose to also back up the edited (`.current`) version,
  which gets its own hash.

### Multi-Resource Assets (Live Photos, etc.)

When a PHAsset has multiple resources (e.g., Live Photo = still + video), all resources
are bundled into a **tar archive** before hashing/compression/encryption. This keeps
them as a single logical backup unit with one hash. The tar preserves original filenames
and resource type metadata for correct reassembly on restore.

### Compression

All files are compressed before encryption using zstd (via Apple's built-in Compression
framework with `COMPRESSION_ZSTD`). Already-compressed formats (HEIC, JPEG, H.265)
won't shrink much, but the overhead is negligible. RAW files and adjustment data will
benefit.

### Encryption

- AES-256-GCM via CryptoKit (authenticated encryption).
- Blob format: `nonce (12 bytes) || ciphertext || tag (16 bytes)`.
- **Easy mode**: 256-bit key generated on first use, stored in macOS Keychain.
- **Advanced mode**: user provides a custom key or passphrase (derived via HKDF).
- CLI: passphrase via argument or environment variable, derived with HKDF.
- Key rotation not in v1 scope, but the format is forwards-compatible (a future
  version can prepend a key-id byte).

### Incremental Index

S3 has no date-filtered listing API. Our approach for v1:

1. On first run, do a full `ListObjectsV2` paginated scan, collecting all object keys
   (hashes). Store this set locally (e.g., in a SQLite database or flat file).
2. On subsequent runs, re-list only if needed (manual refresh or periodic). Since keys
   are content hashes with no temporal ordering, `StartAfter` doesn't help for
   incremental sync — but the full scan of just keys is fast for sub-100K objects.
3. After each successful upload, immediately add the hash to the local cache.
4. Future optimization: use S3 Event Notifications via EventBridge to push new
   object events to a queue, eliminating the need for polling.

---

## Data Model

### FileData (BackupCore input)

```swift
/// Platform-agnostic representation of a file to back up.
struct FileData: Sendable {
  let data: Data                    // raw file bytes (or tar for multi-resource)
  let originalFilename: String      // e.g. "IMG_1234.HEIC"
  let uniformTypeIdentifier: String // e.g. "public.heic"
  let metadata: BackupMetadata
}
```

### BackupMetadata (stored as S3 user metadata)

Kept lean to fit within S3's 2KB user metadata limit. All fields are optional strings
for S3 compatibility.

```swift
struct BackupMetadata: Codable, Sendable {
  let creationDate: Date?
  let pixelWidth: Int?
  let pixelHeight: Int?
  let latitude: Double?
  let longitude: Double?
  let mediaType: String             // "image", "video"
  let originalFilename: String
  let iCloudLocalID: String?        // PHAsset.localIdentifier
  let iCloudCloudID: String?        // PHCloudIdentifier
  let isFavorite: Bool?
  let cameraMake: String?
  let cameraModel: String?
  let durationSeconds: Double?
  let isMultiResource: Bool         // true if tar bundle
  let compressedSize: Int           // size after compression
  let originalSize: Int             // size before compression
}
```

### S3 Object Layout

```
s3://bucket/
  <xxhash64_hex>                    # compressed + encrypted file bytes
                                    # storage class: DEEP_ARCHIVE
                                    # user metadata: BackupMetadata fields
```

User metadata keys are prefixed `x-amz-meta-` by the SDK. Example:
```
x-amz-meta-creation-date: 2024-03-15T10:30:00Z
x-amz-meta-pixel-width: 4032
x-amz-meta-pixel-height: 3024
x-amz-meta-filename: IMG_1234.HEIC
x-amz-meta-media-type: image
x-amz-meta-is-favorite: true
x-amz-meta-camera: Apple/iPhone 15 Pro
x-amz-meta-icloud-local-id: ABC123/L0/001
x-amz-meta-is-multi-resource: false
```

---

## Components

### 1. HashingService

**File:** `BackupCore/HashingService.swift`

- Computes xxHash64 of a `Data` blob.
- Returns the hash as a zero-padded lowercase hex string (16 chars).
- Dependency: `xxHash-Swift` SPM package (pure Swift).
- Registered as a `@DependencyClient` for testability.

### 2. CompressionService

**File:** `BackupCore/CompressionService.swift`

- Compresses data using Apple's Compression framework with `COMPRESSION_ZSTD`.
- Decompresses for restore.
- Registered as a `@DependencyClient`.

### 3. EncryptionService

**File:** `BackupCore/EncryptionService.swift`

- AES-256-GCM via CryptoKit.
- Blob format: `nonce (12B) || ciphertext || tag (16B)`.
- Accepts a `SymmetricKey` — key source is the caller's responsibility.
- Registered as a `@DependencyClient`.

### 4. KeyManagementService

**File:** `BackupCore/KeyManagementService.swift` (protocol)
**File:** `JPBT/KeychainKeyManager.swift` (app implementation)

- Protocol defines: `loadKey() -> SymmetricKey?`, `generateAndStoreKey() -> SymmetricKey`,
  `importKey(from passphrase: String) -> SymmetricKey`.
- App implementation stores/retrieves from macOS Keychain.
- CLI implementation derives from passphrase via HKDF.

### 5. TarService

**File:** `BackupCore/TarService.swift`

- Creates a tar archive from multiple named data blobs (for multi-resource assets).
- Extracts a tar archive back to named blobs (for restore).
- Minimal tar implementation — just enough for our use case (no filesystem
  permissions, no symlinks).

### 6. S3BackupClient

**File:** `BackupCore/S3BackupClient.swift`

- Wraps `AWSS3` operations.
- Registered as a `@DependencyClient`.

```swift
@DependencyClient
struct S3BackupClient: Sendable {
  /// List all backed-up hashes (paginated ListObjectsV2, returns keys).
  var listBackedUpHashes: @Sendable () async throws -> Set<String>

  /// Check if a specific hash exists (HeadObject).
  var exists: @Sendable (_ hash: String) async throws -> Bool

  /// Read metadata for a hash (HeadObject, parse user metadata).
  var readMetadata: @Sendable (_ hash: String) async throws -> BackupMetadata

  /// Upload encrypted data with metadata. Uses multipart for files > 5GB.
  var upload: @Sendable (_ hash: String, _ data: Data, _ metadata: BackupMetadata) async throws -> Void

  /// Initiate a Glacier restore request.
  var requestRestore: @Sendable (_ hash: String, _ tier: RestoreTier) async throws -> Void

  /// Download restored data (only works after restore completes).
  var download: @Sendable (_ hash: String) async throws -> Data
}
```

**Configuration:**
- Bucket name, region, and storage class from settings.
- AWS credentials: default credential chain (`~/.aws/credentials`, env vars, IAM).
- Multipart upload threshold: 100MB (configurable).

### 7. BackupCoordinator

**File:** `BackupCore/BackupCoordinator.swift`

Pipeline for a single file:
```
FileData
  → hash(data)
  → exists(hash)?
    → YES: skip
    → NO:  compress(data) → encrypt(compressed) → upload(hash, encrypted, metadata)
```

Batch operations:
- Accepts `[FileData]`, processes concurrently via `TaskGroup`.
- Configurable concurrency limit (default: 4).
- Reports progress via `AsyncStream<BackupProgress>`.

```swift
struct BackupProgress: Sendable {
  let total: Int
  let completed: Int
  let skipped: Int
  let failed: [(String, any Error)]
  let currentFile: String?
  let bytesUploaded: Int64
  let bytesTotal: Int64
}
```

### 8. LocalBackupIndex

**File:** `BackupCore/LocalBackupIndex.swift`

- Caches the set of backed-up hashes locally to avoid repeated S3 listing.
- Stores hash → basic metadata (filename, date) for quick UI display.
- Backed by a simple file (JSON or SQLite — decide during implementation).
- Syncs with S3 on demand (full re-list) or after each upload (append).

### 9. PhotosDataProvider (App-specific)

**File:** `JPBT/PhotosDataProvider.swift`

- Converts a `PHAsset` into a `FileData`.
- Always requests the **original** version (`PHImageRequestOptions.version = .original`).
- For multi-resource assets (Live Photos), fetches all resources via
  `PHAssetResourceManager` and bundles them into a tar via `TarService`.
- Extracts metadata from PHAsset properties + EXIF via `CGImageSource`.
- Maps `localIdentifier` → `PHCloudIdentifier` for cross-device correlation.
- Registered as a `@DependencyClient`.

### 10. BackupFeature (TCA)

**File:** `JPBT/BackupFeature.swift`

State:
```swift
@ObservableState
struct BackupFeature.State: Equatable {
  var localIndex: Set<String> = []        // cached backed-up hashes
  var isLoadingIndex: Bool = false
  var selectedAssetIDs: Set<String> = []  // user selection for backup
  var backupProgress: BackupProgress?
  var isBackingUp: Bool = false
  var error: String?
  var storageClass: StorageClass = .deepArchive
}
```

Actions:
- `onAppear` — load local index (and optionally sync with S3).
- `syncIndex` — full re-list from S3.
- `backupSelected` — start backing up selected photos.
- `progressUpdated(BackupProgress)` — update progress UI.
- `backupCompleted` — refresh index, clean up state.
- `deleteOldVersion(hash:)` — remove a superseded backup after edit.

UI:
- Each photo in the sidebar shows a backup status badge (backed up / not / in progress).
- "Back Up Selected" toolbar button.
- Progress bar during backup.
- Settings sheet for S3 config, storage class, and key management.

---

## Implementation Order

### Phase 1: Core Infrastructure
- [ ] 1. Add `xxHash-Swift` SPM dependency.
- [ ] 2. Create `BackupCore/` group in the Xcode project.
- [ ] 3. Implement `HashingService` + unit tests.
- [ ] 4. Implement `CompressionService` + unit tests.
- [ ] 5. Implement `EncryptionService` + unit tests.
- [ ] 6. Implement `TarService` + unit tests.
- [ ] 7. Implement `S3BackupClient` (list, exists, upload, readMetadata) with
       multipart upload support.
- [ ] 8. Implement `LocalBackupIndex` + unit tests.
- [ ] 9. Implement `BackupCoordinator` + unit tests (mock dependencies).

### Phase 2: App Integration
- [ ] 10. Implement `KeychainKeyManager`.
- [ ] 11. Implement `PhotosDataProvider` (PHAsset → FileData, including tar bundling).
- [ ] 12. Implement `BackupFeature` TCA reducer.
- [ ] 13. Build `BackupView` — selection, progress, status badges.
- [ ] 14. Wire into `ContentView` — add backup controls to the toolbar/sidebar.
- [ ] 15. Build settings UI — S3 config, storage class picker, key management.

### Phase 3: Polish & CLI Prep
- [ ] 16. Error handling & retry logic in `BackupCoordinator`.
- [ ] 17. Bandwidth/concurrency controls.
- [ ] 18. Verify `BackupCore` compiles without app-target imports.
- [ ] 19. Scaffold CLI target (Swift Argument Parser) with `FileDataProvider`.

---

## Dependencies

| Package | Purpose | Status |
|---------|---------|--------|
| aws-sdk-swift (AWSS3) | S3 operations | Already added |
| swift-dependencies | DI for testability | Already added |
| swift-composable-architecture | TCA state management | Already added |
| xxHash-Swift | xxHash64 hashing | **To add** |

CryptoKit, Compression, and ImageIO are system frameworks — no packages needed.

---

## Open Questions

1. **Edited versions**: Should we offer a "back up edited version too" toggle? The
   original is always backed up; the edited version would be a separate object.
2. **Restore flow**: Not in v1 scope, but encryption format and tar structure are
   designed to support it. Plan restore UI/CLI in a future phase.
3. **Deletion sync**: If a user deletes a photo from iCloud, should the backup be
   kept or optionally cleaned up?
4. **Bandwidth limits**: Should we add upload speed throttling for metered
   connections?
