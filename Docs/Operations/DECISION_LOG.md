# Decision Log

This file records permanent decisions that materially affect product semantics, architecture, privacy, data compatibility or governance.

## D-001 — Local-first Baseline

Date: 2026-07-24
Status: ACCEPTED

Core capture, editing, browsing, search and statistics must work offline. Cloud sync is an optional later capability.

## D-002 — CaptureDraft Is Separate from Item

Date: 2026-07-24
Status: ACCEPTED

Unconfirmed or incomplete captures remain in CaptureDraft and do not participate in formal Item search and statistics.

## D-003 — WishItem Is a Separate Future Concept

Date: 2026-07-25
Status: ACCEPTED

Items considered before purchase are modeled as `WishItem`, not as an Item lifecycle status. V1 reserves the boundary but does not implement the complete feature.

## D-004 — Preserve Original Photo Metadata Locally

Date: 2026-07-25
Status: ACCEPTED

Local import preserves original metadata, including GPS, because it may be useful and local storage does not itself constitute external disclosure.

## D-005 — Strip GPS by Default on Ordinary External Sharing

Date: 2026-07-25
Status: ACCEPTED

External sharing generates a derivative and applies Export Privacy Policy. GPS is removed by default; the original remains unchanged. Settings must explain this behavior.

## D-006 — Facts vs Snapshots

Date: 2026-07-24
Status: ACCEPTED

Lifecycle events and placements are historical facts. Item status and current placement are derived/current snapshots maintained through domain services.

## D-007 — Stage Autonomy with Owner Gates

Date: 2026-07-25
Status: ACCEPTED

Codex may autonomously complete implementation details inside an approved Stage, but cannot advance to an unapproved Stage or merge to main.

## D-008 — Preserve Existing Repository License

Date: 2026-07-25
Status: ACCEPTED

The AGPL-3.0 `LICENSE` created in the initial `main` bootstrap commit remains the repository license and is preserved during the G0 governance foundation import.

## D-009 — Native iOS Xcode Foundation

Date: 2026-07-26
Status: ACCEPTED

The verified engineering baseline is a native iOS `.xcodeproj` using Swift, SwiftUI, Swift 6 language mode and an iOS 17.0 minimum deployment target. Initial stages use Apple native frameworks only and introduce no third-party dependencies.

## D-010 — Temporary Development Identifier

Date: 2026-07-26
Status: ACCEPTED

`com.yocruzer.householdos.dev` is a temporary local and Simulator development identifier. It must not be bound to CloudKit, App Groups, Keychain Sharing, Associated Domains, Push Notifications or another long-lived external service. Formal branding, signing and identifier selection require a separate Owner decision.
