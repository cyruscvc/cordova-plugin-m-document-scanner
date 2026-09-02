package com.mubadala.documentscanner;

import android.app.Activity;
import android.app.ActivityManager;
import android.content.Context;
import android.content.Intent;
import android.content.IntentSender;
import android.graphics.BitmapFactory;
import android.net.Uri;
import android.os.Build;

import com.google.mlkit.vision.documentscanner.GmsDocumentScanner;
import com.google.mlkit.vision.documentscanner.GmsDocumentScannerOptions;
import com.google.mlkit.vision.documentscanner.GmsDocumentScanning;
import com.google.mlkit.vision.documentscanner.GmsDocumentScanningResult;

import org.apache.cordova.CallbackContext;
import org.apache.cordova.CordovaPlugin;
import org.apache.cordova.PluginResult;
import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.io.File;
import java.io.FileOutputStream;
import java.io.FileInputStream;
import java.io.IOException;
import java.io.InputStream;
import java.util.List;
import java.util.Locale;
import java.util.UUID;

public final class MDocumentScanner extends CordovaPlugin {
    private static final int REQUEST_SCAN = 0x4D44;
    private static final int MINIMUM_API_LEVEL = 21;
    private static final long MINIMUM_RAM_BYTES = 1700L * 1024L * 1024L;
    private static final String CACHE_DIRECTORY = "m-document-scanner";
    private static final int DEFAULT_MAX_READ_BYTES = 25 * 1024 * 1024;
    private static final int MAX_READ_BYTES = 50 * 1024 * 1024;

    private final Object stateLock = new Object();
    private CallbackContext pendingCallback;
    private ScanOptions pendingOptions;

    @Override
    public boolean execute(String action, JSONArray args, CallbackContext callbackContext) {
        switch (action) {
            case "scan":
                startScan(args.optJSONObject(0), callbackContext);
                return true;
            case "getCapabilities":
                callbackContext.success(capabilities());
                return true;
            case "cleanup":
                cleanup(args.optJSONObject(0), callbackContext);
                return true;
            case "readFile":
                readFile(args.optJSONObject(0), callbackContext);
                return true;
            default:
                return false;
        }
    }

    private void startScan(JSONObject rawOptions, CallbackContext callbackContext) {
        final ScanOptions options;
        try {
            options = ScanOptions.from(rawOptions);
        } catch (JSONException | IllegalArgumentException exception) {
            sendError(callbackContext, "INVALID_OPTIONS", safeMessage(exception), exception);
            return;
        }

        if (Build.VERSION.SDK_INT < MINIMUM_API_LEVEL) {
            sendError(callbackContext, "UNSUPPORTED_DEVICE",
                    "Android API 21 or newer is required.", null);
            return;
        }
        if (totalMemoryBytes() < MINIMUM_RAM_BYTES) {
            sendError(callbackContext, "UNSUPPORTED_DEVICE",
                    "The ML Kit document scanner requires at least 1.7 GB of RAM.", null);
            return;
        }

        synchronized (stateLock) {
            if (pendingCallback != null) {
                sendError(callbackContext, "SCANNER_BUSY",
                        "Another document scan is already active.", null);
                return;
            }
            pendingCallback = callbackContext;
            pendingOptions = options;
        }

        cordova.getActivity().runOnUiThread(() -> {
            GmsDocumentScannerOptions.Builder builder =
                    new GmsDocumentScannerOptions.Builder()
                            .setGalleryImportAllowed(options.allowGallery)
                            .setPageLimit(options.maxPages)
                            .setScannerMode(options.scannerMode);

            if (options.wantsJpeg && options.wantsPdf) {
                builder.setResultFormats(
                        GmsDocumentScannerOptions.RESULT_FORMAT_JPEG,
                        GmsDocumentScannerOptions.RESULT_FORMAT_PDF);
            } else if (options.wantsPdf) {
                builder.setResultFormats(GmsDocumentScannerOptions.RESULT_FORMAT_PDF);
            } else {
                builder.setResultFormats(GmsDocumentScannerOptions.RESULT_FORMAT_JPEG);
            }

            GmsDocumentScanner scanner = GmsDocumentScanning.getClient(builder.build());
            scanner.getStartScanIntent(cordova.getActivity())
                    .addOnSuccessListener(intentSender -> {
                        try {
                            cordova.setActivityResultCallback(this);
                            cordova.getActivity().startIntentSenderForResult(
                                    intentSender, REQUEST_SCAN, null, 0, 0, 0);
                        } catch (IntentSender.SendIntentException exception) {
                            finishWithError("START_FAILED", safeMessage(exception), exception);
                        }
                    })
                    .addOnFailureListener(exception ->
                            finishWithError("SCANNER_UNAVAILABLE", safeMessage(exception), exception));
        });
    }

