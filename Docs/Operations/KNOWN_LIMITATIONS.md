# Known Limitations

Status: ACTIVE

## Product / Scope

- Complete WishItem workflow is not part of V1.
- Household realtime sharing and account system are deferred.
- OCR, AI recognition and automated purchase advice are deferred.
- External commerce order synchronization is deferred.
- Multi-currency historical conversion is not automatic in V1.

## Architecture

- Final minimum iOS version has not yet been validated against the local Xcode environment.
- SwiftData is the intended persistence technology but must be validated in F0/F1.
- Backup format and migration versioning are not yet implemented.
- No performance baseline exists for large photo libraries or thousands of items.

## Development

- No Xcode project exists.
- No test commands or build scheme exist.
- No CI exists.
- No signed app or TestFlight pipeline exists.
- GitHub repository initialization has not yet been completed at the time this file was generated.

## Privacy

- Export Privacy Policy is designed but not implemented.
- Actual removal of GPS and EXIF must be verified against exported files, not assumed from API calls.
- Sensitive credential encryption beyond platform file protection has not been designed.
