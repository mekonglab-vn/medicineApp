# MedicineApp Flutter client

This directory contains the mobile research-prototype UI used to acquire a
prescription image, perform on-device Google ML Kit OCR, review extracted
medications, check interactions, and schedule reminders.

The client is not a medical device. Outputs require human review and must not be
used as the sole basis for medication decisions.

## Run locally

Requirements: Flutter 3.38.x or a compatible stable release, Android SDK 34 or
35, JDK 17+, and a running MedicineApp API.

```bash
flutter pub get
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:3000/api
```

For a physical device connected over USB, run `adb reverse tcp:3000 tcp:3000`
and use `http://127.0.0.1:3000/api`. A non-secret configuration example is in
`dart_defines.example.json`.

## Checks

```bash
flutter analyze
flutter test
```

The public repository does not include source prescription images, OCR payloads,
ground truth, model weights, or the full drug normalization database. Those
artifacts are not required to inspect or build the UI, but the backend will not
reproduce paper experiments without separately authorized inputs.