    @Override
    public void onActivityResult(int requestCode, int resultCode, Intent intent) {
        if (requestCode != REQUEST_SCAN) {
            return;
        }
        if (resultCode == Activity.RESULT_CANCELED) {
            finishWithSuccess(cancelledResult());
            return;
        }
        if (resultCode != Activity.RESULT_OK) {
            finishWithError("SCAN_FAILED", "The scanner returned result code " + resultCode, null);
            return;
        }

        final GmsDocumentScanningResult scanningResult =
                GmsDocumentScanningResult.fromActivityResultIntent(intent);
        if (scanningResult == null) {
            finishWithError("EMPTY_RESULT", "The scanner did not return a result.", null);
            return;
        }

        final ScanOptions options;
        synchronized (stateLock) {
            options = pendingOptions;
        }
        cordova.getThreadPool().execute(() -> persistResult(scanningResult, options));
    }

    private void persistResult(GmsDocumentScanningResult scan, ScanOptions options) {
        String sessionId = UUID.randomUUID().toString();
        File sessionDirectory = new File(cacheRoot(), sessionId);
        if (!sessionDirectory.mkdirs() && !sessionDirectory.isDirectory()) {
            finishWithError("FILE_WRITE_FAILED", "Unable to create scanner cache directory.", null);
            return;
        }

        try {
            JSONObject response = baseSuccessResult(sessionId);
            JSONArray pagesJson = new JSONArray();
            List<GmsDocumentScanningResult.Page> pages = scan.getPages();

            if (pages != null && options.wantsJpeg) {
                int pageIndex = 0;
                for (GmsDocumentScanningResult.Page page : pages) {
                    if (pageIndex >= options.maxPages) {
                        break;
                    }
                    File destination = new File(
                            sessionDirectory,
                            String.format(Locale.US, "page-%03d.jpg", pageIndex + 1));
                    copyUri(page.getImageUri(), destination);
                    pagesJson.put(pageResult(destination, pageIndex));
                    pageIndex++;
                }
            }

            response.put("pages", pagesJson);
            response.put("pageCount", pagesJson.length() > 0
                    ? pagesJson.length()
                    : scan.getPdf() != null ? scan.getPdf().getPageCount() : 0);

            if (options.wantsPdf && scan.getPdf() != null) {
                File destination = new File(sessionDirectory, "document.pdf");
                copyUri(scan.getPdf().getUri(), destination);
                JSONObject pdf = new JSONObject();
                pdf.put("uri", Uri.fromFile(destination).toString());
                pdf.put("mimeType", "application/pdf");
                pdf.put("pageCount", scan.getPdf().getPageCount());
                response.put("pdf", pdf);
            } else {
                response.put("pdf", JSONObject.NULL);
            }

            finishWithSuccess(response);
        } catch (Exception exception) {
            deleteRecursively(sessionDirectory);
            finishWithError("FILE_WRITE_FAILED", safeMessage(exception), exception);
        }
    }

