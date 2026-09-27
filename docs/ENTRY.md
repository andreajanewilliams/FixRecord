# FixRecord — draft entry

Draft for Andrea to review before submission. No publication or entry submission has been made.

## One-line description

Turn before-and-after photos and work notes into clear reports and invoices from your iPhone.

## The problem

Small repair jobs often leave a scattered trail of photos, messages and receipts. FixRecord brings those details into one local job record and helps a contractor send a professional document to a client.

## What it does

Create a job, capture photos, dictate or type what happened, and review materials from a receipt scan. MatchShot provides a before-photo overlay to help frame the after photo. Choose which photos to include, add business details, and export a real PDF work report or invoice. Optional AI improves the wording of notes after the user reviews the draft. It does not verify a repair.

## RevenueCat integration

RevenueCat manages the Test Store purchase, entitlement and restore flow. Free users can complete the core workflow and export separate reports and invoices with their business details. Pro adds nine document styles, a business logo, footer removal and a combined Client Pack. Monthly and yearly packages come from the current offering; eligible trials are displayed using SDK eligibility rather than a hard-coded promise.

## How it was built

SwiftUI and SwiftData provide the interface and local records. Apple Vision proposes receipt items for review; Apple Speech supports dictation. An Objective-C++ OpenCV bridge compares photo framing. PDF generation happens on the device. An optional TypeScript endpoint protects the AI key and enforces demo quotas through Redis. The source is licensed under AGPL-3.0.

## What was learned

Receipt layouts and camera conditions vary substantially, so editable suggestions and clear processing feedback matter. A useful free document is also essential: business details are available to everyone, while Pro focuses on presentation and reusable professional output.

## Current limits and next steps

Receipt OCR needs human review. Photo matching concerns framing, not workmanship. There is no cloud backup, payment collection or production billing claim. Next steps are field testing with contractors, accessibility testing, and production entitlement verification for paid AI allowances.

## Details Andrea must complete

- Academic-email eligibility and team/entrant details.
- Final public repository and demo URLs after publication approval.
- Current screenshots and icon.
- Private judge configuration values and a contact email.
- Personal development story and any required AI-tool disclosures, accurately reflecting how the app was made.
