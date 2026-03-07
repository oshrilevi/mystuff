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

    init(tokenProvider: @escaping () async throws -> String) {
        self.tokenProvider = tokenProvider
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
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw DriveError.requestFailed(String(data: responseData, encoding: .utf8) ?? "Unknown")
        }
        let json = try JSONSerialization.jsonObject(with: responseData) as? [String: Any]
        guard let id = json?["id"] as? String else { throw DriveError.invalidResponse }
        return id
    }

    func thumbnailURL(fileId: String) -> URL? {
        URL(string: "https://drive.google.com/thumbnail?id=\(fileId)&sz=w400")
    }

    /// Fetches image bytes with auth (required for Drive; public thumbnail URL does not work unauthenticated).
    func fetchImageData(fileId: String) async throws -> Data {
        let token = try await tokenProvider()
        var request = URLRequest(url: URL(string: baseURL + "/files/\(fileId)?alt=media")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw DriveError.requestFailed(String(data: data, encoding: .utf8) ?? "Unknown")
        }
        return data
    }

    func downloadURL(fileId: String) -> String {
        "https://www.googleapis.com/drive/v3/files/\(fileId)?alt=media"
    }
}

enum DriveError: LocalizedError {
    case requestFailed(String)
    case invalidResponse
    var errorDescription: String? {
        switch self {
        case .requestFailed(let msg): return msg
        case .invalidResponse: return "Invalid response"
        }
    }
}
