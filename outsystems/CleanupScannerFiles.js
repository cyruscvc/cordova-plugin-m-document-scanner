var plugin = window.cordova &&
    cordova.plugins &&
    cordova.plugins.mDocumentScanner;

function fail(error) {
    var value = error || {};
    $parameters.IsSuccess = false;
    $parameters.DeletedSessions = 0;
    $parameters.ErrorCode = value.code || "CLEANUP_FAILED";
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

plugin.cleanup(
    {
        sessionId: $parameters.SessionId || "",
        maxAgeHours: $parameters.MaxAgeHours || 24
    },
    function (result) {
        $parameters.IsSuccess = true;
        $parameters.DeletedSessions = Number((result || {}).deletedSessions || 0);
        $parameters.ErrorCode = "";
        $parameters.ErrorMessage = "";
        $resolve();
    },
    fail
);
