# Known Limitations

Status: ACTIVE

## Product / Scope

- Complete WishItem workflow is not part of V1.
- Household realtime sharing and account system are deferred.
- OCR, AI recognition and automated purchase advice are deferred.
- External commerce order synchronization is deferred.
- Multi-currency historical conversion is not automatic in V1.

## Architecture

- iOS 17.0 has been validated as the minimum deployment target with Xcode 26.6 and the iOS 26.5 Simulator runtime.
- SwiftData schema version 1 and a migration boundary exist, but no cross-version migration can be exercised until a second schema version exists.
- Backup/export format and recovery UI are not yet implemented.
- Controlled Simulator tests cover two 4032 × 3024 image imports, thumbnail creation
  and non-main-thread media operations, but no performance ceiling exists for large
  photo libraries, sustained imports or thousands of items.
- Failed managed-file deletion produces a user-visible post-dismissal warning and is
  retryable through later orphan maintenance, including startup maintenance. There
  is no user-facing maintenance dashboard or manual retry control.
- Count-based refresh fault injection validates the committed-display and read-only
  recovery control flow. It does not reproduce real SwiftData or SQLite engine
  corruption, locking or I/O failure behavior.

## Development

- Goal 1 has only been built, tested, installed and launched on an iPhone Simulator.
- Real-device installation, Apple Team selection and paid Apple signing are not
  configured or verified.
- Real-device camera capture, permission-denied UI and selecting a real Photos asset
  have not been manually verified. Simulator coverage verifies the picker
  presentation/cancel path, unavailable-camera fallback, and valid-image
  import/thumbnail behavior at the service boundary.
- File copying, camera encoding, thumbnail generation and thumbnail display decoding
  run outside MainActor, but real-device responsiveness has not been profiled.
- `com.yocruzer.householdos` is configured but has not been validated against the
  Owner's Apple Team or registered App Store Connect application.
- No CI exists.
- No signed Archive or TestFlight upload has been performed.
- The provided App Icon compiles in Simulator builds; real-device and TestFlight
  presentation remain unverified.

## Privacy

- Export Privacy Policy is designed but not implemented.
- Actual removal of GPS and EXIF must be verified against exported files, not assumed from API calls.
- Sensitive credential encryption beyond platform file protection has not been designed.