    private JSONObject pageResult(File file, int index) throws JSONException {
        BitmapFactory.Options dimensions = new BitmapFactory.Options();
        dimensions.inJustDecodeBounds = true;
        BitmapFactory.decodeFile(file.getAbsolutePath(), dimensions);

        JSONObject page = new JSONObject();
        page.put("index", index);
        page.put("uri", Uri.fromFile(file).toString());
        page.put("mimeType", "image/jpeg");
        page.put("width", Math.max(0, dimensions.outWidth));
        page.put("height", Math.max(0, dimensions.outHeight));
        return page;
    }

    private JSONObject capabilities() {
        JSONObject result = new JSONObject();
        try {
            boolean apiSupported = Build.VERSION.SDK_INT >= MINIMUM_API_LEVEL;
            boolean memorySupported = totalMemoryBytes() >= MINIMUM_RAM_BYTES;
            result.put("available", apiSupported && memorySupported);
            result.put("platform", "android");
            result.put("engine", "mlkit-document-scanner");
            result.put("singlePageAutoStop", true);
            result.put("multiPage", true);
            result.put("galleryImport", true);
            result.put("jpegOutput", true);
            result.put("pdfOutput", true);
            result.put("fileRead", true);
            result.put("maxReadBytes", MAX_READ_BYTES);
            result.put("uiPageLimitEnforced", true);
            result.put("minimumApiLevel", MINIMUM_API_LEVEL);
            result.put("minimumRamMb", 1700);
            if (!apiSupported) {
                result.put("unavailableReason", "Android API 21 or newer is required.");
            } else if (!memorySupported) {
                result.put("unavailableReason", "At least 1.7 GB of RAM is required.");
            } else {
                result.put("unavailableReason", JSONObject.NULL);
            }
        } catch (JSONException ignored) {
            // All keys and values above are JSON-safe.
        }
        return result;
    }

    private void cleanup(JSONObject rawOptions, CallbackContext callbackContext) {
        JSONObject options = rawOptions == null ? new JSONObject() : rawOptions;
        String sessionId = options.optString("sessionId", "");
        int maxAgeHours = Math.max(1, Math.min(720, options.optInt("maxAgeHours", 24)));

        if (!sessionId.isEmpty() && !sessionId.matches("[A-Za-z0-9-]+")) {
            sendError(callbackContext, "INVALID_OPTIONS", "sessionId is invalid.", null);
            return;
        }

        cordova.getThreadPool().execute(() -> {
            int deleted = 0;
            File root = cacheRoot();
            if (sessionId.isEmpty()) {
                long threshold = System.currentTimeMillis() - maxAgeHours * 60L * 60L * 1000L;
                File[] sessions = root.listFiles();
                if (sessions != null) {
                    for (File session : sessions) {
                        if (session.lastModified() < threshold && deleteRecursively(session)) {
                            deleted++;
                        }
                    }
                }
            } else {
                File session = new File(root, sessionId);
                if (session.isDirectory() && deleteRecursively(session)) {
                    deleted = 1;
                }
            }

            JSONObject result = new JSONObject();
            try {
                result.put("deletedSessions", deleted);
            } catch (JSONException ignored) {
                // Integer values are JSON-safe.
            }
            callbackContext.success(result);
        });
    }

