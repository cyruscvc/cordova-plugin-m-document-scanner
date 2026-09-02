'use strict';

var test = require('node:test');
var assert = require('node:assert/strict');
var fs = require('node:fs');
var path = require('node:path');
var vm = require('node:vm');

var source = fs.readFileSync(
    path.resolve(__dirname, '..', 'outsystems', 'ReadScannerFile.js'),
    'utf8'
);

test('ReadScannerFile exposes valid O11 Binary Data and optional Base64', function () {
    var parameters = {
        Uri: 'file:///cache/m-document-scanner/session/page-001.jpg',
        IncludeBase64: true,
        MaxBytes: 26214400
    };
    var resolved = 0;
    var plugin = {
        readFile: function (options, success) {
            assert.equal(options.uri, parameters.Uri);
            success(new Uint8Array([0xFF, 0xD8, 0xFF, 0xD9]).buffer);
        }
    };
    var cordova = { plugins: { mDocumentScanner: plugin } };

    vm.runInNewContext(source, {
        window: {
            cordova: cordova,
            btoa: function (binary) {
                return Buffer.from(binary, 'binary').toString('base64');
            }
        },
        cordova: cordova,
        $parameters: parameters,
        $resolve: function () { resolved++; },
        ArrayBuffer: ArrayBuffer,
        Uint8Array: Uint8Array,
        Number: Number,
        Math: Math,
        String: String,
        JSON: JSON,
        Buffer: Buffer
    });

    assert.equal(resolved, 1);
    assert.equal(parameters.IsSuccess, true);
    assert.equal(parameters.BinaryData, '/9j/2Q==');
    assert.equal(parameters.Base64, '/9j/2Q==');
    assert.equal(parameters.MimeType, 'image/jpeg');
    assert.equal(parameters.FileName, 'page-001.jpg');
    assert.equal(parameters.Size, 4);
});

test('ReadScannerFile omits the duplicate Base64 output by default', function () {
    var parameters = {
        Uri: 'file:///cache/m-document-scanner/session/document.pdf',
        IncludeBase64: false,
        MaxBytes: 26214400
    };
    var cordova = {
        plugins: {
            mDocumentScanner: {
                readFile: function (options, success) {
                    success(new Uint8Array([1, 2, 3]).buffer);
                }
            }
        }
    };

    vm.runInNewContext(source, {
        window: {
            cordova: cordova,
            btoa: function (binary) {
                return Buffer.from(binary, 'binary').toString('base64');
            }
        },
        cordova: cordova,
        $parameters: parameters,
        $resolve: function () {},
        ArrayBuffer: ArrayBuffer,
        Uint8Array: Uint8Array,
        Number: Number,
        Math: Math,
        String: String,
        JSON: JSON,
        Buffer: Buffer
    });

    assert.equal(parameters.BinaryData, 'AQID');
    assert.equal(parameters.Base64, '');
    assert.equal(parameters.MimeType, 'application/pdf');
    assert.equal(parameters.Size, 3);
});
