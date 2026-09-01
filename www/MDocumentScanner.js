/* global cordova */

var exec = require('cordova/exec');
var optionTools = require('./options');

function callback(value) {
    return typeof value === 'function' ? value : function () {};
}

function scan(options, onSuccess, onError) {
    var normalized;
    try {
        normalized = optionTools.normalizeScanOptions(options);
    } catch (error) {
        callback(onError)({
            code: 'INVALID_OPTIONS',
            message: error.message || String(error)
        });
        return;
    }

    exec(callback(onSuccess), callback(onError), 'MDocumentScanner', 'scan', [normalized]);
}

function getCapabilities(onSuccess, onError) {
    exec(callback(onSuccess), callback(onError), 'MDocumentScanner', 'getCapabilities', []);
}

function cleanup(options, onSuccess, onError) {
    var normalized;
    try {
        normalized = optionTools.normalizeCleanupOptions(options);
    } catch (error) {
        callback(onError)({
            code: 'INVALID_OPTIONS',
            message: error.message || String(error)
        });
        return;
    }

    exec(callback(onSuccess), callback(onError), 'MDocumentScanner', 'cleanup', [normalized]);
}

module.exports = {
    scan: scan,
    getCapabilities: getCapabilities,
    cleanup: cleanup
};
