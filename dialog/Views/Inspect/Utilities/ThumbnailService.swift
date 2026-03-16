//
//  ThumbnailService.swift
//  dialog
//
//  Created by Henry Stamerjohann, Declarative IT GmbH, 14/03/2026
//
//  Generates downsampled thumbnails for wallpaper picker images
//  Uses CGImageSource to downsample during decode — full image never loaded into memory
//

import AppKit

@MainActor
class ThumbnailService: ObservableObject {
    static let shared = ThumbnailService()

    @Published var thumbnails: [String: NSImage] = [:]

    private let cacheDir = "/var/tmp/dialog-thumbnails"
    private let maxPixelSize: Int = 384
    private let jpegQuality: CGFloat = 0.85

    private init() {
        try? FileManager.default.createDirectory(atPath: cacheDir, withIntermediateDirectories: true)
    }

    // MARK: - Sync Lookup

    /// Returns cached thumbnail (memory or disk), nil if not yet generated
    func thumbnail(for path: String) -> NSImage? {
        if let cached = thumbnails[path] {
            return cached
        }
        // Check disk cache
        let diskPath = diskCachePath(for: path)
        guard FileManager.default.fileExists(atPath: diskPath),
              !isStale(source: path, cache: diskPath),
              let image = NSImage(contentsOfFile: diskPath) else {
            return nil
        }
        // Promote to memory cache
        thumbnails[path] = image
        return image
    }

    // MARK: - Async Generation

    /// Generate a single thumbnail if not already cached
    func loadThumbnail(for path: String) async {
        // Already in memory cache
        if thumbnails[path] != nil { return }

        let diskPath = diskCachePath(for: path)

        // Try disk cache first
        if FileManager.default.fileExists(atPath: diskPath),
           !isStale(source: path, cache: diskPath),
           let diskImage = NSImage(contentsOfFile: diskPath) {
            thumbnails[path] = diskImage
            return
        }

        // Generate via CGImageSource downsample on background thread
        let thumb = await Task.detached(priority: .userInitiated) { [maxPixelSize, jpegQuality] in
            guard let image = Self.downsample(path: path, maxPixelSize: maxPixelSize) else { return nil as NSImage? }
            Self.saveToDisk(image: image, at: diskPath, quality: jpegQuality)
            return image
        }.value

        if let thumb {
            thumbnails[path] = thumb
        }
    }

    /// Batch preload thumbnails for all provided paths
    func preloadThumbnails(for paths: [String]) {
        Task {
            for path in paths {
                if thumbnails[path] != nil { continue }
                await loadThumbnail(for: path)
            }
        }
    }

    // MARK: - Core Downsample (static, thread-safe)

    private nonisolated static func downsample(path: String, maxPixelSize: Int) -> NSImage? {
        let url = URL(fileURLWithPath: path)
        let sourceOptions: [CFString: Any] = [
            kCGImageSourceShouldCache: false
        ]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions as CFDictionary) else {
            return nil
        }

        let downsampleOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, downsampleOptions as CFDictionary) else {
            return nil
        }

        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    // MARK: - Disk Cache

    private nonisolated func diskCachePath(for sourcePath: String) -> String {
        let hash = sourcePath.utf8.reduce(into: UInt64(5381)) { hash, byte in
            hash = hash &* 33 &+ UInt64(byte)
        }
        return "\(cacheDir)/\(hash).jpg"
    }

    private nonisolated static func saveToDisk(image: NSImage, at path: String, quality: CGFloat) {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: quality]) else {
            return
        }
        try? jpegData.write(to: URL(fileURLWithPath: path))
    }

    private nonisolated func isStale(source sourcePath: String, cache cachePath: String) -> Bool {
        let fm = FileManager.default
        guard let sourceAttrs = try? fm.attributesOfItem(atPath: sourcePath),
              let cacheAttrs = try? fm.attributesOfItem(atPath: cachePath),
              let sourceDate = sourceAttrs[.modificationDate] as? Date,
              let cacheDate = cacheAttrs[.modificationDate] as? Date else {
            return true
        }
        return sourceDate > cacheDate
    }
}
