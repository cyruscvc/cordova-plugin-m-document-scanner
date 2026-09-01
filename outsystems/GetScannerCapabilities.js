var plugin = window.cordova &&
    cordova.plugins &&
    cordova.plugins.mDocumentScanner;

function fail(error) {
    var value = error || {};
    $parameters.IsSuccess = false;
    $parameters.ResultJson = "";
    $parameters.ErrorCode = value.code || "CAPABILITIES_FAILED";
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

plugin.getCapabilities(
    function (result) {
        $parameters.IsSuccess = true;
        $parameters.ResultJson = JSON.stringify(result || {});
        $parameters.ErrorCode = "";
        $parameters.ErrorMessage = "";
        $resolve();
    },
    fail
);
