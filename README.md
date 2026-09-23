# FixRecord

[AGPL-3.0 licensed](LICENSE)

**Proof the work was done.** A local-first iPhone app for documenting field work, matching before and after photos, recording materials and labour, and exporting a work report and invoice.

| Sample Home | Work Report preview |
| --- | --- |
| ![FixRecord Home with a sample job](docs/home-sample-original.png) | ![FixRecord Work Report with original demo before and after photos](docs/report-sample-original.png) |

## Run the app

1. Open `FixRecord.xcodeproj` in Xcode 26.3 or later. The deployment target is iOS 17.
2. Let Xcode resolve the RevenueCat Swift package. The OpenCV Mobile 4.13.0 XCFramework is included in `ThirdParty/` with device and Apple Silicon/Intel simulator slices.
3. Select an iPhone simulator and run. No login, AI account, or purchase is needed for the manual workflow.
4. Tap **Tools → Load Sample Job**, then open **Kitchen Sink Repair**. Its names, address, photos and prices are sample data.
5. Open the before and after steps to see the ghost overlay. On a simulator, use imported images; the camera needs a device.
6. Open **Materials & Pricing** to inspect Decimal totals, then **Report & Invoice** to preview and share PDFs.

The before and after sample photos are original generated demo assets. They depict a fictional repair and are provided only to exercise the app.

### Run checks

```sh
xcodebuild test -project FixRecord.xcodeproj -scheme FixRecord \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' CODE_SIGNING_ALLOWED=NO
cd backend && npm install && npm run typecheck
```

The Xcode project links [RevenueCat's iOS SDK](https://www.revenuecat.com/docs/getting-started/installation/ios) and [OpenCV Mobile](https://github.com/nihui/opencv-mobile). The bundled XCFramework makes MatchShot available in the simulator without a separate OpenCV installation. The Objective-C++ bridge is isolated in `MatchShotBridge.mm`.

## RevenueCat Test Store

Create a RevenueCat project with a Test Store app, an offering containing monthly/annual packages, and a `pro` entitlement attached to those products. Set the app target's `REVENUECAT_API_KEY` build setting to the **public Test Store SDK key** (`test_…`) for Debug builds. You can also pass it to `xcodebuild` as `REVENUECAT_API_KEY=test_…`. Never put a RevenueCat secret API key in the app. The Upgrade screen reads package titles and prices from RevenueCat, supports purchase and restore, and grants Client Pack export only while the `pro` entitlement is active. Work Report and Invoice exports remain free.

A Test Store purchase shows RevenueCat's simulated purchase sheet. It does not require App Store Connect. See the [Test Store guide](https://www.revenuecat.com/docs/test-and-launch/sandbox/test-store). **Do not ship a release build with a Test Store key**; replace it with the platform-specific public key first. This checkout has no project-specific RevenueCat key, offering or hosted backend configured, so those live flows need your own account configuration.

## Optional AI note assistance

The manual note always works. To enable **Improve with AI**, deploy `backend/` to Vercel and set its environment variables from `backend/.env.example`: `OPENAI_API_KEY`, a compatible `OPENAI_MODEL`, and both Upstash Redis REST variables. Hosted deployments fail closed if Redis limits are missing. The endpoint sends only the job title, issue, rough note, material names, locale and a local install ID. It sends no photos. Set the app target's `AI_ENDPOINT` build setting to the HTTPS URL ending in `/api/generate-report`, or pass `AI_ENDPOINT=https://…` to `xcodebuild`.

The backend limits input length, requests per minute/day per installation and client IP, monthly assisted jobs (10 Free or 100 Pro, with up to five rewrites per job), and the server-wide daily budget. Set `REVENUECAT_SECRET_API_KEY` on the server to verify Pro for the larger allowance; without it, the Free allowance applies. It requests structured JSON, times out, and returns generic errors without logging secrets. A user must review and explicitly accept any AI-assisted draft. It is a writing aid; it does not verify repairs or safety.

## How it is organised

- `Models.swift`: SwiftData jobs/profile, photo and receipt references, Decimal invoice maths, sample fixture.
- `CameraAndReceipts.swift`: AVFoundation camera, Photos import, ghost overlay, image-quality notice, on-device Vision OCR and correction form.
- `MatchShotBridge.mm`: scaled OpenCV ORB feature matching and geometric consistency check after capture. Low-confidence matches give neutral guidance. The ghost overlay remains available without an alignment result.
- `NotesPricingPurchase.swift`: note editing/AI client, itemised pricing and RevenueCat entitlement service.
- `PDFExport.swift`: separate A4 work report, invoice and Pro Client Pack PDFs, with page breaks and share sheet.
- `backend/api/generate-report.ts`: optional server-side AI rewrite. The API key stays on the server.

Job records live in SwiftData. Photos and receipt images live as files in the app's Application Support directory. The app has no sign-in requirement. Deleting the app deletes local records unless they were exported or backed up by the user.

## Current scope

MatchShot's OpenCV analysis runs after capture, with a live ghost overlay while framing. Receipt OCR proposes editable rows and never adds them without confirmation. PDF report and invoice export, sample mode and manual notes work offline. A hosted AI endpoint and live RevenueCat Test Store setup are optional configuration steps. Cloud backup, accounts, client portal, payment collection and automatic repair verification are outside this build.

## Licences and acknowledgements

FixRecord source is AGPL-3.0; see [LICENSE](LICENSE). RevenueCat's Purchases SDK is MIT licensed. The bundled OpenCV Mobile 4.13.0 binary and OpenCV 4.13.0 are Apache-2.0 licensed. Licence texts are in `ThirdParty/`. Apple frameworks are provided by the iOS SDK. The sample photos are original generated demo assets. Review third-party notices before redistribution.
