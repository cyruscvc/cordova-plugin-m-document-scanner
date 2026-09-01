var plugin = window.cordova &&
    cordova.plugins &&
    cordova.plugins.mDocumentScanner;

function fail(error) {
    var value = error || {};
    $parameters.IsSuccess = false;
    $parameters.IsCancelled = false;
    $parameters.ResultJson = "";
    $parameters.ErrorCode = value.code || "SCAN_FAILED";
    $parameters.ErrorMessage = value.message ||
        (typeof value === "string" ? value : JSON.stringify(value));
    $resolve();
}

if (!plugin) {
    fail({
        code: "PLUGIN_UNAVAILABLE",
        message: "M Document Scanner is unavailable. Install a newly generated native build."
    });
    return;
}

var resultFormats;
try {
    resultFormats = JSON.parse($parameters.ResultFormatsJson || "[\"jpeg\"]");
} catch (error) {
    fail({ code: "INVALID_OPTIONS", message: "ResultFormatsJson is not valid JSON." });
    return;
}

plugin.scan(
    {
        captureMode: $parameters.CaptureMode || "single",
        maxPages: $parameters.MaxPages,
        allowGallery: $parameters.AllowGallery,
        resultFormats: resultFormats,
        jpegQuality: Number($parameters.JpegQuality),
        scannerMode: $parameters.ScannerMode || "full",
        autoCapture: $parameters.AutoCapture,
        stabilityDurationMs: $parameters.StabilityDurationMs,
        detectionConfidence: Number($parameters.DetectionConfidence),
        minDocumentArea: Number($parameters.MinDocumentArea)
    },
    function (result) {
        result = result || {};
        $parameters.IsSuccess = result.status === "success";
        $parameters.IsCancelled = result.status === "cancelled";
        $parameters.ResultJson = JSON.stringify(result);
        $parameters.ErrorCode = "";
        $parameters.ErrorMessage = "";
        $resolve();
    },
    fail
);
