'use strict';

var test = require('node:test');
var assert = require('node:assert/strict');
var options = require('../www/options');

test('single-page defaults are safe for receipts and business cards', function () {
    assert.deepEqual(options.normalizeScanOptions(), {
        captureMode: 'single',
        maxPages: 1,
        allowGallery: false,
        resultFormats: ['jpeg'],
        jpegQuality: 0.9,
        scannerMode: 'full',
        autoCapture: true,
        stabilityDurationMs: 1200,
        detectionConfidence: 0.8,
        minDocumentArea: 0.2
    });
});

test('multi-page options are bounded and formats are de-duplicated', function () {
    var result = options.normalizeScanOptions({
        captureMode: 'multi',
        maxPages: 999,
        resultFormats: ['jpeg', 'pdf', 'jpeg'],
        jpegQuality: 0.1,
        stabilityDurationMs: 100
    });
    assert.equal(result.maxPages, 50);
    assert.deepEqual(result.resultFormats, ['jpeg', 'pdf']);
    assert.equal(result.jpegQuality, 0.35);
    assert.equal(result.stabilityDurationMs, 500);
});

test('unknown modes and formats fail before opening native UI', function () {
    assert.throws(function () {
        options.normalizeScanOptions({ captureMode: 'continuous' });
    }, /captureMode/);
    assert.throws(function () {
        options.normalizeScanOptions({ resultFormats: ['png'] });
    }, /resultFormats/);
});

test('cleanup validates session identifiers and bounds age', function () {
    assert.deepEqual(options.normalizeCleanupOptions({ maxAgeHours: 900 }), {
        sessionId: '',
        maxAgeHours: 720
    });
    assert.throws(function () {
        options.normalizeCleanupOptions({ sessionId: 7 });
    }, /sessionId/);
});
