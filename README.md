# FixRecord

**Turn job photos, notes and receipts into clear reports and invoices.**

FixRecord is an iPhone app for contractors and repair work. Keep the details of each job together, then share a professional PDF with your client. The core workflow runs on your device, with no account required.

<img src="docs/jobs-current.png" alt="FixRecord showing the fictional Kitchen Sink Repair example job" width="280">

## From job to document

- **Capture the work.** Take before-and-after photos, match the framing with a ghost overlay, and choose which images appear in the report.
- **Record the details.** Type or dictate notes, customise job references, and reuse saved business presets.
- **Review the costs.** Scan receipts on-device, correct suggested items and quantities, and add materials, labour and other charges.
- **Share with your client.** Preview and export work reports and invoices through Share, Files or Print.

Optional AI writing helps turn rough notes into a draft you review before accepting. Receipt scanning does not use an AI service.

## Free and Pro

| Free | Pro adds |
| --- | --- |
| Jobs, photos, notes and saved presets | Nine additional document layouts — ten in total |
| On-device receipt scanning and supported dictation | Custom colours and a business logo |
| Business name and contact details on documents | Automatic removal of the FixRecord footer |
| Separate report and invoice PDFs | Client Pack: report and invoice together |

Pro purchases and restores use RevenueCat. The competition build uses its **Test Store**, with simulated purchases rather than live billing. Prices and eligible trials come from the configured offering.

## Try it

Requires **Xcode 26.3 or later** and **iOS 17 or later**.

1. Open `FixRecord.xcodeproj` and let Xcode resolve the Swift packages.
2. Select the **FixRecord** scheme and an iPhone simulator, then run.
3. Choose **Add Example Job** during onboarding to explore a fictional repair, or create your own job.

Jobs, receipt scanning and PDF exports work without backend configuration. Camera features need a physical iPhone; the simulator supports importing photos. Sample photos are generated demo assets depicting a fictional repair.

## Guides

- [Judge walkthrough](docs/JUDGING.md) — a five-minute tour, Test Store setup and optional AI access.
- [Development guide](docs/DEVELOPMENT.md) — device setup, configuration, checks and architecture.
- [Submission preparation](docs/SUBMISSION.md) — competition checklist and remaining actions.
- [Entry draft](docs/ENTRY.md) — project background and submission copy.

## Run checks

```sh
xcodebuild test -project FixRecord.xcodeproj -scheme FixRecord \
  -destination 'platform=iOS Simulator,id=YOUR_SIMULATOR_UDID' \
  -parallel-testing-enabled NO

cd backend
npm ci
npm run typecheck
npm test
```

Find a simulator UUID with `xcrun simctl list devices available`. Tests use sample data and do not need AI or purchase credentials.

## Data and scope

Job records, photos and receipts are stored locally. There is no automatic cloud backup or client payment collection. Receipt suggestions need review, and photo matching helps with framing; it does not verify repair quality.

Optional AI sends job text, material names and up to one before-and-after photo pair to the configured backend and OpenAI. It requires a private demo access code. The [development guide](docs/DEVELOPMENT.md#optional-ai-note-assistance) explains data handling and demo limits. Manual notes and exports remain available offline.

## Licence

FixRecord is licensed under [AGPL-3.0](LICENSE). Built with SwiftUI, SwiftData, Apple Vision and Speech, RevenueCat, and OpenCV Mobile. Third-party licence notices are included in [ThirdParty](ThirdParty/).
