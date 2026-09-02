/* global cordova, $parameters, $resolve */
(function () {
    function finishError(error) {
        var value = error || {};
        $parameters.IsSuccess = false;
        $parameters.BinaryData = "";
        $parameters.Base64 = "";
        $parameters.MimeType = "";
        $parameters.FileName = "";
        $parameters.Size = 0;
        $parameters.ErrorCode = value.code || "FILE_READ_FAILED";
        $parameters.ErrorMessage = value.message ||
            (typeof value === "string" ? value : JSON.stringify(value));
        $resolve();
    }

    function fileNameFromUri(uri) {
        var clean = String(uri || "").split("?")[0].split("#")[0];
        var name = clean.substring(clean.lastIndexOf("/") + 1);
        try {
            return decodeURIComponent(name);
        } catch (_) {
            return name;
        }
    }

    function mimeTypeFromName(name) {
        var lower = String(name || "").toLowerCase();
        if (/\.jpe?g$/.test(lower)) return "image/jpeg";
        if (/\.png$/.test(lower)) return "image/png";
        if (/\.pdf$/.test(lower)) return "application/pdf";
        return "application/octet-stream";
    }

    function arrayBufferToBase64(value) {
        if (typeof value === "string") {
            return value.indexOf("base64,") >= 0
                ? value.substring(value.indexOf("base64,") + 7)
                : value;
        }

        var bytes;
        if (value instanceof ArrayBuffer) {
            bytes = new Uint8Array(value);
        } else if (ArrayBuffer.isView(value)) {
            bytes = new Uint8Array(value.buffer, value.byteOffset, value.byteLength);
        } else {
            throw new Error("The native plugin returned an unsupported binary value.");
        }

        var parts = [];
        var chunkSize = 0x8000;
        for (var offset = 0; offset < bytes.length; offset += chunkSize) {
            parts.push(String.fromCharCode.apply(
                null,
                bytes.subarray(offset, Math.min(offset + chunkSize, bytes.length))
            ));
        }
        return window.btoa(parts.join(""));
    }

    function byteLengthFromBase64(base64) {
        if (!base64) return 0;
        var padding = base64.endsWith("==") ? 2 : (base64.endsWith("=") ? 1 : 0);
        return Math.floor(base64.length * 3 / 4) - padding;
    }

    $parameters.IsSuccess = false;
    $parameters.BinaryData = "";
    $parameters.Base64 = "";
    $parameters.MimeType = "";
    $parameters.FileName = "";
    $parameters.Size = 0;
    $parameters.ErrorCode = "";
    $parameters.ErrorMessage = "";

    var plugin = window.cordova &&
        cordova.plugins &&
        cordova.plugins.mDocumentScanner;

    if (!plugin || typeof plugin.readFile !== "function") {
        finishError({
            code: "PLUGIN_UNAVAILABLE",
            message: "MDocumentScanner.readFile is unavailable. Install a newly generated native build."
        });
        return;
    }

    var uri = String($parameters.Uri || "").trim();
    var maxBytes = Number($parameters.MaxBytes);
    if (!Number.isFinite(maxBytes) || maxBytes < 1) {
        maxBytes = 25 * 1024 * 1024;
    }

    plugin.readFile(
        { uri: uri, maxBytes: Math.floor(maxBytes) },
        function (nativeValue) {
            try {
                var base64 = arrayBufferToBase64(nativeValue);
                var fileName = fileNameFromUri(uri);

                // O11 represents Binary Data parameters as Base64 strings inside
                // JavaScript nodes and converts this output back to Binary Data.
                $parameters.BinaryData = base64;
                $parameters.Base64 = $parameters.IncludeBase64 ? base64 : "";
                $parameters.MimeType = mimeTypeFromName(fileName);
                $parameters.FileName = fileName;
                $parameters.Size = byteLengthFromBase64(base64);
                $parameters.IsSuccess = true;
                $resolve();
            } catch (error) {
                finishError({
                    code: "BINARY_CONVERSION_FAILED",
                    message: error.message || String(error)
                });
            }
        },
        finishError
    );
}());
