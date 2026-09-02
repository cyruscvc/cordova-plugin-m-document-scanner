# Release test matrix

Complete this matrix against the exact MABS build before production rollout.

## Build validation

- [ ] O11 wrapper publishes with the local Resource configuration.
- [ ] MABS 12 Android build succeeds with `cordova-plugin-ml-text-receipt` also installed.
- [ ] MABS 12 iOS build succeeds with `cordova-plugin-visionkit` and `cordova-plugin-ml-text-receipt` also installed.
- [ ] No Gradle dependency resolution downgrade affects ML Kit text recognition.
- [ ] No duplicate Cordova service, iOS class, Java package, or JavaScript clobber warning appears.

## iOS devices

- [ ] Current supported iPhone: single-page auto capture, manual capture, corner editing, enhancement, retake, use, cancel.
- [ ] iPad portrait: controls and safe areas render correctly.
- [ ] Gallery selection returns one corrected image.
- [ ] Camera denied/restricted returns one error and no frozen overlay.
- [ ] VisionKit multi-page returns up to `maxPages` after Save.
- [ ] JPEG-only, PDF-only, and JPEG+PDF outputs open successfully.
- [ ] Twenty repeated open/cancel/scan cycles show no retained camera session.

## Android devices

- [ ] Pixel 8 Pro: single-page limit, gallery, crop, filters, cancel, output.
- [ ] Galaxy A55 5G: first-use component download, capture performance, memory behavior.
- [ ] Managed device with Google Play services available.
- [ ] Device without available Play services returns `SCANNER_UNAVAILABLE` cleanly.
- [ ] Device below 1.7 GB total RAM returns `UNSUPPORTED_DEVICE`.
- [ ] JPEG-only, PDF-only, and JPEG+PDF outputs open successfully.
- [ ] Twenty repeated open/cancel/scan cycles return exactly one callback each.

## OutSystems integration

- [ ] `IsCancelled` is true without showing an error message.
- [ ] Receipt OCR reads `Pages[0].Uri` with `imgType = 0`.
- [ ] Upload completes before cleanup.
- [ ] Cleanup removes one requested session.
- [ ] Age-based cleanup removes stale sessions but not recent sessions.
- [ ] Old installed app shows the wrapper's “plugin unavailable” message until a newly generated binary is installed.

Record the tested MABS version, Cordova platform versions from the MABS log, OS versions, device models, and final build identifiers with the release evidence.
