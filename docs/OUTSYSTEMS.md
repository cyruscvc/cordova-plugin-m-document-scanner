# OutSystems 11 wiring

This guide targets an O11 mobile app built with MABS 12 in Cordova mode.

## 1. Package the plugin

From the repository root:

```bash
python3 scripts/package_outsystems.py .
```

The output must be named exactly:

`cordova-plugin-m-document-scanner.zip`

The ZIP contains exactly one root directory with the same name as the Cordova ID.

## 2. Create the wrapper module

Create a dedicated mobile plugin wrapper module, for example `MDocumentScannerPlugin`.

Add `cordova-plugin-m-document-scanner.zip` under **Data > Resources** with these properties:

| Property | Value |
|---|---|
| Name | `cordova-plugin-m-document-scanner.zip` |
| Public | `No` |
| Deploy Action | `Do Nothing` |
| Target Directory | blank |

Set the wrapper module's **Extensibility Configurations** to:

```json
{
  "resource": "cordova-plugin-m-document-scanner.zip",
  "plugin": {
    "resource": "cordova-plugin-m-document-scanner",
    "variables": [
      {
        "name": "CAMERA_USAGE_DESCRIPTION",
        "value": "Scan receipts, business cards, and documents."
      },
      {
        "name": "PHOTOLIBRARY_USAGE_DESCRIPTION",
        "value": "Select a document image from your photo library."
      }
    ]
  }
}
```

The outer Resource includes `.zip`; `plugin.resource` does not.

## 3. Add `ScanDocument`

Create a public Client Action named `ScanDocument`.

### Inputs

| Input | Type | Suggested default |
|---|---|---|
| `CaptureMode` | Text | `"single"` |
| `MaxPages` | Integer | `1` |
| `AllowGallery` | Boolean | `False` |
| `ResultFormatsJson` | Text | `"[\"jpeg\"]"` |
| `JpegQuality` | Decimal | `0.9` |
| `ScannerMode` | Text | `"full"` |
| `AutoCapture` | Boolean | `True` |
| `StabilityDurationMs` | Integer | `1200` |
| `DetectionConfidence` | Decimal | `0.8` |
| `MinDocumentArea` | Decimal | `0.2` |

### Outputs

| Output | Type |
|---|---|
| `IsSuccess` | Boolean |
| `IsCancelled` | Boolean |
| `ResultJson` | Text |
| `ErrorCode` | Text |
| `ErrorMessage` | Text |

Add an asynchronous JavaScript node and paste [outsystems/ScanDocument.js](../outsystems/ScanDocument.js). Map every input and output with the same name.

## 4. Add `GetScannerCapabilities`

Outputs: `IsSuccess`, `ResultJson`, `ErrorCode`, `ErrorMessage`. Paste [outsystems/GetScannerCapabilities.js](../outsystems/GetScannerCapabilities.js).

Call this once after `deviceready` or before showing the first scanner entry point. Do not treat the ordinary browser preview as a supported native scanner environment.

## 5. Add `CleanupScannerFiles`

Inputs: `SessionId` (Text), `MaxAgeHours` (Integer). Outputs: `IsSuccess`, `DeletedSessions` (Integer), `ErrorCode`, `ErrorMessage`. Paste [outsystems/CleanupScannerFiles.js](../outsystems/CleanupScannerFiles.js).

Call cleanup only after all OCR, upload, preview, or parsing work is complete.

## 6. Read a scanner URI as Binary Data or Base64

Create a public asynchronous Client Action named `ReadScannerFile` and paste [outsystems/ReadScannerFile.js](../outsystems/ReadScannerFile.js) into its JavaScript node.

### Inputs

| Input | Type | Suggested default |
|---|---|---|
| `Uri` | Text | mandatory |
| `IncludeBase64` | Boolean | `False` |
| `MaxBytes` | Integer | `26214400` |

### Outputs

| Output | Type |
|---|---|
| `IsSuccess` | Boolean |
| `BinaryData` | Binary Data |
| `Base64` | Text |
| `MimeType` | Text |
| `FileName` | Text |
| `Size` | Integer |
| `ErrorCode` | Text |
| `ErrorMessage` | Text |

Pass `Pages[0].Uri` for a JPEG or `Pdf.Uri` for a PDF. Keep `IncludeBase64 = False` unless a downstream API explicitly requires Base64; Base64 increases payload size and memory use. The native read is restricted to scanner-owned cache files and has a 50 MB hard maximum.

## 7. Deserialize the result

Import [outsystems/scan-result.sample.json](../outsystems/scan-result.sample.json) into an OutSystems Structure, or create these structures manually:

- `DocumentScanResult`: Status, Platform, Engine, SessionId, PageCount, UiPageLimitEnforced, Pages list, Pdf
- `DocumentScanPage`: Index, Uri, MimeType, Width, Height
- `DocumentScanPdf`: Uri, MimeType, PageCount

Cancellation returns `Status = "cancelled"`, an empty Pages list, and no error.

## 8. Connect the existing receipt OCR plugin

For a successful single-page scan:

1. Deserialize `ResultJson`.
2. Read `Pages[0].Uri`.
3. Call `mltextreceipt.getReceiptText` with `imgType = 0` and `imgSrc = Pages[0].Uri`.
4. Finish OCR, upload, and preview work.
5. Call `CleanupScannerFiles` with the scanner `SessionId`.

Do not convert the scanner URI to Base64 first; that increases memory pressure and bridge payload size.

## 9. Publish and rebuild

1. Publish the wrapper.
2. Refresh the wrapper dependency in the consuming mobile app.
3. Publish the app.
4. Generate new Android and iOS native packages with MABS 12.
5. Install those new packages on physical devices.

Refreshing a dependency does not add native code to an already installed binary.

## Coexistence during migration

The wrapper may coexist with your existing VisionKit and receipt OCR wrappers. Migrate one scanner entry point first. Remove the old VisionKit plugin only after no app module still depends on it and the combined Android/iOS MABS builds pass.
