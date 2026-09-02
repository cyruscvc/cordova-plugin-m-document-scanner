/* global cordova */

var exec = require('cordova/exec');
var optionTools = require(
    'cordova-plugin-m-document-scanner.MDocumentScannerOptions'
);

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

function readFile(options, onSuccess, onError) {
    var source = typeof options === 'string' ? { uri: options } : (options || {});
    var uri = typeof source.uri === 'string' ? source.uri.trim() : '';
    var maxBytes = source.maxBytes == null ? 25 * 1024 * 1024 : Number(source.maxBytes);

    if (!uri) {
        callback(onError)({
            code: 'INVALID_OPTIONS',
            message: 'uri is required.'
        });
        return;
    }
    if (!Number.isFinite(maxBytes) || maxBytes < 1 || maxBytes > 50 * 1024 * 1024) {
        callback(onError)({
            code: 'INVALID_OPTIONS',
            message: 'maxBytes must be between 1 and 52428800.'
        });
        return;
    }

    exec(
        callback(onSuccess),
        callback(onError),
        'MDocumentScanner',
        'readFile',
        [{ uri: uri, maxBytes: Math.floor(maxBytes) }]
    );
}

module.exports = {
    scan: scan,
    getCapabilities: getCapabilities,
    cleanup: cleanup,
    readFile: readFile
};
