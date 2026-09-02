'use strict';

var test = require('node:test');
var assert = require('node:assert/strict');
var fs = require('node:fs');
var path = require('node:path');

var root = path.resolve(__dirname, '..');
var iosPlugin = fs.readFileSync(path.join(root, 'src', 'ios', 'MDocumentScanner.swift'), 'utf8');
var iosStore = fs.readFileSync(path.join(root, 'src', 'ios', 'MDScannerFileStore.swift'), 'utf8');
var android = fs.readFileSync(path.join(root, 'src', 'android', 'MDocumentScanner.java'), 'utf8');

test('iOS readFile returns an ArrayBuffer and restricts reads to scanner cache', function () {
    assert.match(iosPlugin, /@objc\(readFile:\)/);
    assert.match(iosPlugin, /messageAsArrayBuffer:\s*data/);
    assert.match(iosStore, /resolvingSymlinksInPath\(\)/);
    assert.match(iosStore, /file\.path\.hasPrefix\(rootPrefix\)/);
    assert.match(iosStore, /MDScannerFileStoreError\.fileAccessDenied/);
});

test('Android readFile returns bytes and restricts canonical paths', function () {
    assert.match(android, /case "readFile":/);
    assert.match(android, /new PluginResult\(PluginResult\.Status\.OK, data\)/);
    assert.match(android, /getCanonicalFile\(\)/);
    assert.match(android, /file\.getPath\(\)\.startsWith\(rootPrefix\)/);
    assert.match(android, /"FILE_ACCESS_DENIED"/);
});
