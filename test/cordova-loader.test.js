'use strict';

var test = require('node:test');
var assert = require('node:assert/strict');
var fs = require('node:fs');
var path = require('node:path');
var vm = require('node:vm');

var pluginRoot = path.resolve(__dirname, '..');
var bridgeSource = fs.readFileSync(
    path.join(pluginRoot, 'www', 'MDocumentScanner.js'),
    'utf8'
);

test('Cordova can load the clobbered scanner bridge at application startup', function () {
    var bridgeModule = { exports: {} };
    var optionTools = require('../www/options');
    var requestedModules = [];

    function cordovaRequire(moduleId) {
        requestedModules.push(moduleId);
        if (moduleId === 'cordova/exec') {
            return function () {};
        }
        if (moduleId === 'cordova-plugin-m-document-scanner.MDocumentScannerOptions') {
            return optionTools;
        }
        throw new Error('Module not found: ' + moduleId);
    }

    vm.runInNewContext(bridgeSource, {
        module: bridgeModule,
        require: cordovaRequire
    });

    assert.deepEqual(requestedModules, [
        'cordova/exec',
        'cordova-plugin-m-document-scanner.MDocumentScannerOptions'
    ]);
    assert.equal(typeof bridgeModule.exports.scan, 'function');
    assert.equal(typeof bridgeModule.exports.getCapabilities, 'function');
    assert.equal(typeof bridgeModule.exports.cleanup, 'function');
});

test('the options helper is registered without an automatic runs directive', function () {
    var pluginXml = fs.readFileSync(path.join(pluginRoot, 'plugin.xml'), 'utf8');
    var helperBlock = pluginXml.match(
        /<js-module src="www\/options\.js"[\s\S]*?<\/js-module>/
    );

    assert.ok(helperBlock, 'options helper js-module must be declared');
    assert.doesNotMatch(helperBlock[0], /<runs\s*\/>/);
});
