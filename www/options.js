'use strict';

var VALID_CAPTURE_MODES = ['single', 'multi'];
var VALID_FORMATS = ['jpeg', 'pdf'];
var VALID_SCANNER_MODES = ['base', 'base_with_filter', 'full'];

function plainObject(value) {
    return value && typeof value === 'object' && !Array.isArray(value) ? value : {};
}

function boundedNumber(value, fallback, minimum, maximum) {
    var number = Number(value);
    if (!Number.isFinite(number)) {
        return fallback;
    }
    return Math.min(maximum, Math.max(minimum, number));
}

function integer(value, fallback, minimum, maximum) {
    return Math.round(boundedNumber(value, fallback, minimum, maximum));
}

function enumValue(value, fallback, allowed, fieldName) {
    if (value === undefined || value === null || value === '') {
        return fallback;
    }
    if (allowed.indexOf(value) === -1) {
        throw new Error(fieldName + ' must be one of: ' + allowed.join(', '));
    }
    return value;
}

function formats(value) {
    var input = Array.isArray(value) ? value : value ? [value] : ['jpeg'];
    var output = [];
    input.forEach(function (format) {
        if (VALID_FORMATS.indexOf(format) === -1) {
            throw new Error('resultFormats may contain only jpeg and pdf');
        }
        if (output.indexOf(format) === -1) {
            output.push(format);
        }
    });
    if (output.length === 0) {
        throw new Error('resultFormats must contain at least one format');
    }
    return output;
}

function normalizeScanOptions(value) {
    var options = plainObject(value);
    var captureMode = enumValue(
        options.captureMode,
        'single',
        VALID_CAPTURE_MODES,
        'captureMode'
    );

    return {
        captureMode: captureMode,
        maxPages: captureMode === 'single'
            ? 1
            : integer(options.maxPages, 20, 1, 50),
        allowGallery: options.allowGallery === true,
        resultFormats: formats(options.resultFormats),
        jpegQuality: boundedNumber(options.jpegQuality, 0.9, 0.35, 1),
        scannerMode: enumValue(
            options.scannerMode,
            'full',
            VALID_SCANNER_MODES,
            'scannerMode'
        ),
        autoCapture: options.autoCapture !== false,
        stabilityDurationMs: integer(options.stabilityDurationMs, 1200, 500, 5000),
        detectionConfidence: boundedNumber(options.detectionConfidence, 0.8, 0.5, 1),
        minDocumentArea: boundedNumber(options.minDocumentArea, 0.2, 0.08, 0.9)
    };
}

function normalizeCleanupOptions(value) {
    var options = plainObject(value);
    if (options.sessionId !== undefined && typeof options.sessionId !== 'string') {
        throw new Error('sessionId must be a string');
    }
    return {
        sessionId: options.sessionId || '',
        maxAgeHours: integer(options.maxAgeHours, 24, 1, 720)
    };
}

module.exports = {
    normalizeScanOptions: normalizeScanOptions,
    normalizeCleanupOptions: normalizeCleanupOptions
};
