# API contract

## `scan(options, success, error)`

Opens exactly one scanner session. A second invocation while the first is active fails with `SCANNER_BUSY`.

### Options

| Option | Type | Default | Notes |
|---|---:|---:|---|
| `captureMode` | Text | `single` | `single` or `multi` |
| `maxPages` | Integer | `1` / `20` | Forced to 1 for single mode; bounded to 1–50 for multi mode |
| `allowGallery` | Boolean | `false` | Available in Android ML Kit and the WeScan-derived iOS single-page scanner |
| `resultFormats` | Text list | `jpeg` | One or both of `jpeg`, `pdf` |
| `jpegQuality` | Decimal | `0.9` | Bounded to 0.35–1.0; used by iOS, while Android ML Kit controls its own JPEG encoding |
| `scannerMode` | Text | `full` | Android: `base`, `base_with_filter`, or `full`; ignored on iOS |
| `autoCapture` | Boolean | `true` | Sets the initial Auto/Manual state of the WeScan-derived iOS scanner |
| `stabilityDurationMs` | Integer | `1200` | Approximate iOS single-page stability window; bounded to 500–5000 ms |
| `detectionConfidence` | Decimal | `0.8` | Apple Vision rectangle confidence in iOS single-page mode; bounded to 0.5–1.0 |
| `minDocumentArea` | Decimal | `0.2` | Minimum normalized rectangle area; bounded to 0.08–0.9 |

### Success and cancellation

Cancellation is an expected success callback with `status: "cancelled"`; it is not routed through the error callback.

`uiPageLimitEnforced` means the native capture UI prevented additional pages. It is `false` only for iOS VisionKit multi-page mode.

### Errors

Errors are objects with `code`, `message`, and optionally `nativeType`.

| Code | Meaning |
|---|---|
| `INVALID_OPTIONS` | Unsupported or malformed option |
| `SCANNER_BUSY` | A scan is already open |
| `UNSUPPORTED_DEVICE` | Camera, OS, API level, or RAM requirement is not met |
| `SCANNER_UNAVAILABLE` | Android could not obtain the ML Kit scanner intent, including missing/unavailable Play services components |
| `START_FAILED` | Native scanner UI could not start |
| `SCAN_FAILED` | Native capture or processing failed |
| `EMPTY_RESULT` | Native scanner completed without a readable result |
| `FILE_WRITE_FAILED` | Cache-backed JPEG/PDF output could not be created |
| `CLEANUP_FAILED` | Cache cleanup failed |

## `getCapabilities(success, error)`

Returns platform-specific availability and feature flags. Call this before exposing the scan button if you support devices without Google Play services or without a camera.

## `cleanup(options, success, error)`

Delete one completed scanner session:

```javascript
cordova.plugins.mDocumentScanner.cleanup(
  { sessionId: result.sessionId },
  onSuccess,
  onError
);
```

Or delete all plugin sessions older than a threshold:

```javascript
cordova.plugins.mDocumentScanner.cleanup(
  { maxAgeHours: 24 },
  onSuccess,
  onError
);
```

Do not clean up a session until OCR, preview, upload, or other consumers have finished reading its files.
