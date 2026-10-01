# Judge walkthrough

FixRecord is Andrea Jane Williams’s Shipaton 2026 Next Gen project. It documents field work; it does not certify repairs or safety. No app account or paid Apple developer membership is required for simulator testing.

## Open and run

Use Xcode 26.3 or later and an installed iOS simulator runtime. Open `FixRecord.xcodeproj`, select the FixRecord scheme and an iPhone simulator, then Run. RevenueCat resolves through Swift Package Manager; OpenCV and sample assets are included. The app deployment target is iOS 17. Core jobs, receipt OCR and PDF export work without backend configuration.

Choose **Add Example Job** at the end of onboarding, then select **Completed → Kitchen Sink Repair**. The example is fictional and uses generated photos. If onboarding was skipped, add `-load-sample` to the scheme’s Run arguments and relaunch, then open Completed. Remove the argument afterwards to avoid re-adding a deleted example.

## Five-minute walkthrough

1. Open the example job. Use Photos to inspect the pair and toggle whether individual images or Before/After labels appear in the report.
2. Edit the job reference and work notes. On a phone, the microphone button requests microphone and speech permission; transcription is on-device where supported. Typing always works.
3. Open Materials & Pricing. Edit quantities/prices, delete a row, or import a receipt from Photos. Review suggestions before adding; tax, discounts and payment totals are not material lines. Inconsistent totals are flagged rather than silently corrected.
4. Open Preview & Export. Add business details for free, preview the actual Work Report and Invoice PDFs, and export through Share, Files or Print. Photos are optional.
5. Explore Templates. Modern is free; the other nine styles, custom logo, removal of the FixRecord footer and Client Pack require Pro. Saved presets reuse document details; job references remain editable.
6. On a physical iPhone, try Before capture, MatchShot After capture and automatic receipt capture. A simulator cannot verify camera behaviour. MatchShot compares framing, not repair quality.

## Test Pro without a real charge

The private submission notes provide the public RevenueCat Test Store SDK key. Alternatively, create your own Test Store project with a `pro` entitlement and a current offering containing monthly and annual packages, each attached to that entitlement.

Copy `Local.xcconfig.example` to ignored `Local.xcconfig` and fill in the public Test Store key. The hosted AI endpoint is already configured; leave it unchanged to use the private judging code. Never place a RevenueCat secret key or an OpenAI key in this file.

```sh
xcrun simctl list devices available
xcodebuild build -project FixRecord.xcodeproj -scheme FixRecord   -destination 'platform=iOS Simulator,id=YOUR_SIMULATOR_UDID'   -xcconfig Local.xcconfig CODE_SIGNING_ALLOWED=NO
```

For Xcode’s Run button, put the same values in the app target’s Debug User-Defined build settings (`REVENUECAT_API_KEY`); simply copying the file does not attach it to the project. The `AI_ENDPOINT` setting already points to the hosted demo.

Open Settings → FixRecord Pro, choose Monthly or Yearly, and continue through the simulated purchase sheet. Verify Pro becomes active and permits a premium export. Use Restore Purchases to check the entitlement again. The configured offering is US$4.99 monthly / US$39.99 yearly with seven-day trials; trial visibility depends on eligibility, and a returning test customer may not qualify. Test Store renewal timing is accelerated. Test purchases are not production payments. Test Store subscription management differs from Apple’s subscription settings.

## Optional AI writing

AI writing is separate from receipt scanning. Receipts never go to an AI API. The optional writing action sends job text, material names and up to one Before/After photo to the configured server and OpenAI. Review and accept the proposed text before using it.

The app defaults to `https://fixrecord-api.vercel.app/api/generate-report`. Use the private access code from the submission notes; no endpoint setup is needed. To use your own server, deploy `backend/` with your own credentials from `.env.example` and override `AI_ENDPOINT`. Enter the access code when Improve with AI prompts. Codes never belong in source control. A work note or readable job photo is needed. The server validates the code, enforces 3 Free / 30 Pro requests per installation per month and an aggregate 1,000-request judging cap, and uses Redis for hosted limits. Pro AI demo access is determined by the code, separately from Test Store purchases. The manual workflow remains usable when the endpoint is unavailable or its allowance is exhausted.

## Testing and data

Run the commands in README for the iOS tests and backend checks. Keep real client details out of demo recordings. App records and photos are local; uninstalling removes them. Exported PDFs are separate files. There is no cloud backup or client payment collection.
