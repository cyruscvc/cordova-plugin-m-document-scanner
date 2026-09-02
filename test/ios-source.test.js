'use strict';

var test = require('node:test');
var assert = require('node:assert/strict');
var fs = require('node:fs');
var path = require('node:path');

var root = path.resolve(__dirname, '..');
var iosRoot = path.join(root, 'src', 'ios');
var pluginSource = fs.readFileSync(path.join(iosRoot, 'MDocumentScanner.swift'), 'utf8');
var pluginXml = fs.readFileSync(path.join(root, 'plugin.xml'), 'utf8');
var weScanRoot = path.join(iosRoot, 'MDWeScan');

function swiftFiles(directory) {
    return fs.readdirSync(directory, { withFileTypes: true }).flatMap(function (entry) {
        var target = path.join(directory, entry.name);
        return entry.isDirectory()
            ? swiftFiles(target)
            : entry.name.endsWith('.swift') ? [target] : [];
    });
}

test('MABS controller traversal is explicitly typed as UIViewController', function () {
    assert.match(
        pluginSource,
        /var controller:\s*UIViewController\s*=\s*viewController!/
    );
});

test('iOS single-page mode uses the namespaced WeScan engine', function () {
    assert.match(pluginSource, /activeEngine\s*=\s*"wescan"/);
    assert.match(pluginSource, /MDWImageScannerController\(delegate:\s*self\)/);
    assert.match(pluginSource, /MDWCaptureSession\.current\.isAutoScanEnabled/);
    assert.doesNotMatch(pluginXml, /MDSinglePageScannerViewController\.swift/);
});

test('all vendored WeScan Swift sources are namespaced and declared', function () {
    var files = swiftFiles(weScanRoot);
    assert.ok(files.length >= 30);
    files.forEach(function (file) {
        var relative = path.relative(root, file).split(path.sep).join('/');
        assert.match(pluginXml, new RegExp(
            '<source-file src="' + relative.replace(/[.*+?^$\{\}()|[\]\\]/g, '\\$&') + '"'
        ));
    });

    var combined = files.map(function (file) {
        return fs.readFileSync(file, 'utf8');
    }).join('\n');
    assert.match(combined, /MDWImageScannerController/);
    assert.match(combined, /MDWRectangleFeaturesFunnel/);
    assert.doesNotMatch(combined, /\bclass\s+ImageScannerController\b/);
    assert.doesNotMatch(combined, /\bclass\s+CaptureSessionManager\b/);
});

test('iOS capture is bounded and uses supported photo prioritization', function () {
    var manager = fs.readFileSync(
        path.join(weScanRoot, 'Scan', 'CaptureSessionManager.swift'),
        'utf8'
    );
    assert.match(manager, /mdwDownsampledImage\(data:\s*imageData,\s*maxDimension:\s*3500\)/);
    assert.match(manager, /maxPhotoQualityPrioritization\s*=\s*\.balanced/);
    assert.match(manager, /photoQualityPrioritization\s*=\s*\.balanced/);
    assert.doesNotMatch(manager, /photoQualityPrioritization\s*=\s*\.quality/);
});

test('iOS downsampling preserves EXIF orientation for crop-quad mapping', function () {
    var imageUtils = fs.readFileSync(
        path.join(weScanRoot, 'Extensions', 'UIImage+Utils.swift'),
        'utf8'
    );
    assert.match(imageUtils, /kCGImageSourceCreateThumbnailWithTransform:\s*false/);
    assert.match(imageUtils, /kCGImagePropertyOrientation/);
    assert.match(imageUtils, /UIImage\.Orientation\(mdwExifOrientation:/);
    assert.doesNotMatch(
        imageUtils,
        /return UIImage\(cgImage:\s*image,\s*scale:\s*1,\s*orientation:\s*\.up\)/
    );
});

test('iOS gallery and OCR-compatible URI contract remain available', function () {
    assert.match(pluginSource, /UIImagePickerControllerDelegate/);
    assert.match(pluginSource, /mdwPreparedImage\(maxDimension:\s*3500\)/);
    assert.match(pluginSource, /complete\(images:\s*\[image\],\s*uiPageLimitEnforced:\s*true\)/);
});

test('iOS live detection uses branded stability feedback tied to auto capture', function () {
    var quadView = fs.readFileSync(
        path.join(weScanRoot, 'Common', 'QuadrilateralView.swift'),
        'utf8'
    );
    var funnel = fs.readFileSync(
        path.join(weScanRoot, 'Scan', 'RectangleFeaturesFunnel.swift'),
        'utf8'
    );
    var manager = fs.readFileSync(
        path.join(weScanRoot, 'Scan', 'CaptureSessionManager.swift'),
        'utf8'
    );
    var scanner = fs.readFileSync(
        path.join(weScanRoot, 'Scan', 'ScannerViewController.swift'),
        'utf8'
    );

    assert.match(quadView, /Mubadala teal used by the live document-detection overlay \(#7AC4BD\)/);
    assert.match(quadView, /stabilityGridLayer/);
    assert.match(quadView, /stabilityGridPath\(for quad:/);
    assert.match(quadView, /func updateAutoScanProgress\(_ progress: CGFloat, animated: Bool\)/);
    assert.match(funnel, /completion: \(MDWAddResult, MDWQuadrilateral, CGFloat\) -> Void/);
    assert.match(funnel, /A changed quadrilateral is a new stability attempt/);
    assert.match(manager, /didUpdateAutoScanProgress progress: CGFloat/);
    assert.match(manager, /resetAutoScanProgress\(\)/);
    assert.match(scanner, /configureForDocumentScanning\(\)/);
    assert.match(scanner, /quadView\.updateAutoScanProgress\(visibleProgress, animated: true\)/);
});
