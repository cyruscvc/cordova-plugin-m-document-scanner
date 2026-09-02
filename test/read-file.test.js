'use strict';

var test = require('node:test');
var assert = require('node:assert/strict');
var fs = require('node:fs');
var path = require('node:path');
var vm = require('node:vm');

var root = path.resolve(__dirname, '..');
var bridgeSource = fs.readFileSync(
    path.join(root, 'www', 'MDocumentScanner.js'),
    'utf8'
);
var optionTools = require('../www/options');

function loadBridge(exec) {
    var bridgeModule = { exports: {} };
    vm.runInNewContext(bridgeSource, {
        module: bridgeModule,
        require: function (moduleId) {
            if (moduleId === 'cordova/exec') return exec;
            if (moduleId === 'cordova-plugin-m-document-scanner.MDocumentScannerOptions') {
                return optionTools;
            }
            throw new Error('Unexpected module: ' + moduleId);
        },
        Number: Number,
        Math: Math
    });
    return bridgeModule.exports;
}

test('readFile sends a bounded scanner URI request to the native service', function () {
    var invocation;
    var bridge = loadBridge(function (success, error, service, action, args) {
        invocation = { service: service, action: action, args: args };
    });

    bridge.readFile({
        uri: ' file:///cache/m-document-scanner/session/page-001.jpg ',
        maxBytes: 1024
    });

    assert.deepEqual(invocation, {
        service: 'MDocumentScanner',
        action: 'readFile',
        args: [{
            uri: 'file:///cache/m-document-scanner/session/page-001.jpg',
            maxBytes: 1024
        }]
    });
});

test('readFile rejects missing URIs before invoking native code', function () {
    var invoked = false;
    var received;
    var bridge = loadBridge(function () {
        invoked = true;
    });

    bridge.readFile({}, null, function (error) {
        received = error;
    });

    assert.equal(invoked, false);
    assert.equal(received.code, 'INVALID_OPTIONS');
});
