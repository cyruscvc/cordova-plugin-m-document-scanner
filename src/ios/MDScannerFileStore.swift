import Foundation
import UIKit

enum MDScannerFileStoreError: LocalizedError {
    case cacheUnavailable
    case jpegEncodingFailed
    case invalidSessionIdentifier
    case invalidFileURI
    case fileAccessDenied
    case fileNotFound
    case fileTooLarge
    case fileReadFailed

    var code: String {
        switch self {
        case .invalidFileURI:
            return "INVALID_OPTIONS"
        case .fileAccessDenied:
            return "FILE_ACCESS_DENIED"
        case .fileNotFound:
            return "FILE_NOT_FOUND"
        case .fileTooLarge:
            return "FILE_TOO_LARGE"
        case .fileReadFailed:
            return "FILE_READ_FAILED"
        default:
            return "FILE_READ_FAILED"
        }
    }

    var errorDescription: String? {
        switch self {
        case .cacheUnavailable:
            return "Unable to create the scanner cache directory."
        case .jpegEncodingFailed:
            return "Unable to encode a scanned page as JPEG."
        case .invalidSessionIdentifier:
            return "The scanner session identifier is invalid."
        case .invalidFileURI:
            return "The scanner file URI is invalid."
        case .fileAccessDenied:
            return "The requested file is outside the scanner cache."
        case .fileNotFound:
            return "The scanner file no longer exists."
        case .fileTooLarge:
            return "The scanner file exceeds the requested maximum size."
        case .fileReadFailed:
            return "The scanner file could not be read."
        }
    }
}

final class MDScannerFileStore {
    static let shared = MDScannerFileStore()

    private let fileManager = FileManager.default
    private let directoryName = "m-document-scanner"

    private init() {}

    func persist(
        images: [UIImage],
        wantsJPEG: Bool,
        wantsPDF: Bool,
        jpegQuality: CGFloat,
        platform: String,
        engine: String,
        uiPageLimitEnforced: Bool
    ) throws -> [String: Any] {
        let sessionId = UUID().uuidString.lowercased()
        let sessionDirectory = try createSessionDirectory(sessionId: sessionId)

        do {
            var pageResults: [[String: Any]] = []
            if wantsJPEG {
                for (index, image) in images.enumerated() {
                    guard let data = image.jpegData(compressionQuality: jpegQuality) else {
                        throw MDScannerFileStoreError.jpegEncodingFailed
                    }
                    let url = sessionDirectory.appendingPathComponent(
                        String(format: "page-%03d.jpg", index + 1)
                    )
                    try data.write(to: url, options: .atomic)
                    pageResults.append([
                        "index": index,
                        "uri": url.absoluteString,
                        "mimeType": "image/jpeg",
                        "width": Int(image.size.width * image.scale),
                        "height": Int(image.size.height * image.scale)
                    ])
                }
            }

            var pdfResult: Any = NSNull()
            if wantsPDF {
                let pdfURL = sessionDirectory.appendingPathComponent("document.pdf")
                try makePDF(images: images).write(to: pdfURL, options: .atomic)
                pdfResult = [
                    "uri": pdfURL.absoluteString,
                    "mimeType": "application/pdf",
                    "pageCount": images.count
                ]
            }

            return [
                "status": "success",
                "platform": platform,
                "engine": engine,
                "sessionId": sessionId,
                "pageCount": images.count,
                "pages": pageResults,
                "pdf": pdfResult,
                "uiPageLimitEnforced": uiPageLimitEnforced
            ]
        } catch {
            try? fileManager.removeItem(at: sessionDirectory)
            throw error
        }
    }

    func cleanup(sessionId: String, maxAgeHours: Int) throws -> Int {
        let root = try cacheRoot()
        if !sessionId.isEmpty {
            guard sessionId.range(of: "^[A-Za-z0-9-]+$", options: .regularExpression) != nil else {
                throw MDScannerFileStoreError.invalidSessionIdentifier
            }
            let target = root.appendingPathComponent(sessionId, isDirectory: true)
            guard fileManager.fileExists(atPath: target.path) else { return 0 }
            try fileManager.removeItem(at: target)
            return 1
        }

        let threshold = Date().addingTimeInterval(-Double(maxAgeHours) * 3600)
        let entries = try fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )
        var deleted = 0
        for entry in entries {
            let values = try? entry.resourceValues(forKeys: [.contentModificationDateKey])
            if (values?.contentModificationDate ?? .distantPast) < threshold {
                try? fileManager.removeItem(at: entry)
                deleted += 1
            }
        }
        return deleted
    }

    func readFile(uri: String, maxBytes: Int) throws -> Data {
        guard let requestedURL = URL(string: uri), requestedURL.isFileURL else {
            throw MDScannerFileStoreError.invalidFileURI
        }

        let root = try cacheRoot().standardizedFileURL.resolvingSymlinksInPath()
        let file = requestedURL.standardizedFileURL.resolvingSymlinksInPath()
        let rootPrefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        guard file.path.hasPrefix(rootPrefix) else {
            throw MDScannerFileStoreError.fileAccessDenied
        }

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: file.path, isDirectory: &isDirectory),
              !isDirectory.boolValue else {
            throw MDScannerFileStoreError.fileNotFound
        }

        let attributes = try fileManager.attributesOfItem(atPath: file.path)
        let size = (attributes[.size] as? NSNumber)?.intValue ?? 0
        guard size <= maxBytes else {
            throw MDScannerFileStoreError.fileTooLarge
        }

        do {
            return try Data(contentsOf: file, options: .mappedIfSafe)
        } catch {
            throw MDScannerFileStoreError.fileReadFailed
        }
    }

    private func cacheRoot() throws -> URL {
        guard let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            throw MDScannerFileStoreError.cacheUnavailable
        }
        let root = caches.appendingPathComponent(directoryName, isDirectory: true)
        if !fileManager.fileExists(atPath: root.path) {
            try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        }
        return root
    }

    private func createSessionDirectory(sessionId: String) throws -> URL {
        let directory = try cacheRoot().appendingPathComponent(sessionId, isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: false)
        return directory
    }

    private func makePDF(images: [UIImage]) -> Data {
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextCreator as String: "M Document Scanner",
            kCGPDFContextTitle as String: "Scanned Document"
        ]
        let renderer = UIGraphicsPDFRenderer(
            bounds: CGRect(x: 0, y: 0, width: 612, height: 792),
            format: format
        )
        return renderer.pdfData { context in
            for image in images {
                let pageRect = CGRect(origin: .zero, size: image.size)
                context.beginPage(withBounds: pageRect, pageInfo: [:])
                image.draw(in: pageRect)
            }
        }
    }
}
