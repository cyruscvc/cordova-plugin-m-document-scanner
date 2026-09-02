# M Document Scanner for Cordova and OutSystems

`cordova-plugin-m-document-scanner` provides one JavaScript API for production document scanning on iOS and Android.

- **iOS single-page:** a maintained, namespaced WeScan fork using AVFoundation + Apple Vision, with stable auto-capture, manual corner editing, review, enhancement, and a strict one-document flow.
- **iOS multi-page:** Apple's native VisionKit document camera.
- **Android:** Google Play services ML Kit Document Scanner with a real page limit, crop/review UI, gallery import, filters, JPEG output, and PDF output.

The plugin is isolated from `cordova-plugin-visionkit`, `cordova-plugin-ml-text`, and `cordova-plugin-ml-text-receipt`: it uses a different Cordova ID, native service, JavaScript namespace, iOS class, and Android package.

## Requirements

| Platform | Requirement |
|---|---|
| OutSystems | O11 mobile app using MABS 12 and Cordova |
| iOS | iOS 13+, rear camera for camera capture |
| Android | API 21+, Google Play services, at least 1.7 GB total RAM |
| Cordova | `cordova-ios` 7+ or `cordova-android` 12+ |

The Android scanner UI and models are delivered by Google Play services. The first Android scan can take longer while those components are downloaded.

## Installation

### Cordova

```bash
cordova plugin add https://github.com/cyruscvc/cordova-plugin-m-document-scanner.git \
  --variable CAMERA_USAGE_DESCRIPTION="Scan receipts, business cards, and documents." \
  --variable PHOTOLIBRARY_USAGE_DESCRIPTION="Select a document image from your photo library."
```

### OutSystems 11 local Resource

Generate the deterministic ZIP:

```bash
python3 scripts/package_outsystems.py .
```

Then follow [the complete OutSystems wiring guide](docs/OUTSYSTEMS.md).

## JavaScript API

The namespace is available after `deviceready`:

```javascript
cordova.plugins.mDocumentScanner.scan(
  {
    captureMode: "single",
    maxPages: 1,
    allowGallery: false,
    resultFormats: ["jpeg"],
    jpegQuality: 0.9,
    scannerMode: "full",
    autoCapture: true,
    stabilityDurationMs: 1200,
    detectionConfidence: 0.8,
    minDocumentArea: 0.2
  },
  function (result) {
    if (result.status === "cancelled") return;
    console.log(result.pages[0].uri);
  },
  function (error) {
    console.error(error.code, error.message);
  }
);
```

See [API.md](docs/API.md) for every option, output, error code, and lifecycle rule.

## Result example

```json
{
  "status": "success",
  "platform": "ios",
  "engine": "wescan",
  "sessionId": "4a54a63e-dc6a-4fd9-82df-c4d60072040b",
  "pageCount": 1,
  "pages": [
    {
      "index": 0,
      "uri": "file:///.../m-document-scanner/.../page-001.jpg",
      "mimeType": "image/jpeg",
      "width": 3024,
      "height": 4032
    }
  ],
  "pdf": null,
  "uiPageLimitEnforced": true
}
```

Images and PDFs are returned as cache-backed file URIs rather than Base64. Process or upload them promptly, then call `cleanup`. Mobile operating systems may purge cache files under storage pressure.

## Reading a result as OutSystems Binary Data

The scanner returns cache-backed URIs to avoid large Cordova bridge payloads. When an OutSystems flow specifically needs Binary Data or Base64, use the included `ReadScannerFile` wrapper action with `Pages[0].Uri` or `Pdf.Uri`.

Binary Data is always returned. Base64 is optional because it increases the payload by roughly one third and creates additional memory pressure. The native reader only accepts files inside this scanner's cache and refuses files larger than 50 MB.

## Using the existing receipt OCR plugin

Keep capture and OCR as separate steps:

```javascript
cordova.plugins.mDocumentScanner.scan(
  { captureMode: "single", resultFormats: ["jpeg"] },
  function (scan) {
    if (scan.status !== "success") return;
    mltextreceipt.getReceiptText(onOcrSuccess, onOcrError, {
      imgType: 0,
      imgSrc: scan.pages[0].uri,
      rotationDegrees: 0
    });
  },
  onScanError
);
```

## Native behavior differences

- Single-page iOS uses the bundled WeScan-derived flow because VisionKit exposes no supported maximum-page setting. The fork is namespaced and maintained inside this repository.
- Multi-page iOS uses the exact VisionKit UI. `maxPages` limits the returned pages after the user taps Save; it cannot restrict VisionKit's page-adding UI.
- Android enforces `maxPages` in the ML Kit UI.

## Validation

```bash
npm test
python3 scripts/validate_plugin.py .
python3 scripts/package_outsystems.py .
python3 scripts/validate_plugin.py ../cordova-plugin-m-document-scanner.zip
```

Static validation and Cordova installation do not replace MABS compilation and physical-device tests. Use [TEST-MATRIX.md](docs/TEST-MATRIX.md) before production rollout.

## License

MIT. See [LICENSE](LICENSE). Bundled WeScan-derived sources remain under the upstream MIT license; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
