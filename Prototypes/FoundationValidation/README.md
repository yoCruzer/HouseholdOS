# HHOS-FAV-001 isolated harness

Work in progress; authoritative scope and status are under `Docs/Validation/HHOS-FAV-001`. Shipping App inputs are unchanged. Swift package supports macOS 14 / iOS 17; no third-party dependencies.

Commands from this directory:

```sh
swift build
swift test --filter LocalChainTests
swift test --filter SyncProtocolTests
.build/debug/hhos-validation legacy LocalEvidence/new-immutable-fixture
.build/debug/hhos-validation migrate LocalEvidence/new-immutable-fixture LocalEvidence/new-candidate-clone
.build/debug/hhos-validation verify LocalEvidence/new-candidate-clone
```

Generator must terminate before cloning; the CLI copies the entire fixture directory including all store sidecars. It refuses existing destinations. Retain original fixtures. Do not pass shipping stores or personal media. `LocalEvidence/` is durable and gitignored, containing logs and synthetic stores. No live container is configured by default. Core compile is not service evidence.

Baseline model/container files are exact copies with source hashes in LegacySourceManifest.json. Candidate sidecars are experimental, not a frozen V2 schema.
