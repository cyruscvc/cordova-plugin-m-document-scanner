# Security and privacy

- The plugin does not request network permission or upload scan results.
- iOS document detection and image correction run on device.
- Android scanning is provided by Google Play services; scanner components may be downloaded before first use.
- Results are written only to the app's private cache directory and returned as file URIs.
- Consumers are responsible for access control, upload transport, retention, audit, and calling `cleanup` after use.
- Do not log scan URIs, OCR output, or document images in production telemetry.

Report vulnerabilities privately to the repository owner rather than opening a public issue containing sensitive document data.
