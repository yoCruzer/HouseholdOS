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
- No performance baseline exists for large photo libraries or thousands of items.

## Development

- Goal 1 has only been built, tested, installed and launched on an iPhone Simulator.
- Real-device installation and paid Apple signing are not configured or verified.
- Real-device camera capture, permission-denied UI and selecting a real Photos asset have not been manually verified. Simulator coverage verifies the picker presentation/cancel path, unavailable-camera fallback, and valid-image import/thumbnail behavior at the service boundary.
- `com.yocruzer.householdos.dev` is a temporary Bundle Identifier with no external service bindings.
- No CI exists.
- No TestFlight pipeline exists.
- No formal App Icon or brand assets are included.

## Privacy

- Export Privacy Policy is designed but not implemented.
- Actual removal of GPS and EXIF must be verified against exported files, not assumed from API calls.
- Sensitive credential encryption beyond platform file protection has not been designed.
