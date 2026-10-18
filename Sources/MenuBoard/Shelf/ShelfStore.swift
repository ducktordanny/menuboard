import AppKit
import Foundation
import QuickLookThumbnailing
import UniformTypeIdentifiers

struct ShelfItem: Identifiable, Hashable, Codable {
    enum Kind: String, Codable { case file, link }

    let id: UUID
    var kind: Kind
    var url: URL
    var title: String
    /// Lives in the shelf's own storage directory (downloaded or received file), deleted on remove.
    var isManaged: Bool
    var isLoading = false

    var isFile: Bool { kind == .file }

    init(file url: URL, managed: Bool) {
        id = UUID()
        kind = .file
        self.url = url.standardizedFileURL
        title = url.lastPathComponent
        isManaged = managed
    }

    init(link url: URL, title: String, loading: Bool) {
        id = UUID()
        kind = .link
        self.url = url
        self.title = title
        isManaged = false
        isLoading = loading
    }
}

final class ShelfStore: ObservableObject {
    private static let defaultsKey = "shelf.items"

    private static let assetMIMEPrefixes = [
        "image/", "video/", "audio/", "font/",
        "application/pdf", "application/zip", "application/gzip", "application/octet-stream", "application/x-",
    ]

    static let storageDirectory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = base.appendingPathComponent("MenuBoard/Shelf", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }()

