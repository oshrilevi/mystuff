import Foundation
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

final class DriveService {
    private let baseURL = "https://www.googleapis.com/drive/v3"
    private let uploadURL = "https://www.googleapis.com/upload/drive/v3/files"
    private let tokenProvider: () async throws -> String

    /// In-memory cache for image data keyed by Drive file ID. Evicts under memory pressure.
    private let memoryCache: NSCache<NSString, NSData> = {
        let c = NSCache<NSString, NSData>()
        c.countLimit = 200
        c.totalCostLimit = 100 * 1024 * 1024 // 100 MB
        return c
    }()
    /// Disk cache directory: Caches/MyStuffThumbnails. Access synchronized via diskQueue.
    private let diskCacheURL: URL = {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MyStuffThumbnails", isDirectory: true)
    }()
    private let diskQueue = DispatchQueue(label: "mystuff.drive.diskcache")
    private let maxDiskCacheBytes = 300 * 1024 * 1024 // 300 MB

    init(tokenProvider: @escaping () async throws -> String) {
        self.tokenProvider = tokenProvider
    }

    /// Sanitizes a Drive file ID for use as a filename (alphanumeric, "-", "_" only).
    private static func sanitizedFileId(_ fileId: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        return fileId.unicodeScalars.map { allowed.contains($0) ? String($0) : "_" }.joined()
    }

    func createFolder(name: String, parentId: String? = nil) async throws -> String {
        let token = try await tokenProvider()
        var request = URLRequest(url: URL(string: baseURL + "/files")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var metadata: [String: Any] = [
            "name": name,
            "mimeType": "application/vnd.google-apps.folder"
        ]
        if let parentId = parentId { metadata["parents"] = [parentId] }
        request.httpBody = try JSONSerialization.data(withJSONObject: metadata)
        request.timeoutInterval = 30
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode == 401 {
            throw DriveError.unauthorized(String(data: data, encoding: .utf8) ?? "Unauthorized")
        }
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw DriveError.requestFailed(String(data: data, encoding: .utf8) ?? "Unknown")
        }
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let id = json?["id"] as? String else { throw DriveError.invalidResponse }
        return id
    }

    func uploadImage(data: Data, mimeType: String, filename: String, parentFolderId: String) async throws -> String {
        let token = try await tokenProvider()
        let boundary = "boundary_\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
        var request = URLRequest(url: URL(string: uploadURL + "?uploadType=multipart")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/related; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        let metadata = """
        {"name":"\(filename.replacingOccurrences(of: "\"", with: "\\\""))","parents":["\(parentFolderId)"]}
        """
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/json; charset=UTF-8\r\n\r\n".data(using: .utf8)!)
        body.append(metadata.data(using: .utf8)!)
        body.append("\r\n--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body
        let (responseData, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode == 401 {
            throw DriveError.unauthorized(String(data: responseData, encoding: .utf8) ?? "Unauthorized")
        }
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw DriveError.requestFailed(String(data: responseData, encoding: .utf8) ?? "Unknown")
        }
        let json = try JSONSerialization.jsonObject(with: responseData) as? [String: Any]
        guard let id = json?["id"] as? String else { throw DriveError.invalidResponse }
        return id
    }

    /// Uploads any file (e.g. PDF, images) to Drive. For images prefer uploadImage; this is for documents.
    func uploadFile(data: Data, mimeType: String, filename: String, parentFolderId: String) async throws -> String {
        try await uploadImage(data: data, mimeType: mimeType, filename: filename, parentFolderId: parentFolderId)
    }

    func thumbnailURL(fileId: String) -> URL? {
        URL(string: "https://drive.google.com/thumbnail?id=\(fileId)&sz=w400")
    }

    /// Fetches image bytes with auth (required for Drive; public thumbnail URL does not work unauthenticated).
    /// Uses in-memory then disk cache; only hits the network on cache miss.
    func fetchImageData(fileId: String) async throws -> Data {
        let key = fileId as NSString
        if let cached = memoryCache.object(forKey: key) {
            return cached as Data
        }
        if let diskData = await readFromDisk(fileId: fileId) {
            memoryCache.setObject(diskData as NSData, forKey: key, cost: diskData.count)
            return diskData
        }
        let token = try await tokenProvider()
        var request = URLRequest(url: URL(string: baseURL + "/files/\(fileId)?alt=media")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode == 401 {
            throw DriveError.unauthorized(String(data: data, encoding: .utf8) ?? "Unauthorized")
        }
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw DriveError.requestFailed(String(data: data, encoding: .utf8) ?? "Unknown")
        }
        memoryCache.setObject(data as NSData, forKey: key, cost: data.count)
        await writeToDisk(fileId: fileId, data: data)
        return data
    }

    private func readFromDisk(fileId: String) async -> Data? {
        await withCheckedContinuation { continuation in
            diskQueue.async { [weak self] in
                guard let self else { continuation.resume(returning: nil); return }
                let url = self.diskCacheURL.appendingPathComponent(Self.sanitizedFileId(fileId), isDirectory: false)
                let data = try? Data(contentsOf: url)
                continuation.resume(returning: data)
            }
        }
    }

    private func writeToDisk(fileId: String, data: Data) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            diskQueue.async { [weak self] in
                guard let self else { continuation.resume(); return }
                try? FileManager.default.createDirectory(at: self.diskCacheURL, withIntermediateDirectories: true)
                let url = self.diskCacheURL.appendingPathComponent(Self.sanitizedFileId(fileId), isDirectory: false)
                try? data.write(to: url)
                self.evictDiskCacheIfNeeded()
                continuation.resume()
            }
        }
    }

    /// Deletes oldest files by modification date until total size is at or below maxDiskCacheBytes.
    private func evictDiskCacheIfNeeded() {
        guard let urls = try? FileManager.default.contentsOfDirectory(at: diskCacheURL, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey], options: .skipsHiddenFiles) else { return }
        var total: Int = 0
        var byDate: [(URL, Date, Int)] = []
        for url in urls {
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
                  let size = attrs[.size] as? Int,
                  let date = attrs[.modificationDate] as? Date else { continue }
            total += size
            byDate.append((url, date, size))
        }
        guard total > maxDiskCacheBytes else { return }
        byDate.sort { $0.1 < $1.1 }
        for (url, _, size) in byDate {
            try? FileManager.default.removeItem(at: url)
            total -= size
            if total <= maxDiskCacheBytes { break }
        }
    }

    func downloadURL(fileId: String) -> String {
        "https://www.googleapis.com/drive/v3/files/\(fileId)?alt=media"
    }
}

enum DriveError: LocalizedError {
    case requestFailed(String)
    case invalidResponse
    case unauthorized(String)
    var errorDescription: String? {
        switch self {
        case .requestFailed(let msg): return msg
        case .invalidResponse: return "Invalid response"
        case .unauthorized(let msg): return "Google Drive authorization failed: \(msg)"
        }
    }
}