    private void readFile(JSONObject rawOptions, CallbackContext callbackContext) {
        JSONObject options = rawOptions == null ? new JSONObject() : rawOptions;
        String uriText = options.optString("uri", "").trim();
        int maxBytes = Math.max(
                1,
                Math.min(MAX_READ_BYTES, options.optInt("maxBytes", DEFAULT_MAX_READ_BYTES))
        );
        if (uriText.isEmpty()) {
            sendError(callbackContext, "INVALID_OPTIONS", "uri is required.", null);
            return;
        }

        cordova.getThreadPool().execute(() -> {
            try {
                Uri uri = Uri.parse(uriText);
                if (!"file".equalsIgnoreCase(uri.getScheme()) || uri.getPath() == null) {
                    throw new ScannerFileReadException(
                            "INVALID_OPTIONS",
                            "The scanner file URI is invalid."
                    );
                }

                File root = cacheRoot().getCanonicalFile();
                File file = new File(uri.getPath()).getCanonicalFile();
                String rootPrefix = root.getPath() + File.separator;
                if (!file.getPath().startsWith(rootPrefix)) {
                    throw new ScannerFileReadException(
                            "FILE_ACCESS_DENIED",
                            "The requested file is outside the scanner cache."
                    );
                }
                if (!file.isFile()) {
                    throw new ScannerFileReadException(
                            "FILE_NOT_FOUND",
                            "The scanner file no longer exists."
                    );
                }

                long length = file.length();
                if (length > maxBytes || length > Integer.MAX_VALUE) {
                    throw new ScannerFileReadException(
                            "FILE_TOO_LARGE",
                            "The scanner file exceeds the requested maximum size."
                    );
                }

                byte[] data = new byte[(int) length];
                try (FileInputStream input = new FileInputStream(file)) {
                    int offset = 0;
                    while (offset < data.length) {
                        int count = input.read(data, offset, data.length - offset);
                        if (count < 0) {
                            throw new IOException("Unexpected end of scanner file.");
                        }
                        offset += count;
                    }
                }

                PluginResult result = new PluginResult(PluginResult.Status.OK, data);
                callbackContext.sendPluginResult(result);
            } catch (ScannerFileReadException exception) {
                sendError(callbackContext, exception.code, exception.getMessage(), exception);
            } catch (IOException | SecurityException exception) {
                sendError(
                        callbackContext,
                        "FILE_READ_FAILED",
                        safeMessage(exception),
                        exception
                );
            }
        });
    }

    private void copyUri(Uri source, File destination) throws IOException {
        try (InputStream input = cordova.getContext().getContentResolver().openInputStream(source);
             FileOutputStream output = new FileOutputStream(destination)) {
            if (input == null) {
                throw new IOException("Unable to open scanner result URI.");
            }
            byte[] buffer = new byte[32 * 1024];
            int count;
            while ((count = input.read(buffer)) != -1) {
                output.write(buffer, 0, count);
            }
            output.flush();
        }
    }

    private File cacheRoot() {
        File root = new File(cordova.getContext().getCacheDir(), CACHE_DIRECTORY);
        if (!root.exists()) {
            root.mkdirs();
        }
        return root;
    }

    private long totalMemoryBytes() {
        ActivityManager manager =
                (ActivityManager) cordova.getContext().getSystemService(Context.ACTIVITY_SERVICE);
        if (manager == null) {
            return Long.MAX_VALUE;
        }
        ActivityManager.MemoryInfo info = new ActivityManager.MemoryInfo();
        manager.getMemoryInfo(info);
        return info.totalMem;
    }

    private JSONObject baseSuccessResult(String sessionId) throws JSONException {
        JSONObject result = new JSONObject();
        result.put("status", "success");
        result.put("platform", "android");
        result.put("engine", "mlkit-document-scanner");
        result.put("sessionId", sessionId);
        result.put("uiPageLimitEnforced", true);
        return result;
    }

    private JSONObject cancelledResult() {
        JSONObject result = new JSONObject();
        try {
            result.put("status", "cancelled");
            result.put("platform", "android");
            result.put("engine", "mlkit-document-scanner");
            result.put("sessionId", JSONObject.NULL);
            result.put("pageCount", 0);
            result.put("pages", new JSONArray());
            result.put("pdf", JSONObject.NULL);
            result.put("uiPageLimitEnforced", true);
        } catch (JSONException ignored) {
            // All values above are JSON-safe.
        }
        return result;
    }

