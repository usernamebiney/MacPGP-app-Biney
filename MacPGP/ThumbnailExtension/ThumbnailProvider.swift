import QuickLookThumbnailing
import Cocoa

nonisolated class ThumbnailProvider: QLThumbnailProvider {

    private let fileAnalyzer = PGPFileAnalyzer()
    private let renderer = ThumbnailRenderer()

    override func provideThumbnail(for request: QLFileThumbnailRequest, _ handler: @escaping (QLThumbnailReply?, Error?) -> Void) {

        // Check if this is a PGP file
        guard PGPFileAnalyzer.isPGPFile(url: request.fileURL) else {
            handler(nil, nil)
            return
        }

        // Analyze the file to determine encryption status
        guard let result = try? fileAnalyzer.analyzeHeader(fileAt: request.fileURL) else {
    print("MacPGP Thumbnail: analyzeHeader FAILED:", request.fileURL.path)
    handler(nil, nil)
    return
}

print(
    "MacPGP Thumbnail:",
    request.fileURL.path,
    "type:", result.fileType,
    "encoding:", result.encodingFormat,
    "encrypted:", result.isEncrypted
)

guard result.isEncrypted else {
    handler(nil, nil)
    return
}

        // Generate thumbnail with visual indicators for encryption type
        let reply = QLThumbnailReply(contextSize: request.maximumSize, currentContextDrawing: { () -> Bool in
            return self.renderer.renderThumbnail(for: result, in: request.maximumSize)
        })

        handler(reply, nil)
    }
}
