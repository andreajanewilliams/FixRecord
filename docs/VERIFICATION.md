# Submission verification — 27 September 2026

## Automated checks

- `xcodebuild test -project FixRecord.xcodeproj -scheme FixRecord -destination 'platform=iOS Simulator,id=YOUR_SIMULATOR_UDID' CODE_SIGNING_ALLOWED=NO`: **69 passed, 0 failed, 0 skipped**, Xcode 26.3 / iOS 26.3.1 simulator.
- In `backend/`, `npm run typecheck && npm test`: **passed**, 11 backend tests.
- `git diff --check`: passed.

The iOS suite covers job defaults, duplication, reference validation, receipt parsing, photo selection, dictation transcript handling, PDF content/layout selection and entitlement gates. Backend tests cover payload validation, code checks and usage limits with mocked services. They do not establish live model availability or a real purchase.

## Manual evidence and remaining checks

The earlier physical-device Test Store purchase and restore succeeded with the previous offering. The current monthly/yearly trial products still need a fresh end-to-end purchase/restore check. The current receipt auto-capture implementation has compiled and passed helper tests; confirm detection and dismissal on a real receipt and phone. Camera, speech, sharing and the final uninterrupted journey require physical-device checks.

Existing demo footage predates recent UI changes. Record current footage before submitting. The repository remains private pending explicit approval. See [submission checklist](SUBMISSION.md).

## Independent review

A fresh Astra review is pending; this document does not claim a clean review until its outcome is recorded.
