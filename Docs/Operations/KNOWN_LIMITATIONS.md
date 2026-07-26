# Known Limitations

Status: ACTIVE

## Product / Scope

- Complete WishItem workflow is not part of V1.
- Household realtime sharing and account system are deferred.
- OCR, AI recognition and automated purchase advice are deferred.
- External commerce order synchronization is deferred.
- Multi-currency historical conversion is not automatic in V1.

## Architecture

- iOS 17.0 has been validated as the F0 minimum deployment target with Xcode 26.5 and the iOS 26.5 Simulator runtime.
- SwiftData is the intended persistence technology but has not been implemented or validated; that work belongs to an approved F1.
- Backup format and migration versioning are not yet implemented.
- No performance baseline exists for large photo libraries or thousands of items.

## Development

- F0 has only been built, tested, installed and launched on an iPhone Simulator.
- Real-device installation and paid Apple signing are not configured or verified.
- `com.yocruzer.householdos.dev` is a temporary Bundle Identifier with no external service bindings.
- No CI exists.
- No TestFlight pipeline exists.
- No formal App Icon or brand assets are included.
- The current App is only an engineering placeholder; no business capability is implemented.

## Privacy

- Export Privacy Policy is designed but not implemented.
- Actual removal of GPS and EXIF must be verified against exported files, not assumed from API calls.
- Sensitive credential encryption beyond platform file protection has not been designed.