    private void finishWithSuccess(JSONObject result) {
        CallbackContext callback = takePendingCallback();
        if (callback != null) {
            callback.success(result);
        }
    }

    private void finishWithError(String code, String message, Throwable exception) {
        CallbackContext callback = takePendingCallback();
        if (callback != null) {
            sendError(callback, code, message, exception);
        }
    }

    private CallbackContext takePendingCallback() {
        synchronized (stateLock) {
            CallbackContext callback = pendingCallback;
            pendingCallback = null;
            pendingOptions = null;
            return callback;
        }
    }

    private void sendError(
            CallbackContext callback,
            String code,
            String message,
            Throwable exception
    ) {
        JSONObject error = new JSONObject();
        try {
            error.put("code", code);
            error.put("message", message == null || message.trim().isEmpty()
                    ? "Unknown scanner error."
                    : message);
            if (exception != null) {
                error.put("nativeType", exception.getClass().getSimpleName());
            }
        } catch (JSONException ignored) {
            callback.error(code + ": " + message);
            return;
        }
        callback.error(error);
    }

    private boolean deleteRecursively(File target) {
        if (target == null || !target.exists()) {
            return false;
        }
        if (target.isDirectory()) {
            File[] children = target.listFiles();
            if (children != null) {
                for (File child : children) {
                    deleteRecursively(child);
                }
            }
        }
        return target.delete();
    }

    private static String safeMessage(Throwable exception) {
        if (exception == null) {
            return "Unknown scanner error.";
        }
        String message = exception.getMessage();
        return message == null || message.trim().isEmpty()
                ? exception.getClass().getSimpleName()
                : message;
    }

    private static final class ScannerFileReadException extends IOException {
        final String code;

        ScannerFileReadException(String code, String message) {
            super(message);
            this.code = code;
        }
    }

    private static final class ScanOptions {
        final boolean allowGallery;
        final int maxPages;
        final boolean wantsJpeg;
        final boolean wantsPdf;
        final int scannerMode;

        private ScanOptions(
                boolean allowGallery,
                int maxPages,
                boolean wantsJpeg,
                boolean wantsPdf,
                int scannerMode
        ) {
            this.allowGallery = allowGallery;
            this.maxPages = maxPages;
            this.wantsJpeg = wantsJpeg;
            this.wantsPdf = wantsPdf;
            this.scannerMode = scannerMode;
        }

        static ScanOptions from(JSONObject raw) throws JSONException {
            JSONObject options = raw == null ? new JSONObject() : raw;
            int maxPages = Math.max(1, Math.min(50, options.optInt("maxPages", 1)));
            boolean wantsJpeg = false;
            boolean wantsPdf = false;
            JSONArray formats = options.optJSONArray("resultFormats");
            if (formats == null || formats.length() == 0) {
                wantsJpeg = true;
            } else {
                for (int index = 0; index < formats.length(); index++) {
                    String format = formats.getString(index);
                    if ("jpeg".equals(format)) {
                        wantsJpeg = true;
                    } else if ("pdf".equals(format)) {
                        wantsPdf = true;
                    } else {
                        throw new IllegalArgumentException("Unsupported result format: " + format);
                    }
                }
            }

            int scannerMode;
            switch (options.optString("scannerMode", "full")) {
                case "base":
                    scannerMode = GmsDocumentScannerOptions.SCANNER_MODE_BASE;
                    break;
                case "base_with_filter":
                    scannerMode = GmsDocumentScannerOptions.SCANNER_MODE_BASE_WITH_FILTER;
                    break;
                case "full":
                    scannerMode = GmsDocumentScannerOptions.SCANNER_MODE_FULL;
                    break;
                default:
                    throw new IllegalArgumentException("Unsupported scannerMode.");
            }

            return new ScanOptions(
                    options.optBoolean("allowGallery", false),
                    maxPages,
                    wantsJpeg,
                    wantsPdf,
                    scannerMode);
        }
    }
}
