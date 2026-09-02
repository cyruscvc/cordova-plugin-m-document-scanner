'use strict';

var test = require('node:test');
var assert = require('node:assert/strict');
var fs = require('node:fs');
var path = require('node:path');

var iosRoot = path.resolve(__dirname, '..', 'src', 'ios');

test('MABS controller traversal is explicitly typed as UIViewController', function () {
    var source = fs.readFileSync(path.join(iosRoot, 'MDocumentScanner.swift'), 'utf8');

    assert.match(
        source,
        /var controller:\s*UIViewController\s*=\s*viewController!/
    );
});

test('single-page scanner uses the supported activity indicator style', function () {
    var source = fs.readFileSync(
        path.join(iosRoot, 'MDSinglePageScannerViewController.swift'),
        'utf8'
    );

    assert.match(source, /UIActivityIndicatorView\(style:\s*\.large\)/);
    assert.doesNotMatch(source, /\.whiteLarge/);
});