    static let draggedTypes: [NSPasteboard.PasteboardType] =
        [.fileURL, .URL, .png, .tiff] + NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) }

    @Published private(set) var items: [ShelfItem] = [] {
        didSet { persist() }
    }
    @Published var isDropTargeted = false
    /// Called after a drop was accepted, from any drop target.
    var onImport: (() -> Void)?

    private var iconCache: [URL: NSImage] = [:]
    private var detailCache: [URL: String] = [:]
    private var previewCache: [URL: NSImage] = [:]
    private var weblocCache: [URL: URL] = [:]
    private var pendingPreviews: Set<URL> = []
    private var failedPreviews: Set<URL> = []
    private let promiseQueue = OperationQueue()
    private let session = URLSession(configuration: .ephemeral)

    init() {
        guard let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
              let saved = try? JSONDecoder().decode([ShelfItem].self, from: data) else { return }
        items = saved.compactMap { item in
            var item = item
            item.isLoading = false
            if item.isFile, !FileManager.default.fileExists(atPath: item.url.path) { return nil }
            return item
        }
    }

    var urls: [URL] { items.map(\.url) }

    // MARK: Drop handling

    func canAccept(_ info: NSDraggingInfo) -> Bool {
        // Drags that start inside MenuBoard (shelf rows) are not imports.
        guard info.draggingSource == nil else { return false }
        return Self.canAccept(pasteboard: info.draggingPasteboard)
    }

    static func canAccept(pasteboard: NSPasteboard) -> Bool {
        pasteboard.canReadObject(forClasses: [NSURL.self, NSFilePromiseReceiver.self, NSImage.self], options: nil)
    }

    @discardableResult
    func importDrop(_ info: NSDraggingInfo) -> Bool {
        let accepted = acceptDrop(info)
        if accepted { onImport?() }
        return accepted
    }

    private func acceptDrop(_ info: NSDraggingInfo) -> Bool {
        let pasteboard = info.draggingPasteboard
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] ?? []

        let fileURLs = urls.filter(\.isFileURL)
        if !fileURLs.isEmpty {
            add(fileURLs)
            return true
        }

        if let receivers = pasteboard.readObjects(forClasses: [NSFilePromiseReceiver.self], options: nil) as? [NSFilePromiseReceiver],
           !receivers.isEmpty {
            receive(receivers)
            return true
        }

        let pastedImage = NSImage(pasteboard: pasteboard)
        if let url = urls.first(where: { ["http", "https"].contains($0.scheme?.lowercased()) }) {
            let title = pasteboard.string(forType: NSPasteboard.PasteboardType("public.url-name")) ?? url.host ?? url.absoluteString
            addRemote(url, title: title, fallbackImage: pastedImage)
            return true
        }

        if let pastedImage {
            saveImage(pastedImage, named: "Image \(Self.timestamp()).png", replacing: nil)
            return true
        }
        return false
    }

    func add(_ urls: [URL]) {
        let existing = Set(items.map(\.url))
        let fresh = urls.map(\.standardizedFileURL).filter { !existing.contains($0) }
        guard !fresh.isEmpty else { return }
        items.append(contentsOf: fresh.map { ShelfItem(file: $0, managed: false) })
    }

    private func receive(_ receivers: [NSFilePromiseReceiver]) {
        let incoming = Self.storageDirectory.appendingPathComponent(".incoming-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: incoming, withIntermediateDirectories: true)
        for receiver in receivers {
            receiver.receivePromisedFiles(atDestination: incoming, options: [:], operationQueue: promiseQueue) { [weak self] url, error in
                guard error == nil else { return }
                let destination = Self.uniqueDestination(named: url.lastPathComponent)
                guard (try? FileManager.default.moveItem(at: url, to: destination)) != nil else { return }
                DispatchQueue.main.async {
                    self?.items.append(ShelfItem(file: destination, managed: true))
                }
            }
        }
    }

    /// Links are added immediately; if the URL turns out to be an asset (image, PDF…) it is downloaded
    /// and the link item is swapped for the file.
    private func addRemote(_ url: URL, title: String, fallbackImage: NSImage?) {
        let item = ShelfItem(link: url, title: title, loading: true)
        items.append(item)

        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 15
        session.dataTask(with: request) { [weak self] _, response, _ in
            let mime = response?.mimeType?.lowercased() ?? ""
            let isAsset = Self.assetMIMEPrefixes.contains { mime.hasPrefix($0) }
            DispatchQueue.main.async {
                guard let self else { return }
                if isAsset {
                    self.download(url, replacing: item.id, fallbackImage: fallbackImage)
                } else if let fallbackImage {
                    self.saveImage(fallbackImage, named: Self.imageName(for: url), replacing: item.id)
                } else {
                    self.update(item.id) { $0.isLoading = false }
                }
            }
        }.resume()
    }

    private func download(_ url: URL, replacing id: UUID, fallbackImage: NSImage?) {
        session.downloadTask(with: url) { [weak self] temporaryURL, response, _ in
            var destination: URL?
            if let temporaryURL {
                let candidate = Self.uniqueDestination(named: response?.suggestedFilename ?? url.lastPathComponent)
                if (try? FileManager.default.moveItem(at: temporaryURL, to: candidate)) != nil { destination = candidate }
            }
            DispatchQueue.main.async {
                guard let self else { return }
                if let destination {
                    self.replace(id, with: ShelfItem(file: destination, managed: true))
                } else if let fallbackImage {
                    self.saveImage(fallbackImage, named: Self.imageName(for: url), replacing: id)
                } else {
                    self.update(id) { $0.isLoading = false }
                }
            }
        }.resume()
    }

    private func saveImage(_ image: NSImage, named name: String, replacing id: UUID?) {
        guard let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else {
            if let id { update(id) { $0.isLoading = false } }
            return
        }
        let destination = Self.uniqueDestination(named: name)
        guard (try? png.write(to: destination)) != nil else {
            if let id { update(id) { $0.isLoading = false } }
            return
        }
        let item = ShelfItem(file: destination, managed: true)
        if let id { replace(id, with: item) } else { items.append(item) }
    }

    // MARK: Item management

    func remove(_ item: ShelfItem) {
        items.removeAll { $0.id == item.id }
        deleteManagedFile(item)
        if let webloc = weblocCache.removeValue(forKey: item.url) { try? FileManager.default.removeItem(at: webloc) }
        iconCache[item.url] = nil
        detailCache[item.url] = nil
        previewCache[item.url] = nil
        failedPreviews.remove(item.url)
    }

    func clear() {
        let removed = items
        items.removeAll()
        removed.forEach(deleteManagedFile)
        weblocCache.values.forEach { try? FileManager.default.removeItem(at: $0) }
        weblocCache.removeAll()
        iconCache.removeAll()
        detailCache.removeAll()
        previewCache.removeAll()
        failedPreviews.removeAll()
    }

    func open(_ item: ShelfItem) {
        NSWorkspace.shared.open(item.url)
    }

    func reveal(_ item: ShelfItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    func icon(for item: ShelfItem) -> NSImage {
        if let cached = iconCache[item.url] { return cached }
        let icon: NSImage
        if item.isFile {
            icon = NSWorkspace.shared.icon(forFile: item.url.path)
        } else if let handler = NSWorkspace.shared.urlForApplication(toOpen: item.url) {
            icon = NSWorkspace.shared.icon(forFile: handler.path)
        } else {
            icon = NSImage(systemSymbolName: "link", accessibilityDescription: nil) ?? NSImage()
        }
        iconCache[item.url] = icon
        return icon
    }

    /// QuickLook thumbnail for files, favicon for links. Generated lazily; nil until ready or when unavailable.
    func preview(for item: ShelfItem) -> NSImage? {
        if let cached = previewCache[item.url] { return cached }
        guard !item.isLoading, !pendingPreviews.contains(item.url), !failedPreviews.contains(item.url) else { return nil }
        pendingPreviews.insert(item.url)
        if item.isFile {
            generateThumbnail(for: item.url)
        } else {
            fetchFavicon(for: item.url)
        }
        return nil
    }

    private func generateThumbnail(for url: URL) {
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: 96, height: 96), scale: scale, representationTypes: .thumbnail)
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { [weak self] representation, _ in
            DispatchQueue.main.async { self?.finishPreview(representation?.nsImage, for: url) }
        }
    }

    private func fetchFavicon(for url: URL) {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false), components.host != nil else {
            finishPreview(nil, for: url)
            return
        }
        components.path = "/favicon.ico"
        components.query = nil
        components.fragment = nil
        guard let faviconURL = components.url else {
            finishPreview(nil, for: url)
            return
        }
        session.dataTask(with: faviconURL) { [weak self] data, response, _ in
            let ok = (response as? HTTPURLResponse).map { (200..<300).contains($0.statusCode) } ?? false
            let image = ok ? data.flatMap { NSImage(data: $0) } : nil
            DispatchQueue.main.async { self?.finishPreview(image, for: url) }
        }.resume()
    }

    private func finishPreview(_ image: NSImage?, for url: URL) {
        pendingPreviews.remove(url)
        objectWillChange.send()
        if let image {
            previewCache[url] = image
        } else {
            failedPreviews.insert(url)
        }
    }

    /// URL handed to Quick Look: the file itself, or a generated .webloc so links render as a web page.
    func previewURL(for item: ShelfItem) -> URL {
        guard !item.isFile else { return item.url }
        if let cached = weblocCache[item.url] { return cached }
        let directory = Self.storageDirectory.appendingPathComponent(".previews", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let safeTitle = item.title.replacingOccurrences(of: "/", with: "-").prefix(80)
        let file = directory.appendingPathComponent("\(safeTitle.isEmpty ? "Link" : String(safeTitle)) \(item.id.uuidString.prefix(8)).webloc")
        let plist: [String: Any] = ["URL": item.url.absoluteString]
        if let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0) {
            try? data.write(to: file)
        }
        weblocCache[item.url] = file
        return file
    }

    func detail(for item: ShelfItem) -> String {
        if item.isLoading { return "Fetching…" }
        if let cached = detailCache[item.url] { return cached }
        let detail: String
        if item.isFile {
            var parts: [String] = []
            let values = try? item.url.resourceValues(forKeys: [.localizedTypeDescriptionKey, .fileSizeKey, .isDirectoryKey])
            if let kind = values?.localizedTypeDescription { parts.append(kind) }
            if values?.isDirectory != true, let size = values?.fileSize { parts.append(Format.file(Int64(size))) }
            let folder = item.isManaged ? "Shelf" : item.url.deletingLastPathComponent().path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
            parts.append(folder)
            detail = parts.joined(separator: " · ")
        } else {
            detail = (item.url.host ?? "") + item.url.path
        }
        detailCache[item.url] = detail
        return detail
    }

    private func update(_ id: UUID, _ change: (inout ShelfItem) -> Void) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        change(&items[index])
    }

    private func replace(_ id: UUID, with item: ShelfItem) {
        guard let index = items.firstIndex(where: { $0.id == id }) else {
            items.append(item)
            return
        }
        items[index] = item
    }

    private func deleteManagedFile(_ item: ShelfItem) {
        guard item.isManaged, item.url.path.hasPrefix(Self.storageDirectory.path) else { return }
        try? FileManager.default.removeItem(at: item.url)
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
    }

    // MARK: Naming

    private static func uniqueDestination(named rawName: String) -> URL {
        var name = rawName.replacingOccurrences(of: "/", with: "-").trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty || name.hasPrefix(".") { name = "file" + name }
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var candidate = storageDirectory.appendingPathComponent(name)
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            let numbered = ext.isEmpty ? "\(base) \(counter)" : "\(base) \(counter).\(ext)"
            candidate = storageDirectory.appendingPathComponent(numbered)
            counter += 1
        }
        return candidate
    }

    private static func imageName(for url: URL) -> String {
        let last = url.deletingPathExtension().lastPathComponent
        let base = last.isEmpty || last == "/" ? "Image \(timestamp())" : last
        return base + ".png"
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return formatter.string(from: Date())
    }
}
