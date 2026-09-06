import Foundation
import AppKit
import Darwin
@preconcurrency import UserNotifications

/// Handles communication between app extensions (FinderSync, QuickLook, Thumbnail) and the main application
/// This service processes file operations triggered from Finder context menus and other extension interfaces
final class ExtensionCommunicationService: NSObject {

    // MARK: - Notification Names

    /// Posted when files should be opened for encryption
    static let encryptFilesNotification = Notification.Name("com.macpgp.encryptFiles")

    /// Posted when files should be opened for decryption
    static let decryptFilesNotification = Notification.Name("com.macpgp.decryptFiles")

    /// UserInfo key for file URLs array
    static let fileURLsKey = "fileURLs"

    // MARK: - Properties

    private let fileAnalyzer = PGPFileAnalyzer()
    private let notificationCenter = UNUserNotificationCenter.current()
    private var finderSyncActivationObserver: NSObjectProtocol?
    private static let finderSyncRequestsKey = "com.macpgp.finderSync.fileRequests"
    private static let finderSyncLockFileName = ".macpgp-finder-sync.lock"

    // MARK: - Initialization

    override init() {
        super.init()
        registerForEvents()
        deliverPendingFinderSyncErrors()
        DispatchQueue.main.async { [weak self] in
            self?.deliverPendingFinderSyncFileRequests()
        }
    }

    deinit {
        if let observer = finderSyncActivationObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Registration

    /// Registers the service to handle file opening events
    private func registerForEvents() {
        finderSyncActivationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.deliverPendingFinderSyncFileRequests()
        }

        NSLog("[ExtensionCommunicationService] Registered for extension events")
    }

    // MARK: - File Handling

    /// Handles files opened from extensions or Finder
    /// Determines the appropriate operation (encrypt/decrypt) based on file type
    /// - Parameter urls: Array of file URLs to process
    func handleOpenFiles(_ urls: [URL]) {
        deliverPendingFinderSyncErrors()

        guard !urls.isEmpty else {
            NSLog("[ExtensionCommunicationService] No files to handle")
            return
        }

        NSLog("[ExtensionCommunicationService] Handling \(urls.count) file(s)")

        // Separate encrypted files from regular files. Classification uses
        // bounded header sniffing (issue #142) via isEncryptedFile, so opening a
        // large file never reads it fully just to choose the handoff route.
        let encryptedFiles = urls.filter { isEncryptedFile($0) }
        let regularFiles = urls.filter { !isEncryptedFile($0) }

        // Handle decryption for encrypted files
        if !encryptedFiles.isEmpty {
            NSLog("[ExtensionCommunicationService] Triggering decrypt for \(encryptedFiles.count) encrypted file(s)")
            postDecryptNotification(for: encryptedFiles)
        }

        // Handle encryption for regular files
        if !regularFiles.isEmpty {
            NSLog("[ExtensionCommunicationService] Triggering encrypt for \(regularFiles.count) regular file(s)")
            postEncryptNotification(for: regularFiles)
        }
    }

    // MARK: - Notification Posting

    /// Posts notification to trigger encryption workflow
    /// - Parameter urls: Files to encrypt
    private func postEncryptNotification(for urls: [URL]) {
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: Self.encryptFilesNotification,
                object: nil,
                userInfo: [Self.fileURLsKey: urls]
            )
        }
    }

    /// Posts notification to trigger decryption workflow
    /// - Parameter urls: Files to decrypt
    private func postDecryptNotification(for urls: [URL]) {
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: Self.decryptFilesNotification,
                object: nil,
                userInfo: [Self.fileURLsKey: urls]
            )
        }
    }

    private func deliverPendingFinderSyncFileRequests() {
        guard let defaults = UserDefaults(suiteName: SharedConfiguration.appGroupIdentifier),
              let containerURL = FileManager.default.containerURL(
                  forSecurityApplicationGroupIdentifier: SharedConfiguration.appGroupIdentifier
              ) else {
            return
        }

        let lockURL = containerURL.appendingPathComponent(Self.finderSyncLockFileName)
        let fd = open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)

        guard fd >= 0 else { return }
        defer { close(fd) }

        guard flock(fd, LOCK_EX) == 0 else { return }
        defer { flock(fd, LOCK_UN) }

        let requests = defaults.array(forKey: Self.finderSyncRequestsKey) as? [[String: Any]] ?? []
        guard !requests.isEmpty else { return }

        defaults.removeObject(forKey: Self.finderSyncRequestsKey)
        defaults.synchronize()

        for request in requests {
            guard let operation = request["operation"] as? String,
                  let bookmarks = request["bookmarks"] as? [Data] else {
                continue
            }

            var urls: [URL] = []

            for bookmark in bookmarks {
                var stale = false

                guard let url = try? URL(
                    resolvingBookmarkData: bookmark,
                    options: [.withSecurityScope],
                    relativeTo: nil,
                    bookmarkDataIsStale: &stale
                ) else {
                    NSLog("[ExtensionCommunicationService] Failed to resolve Finder Sync bookmark")
                    continue
                }

                guard url.startAccessingSecurityScopedResource() else {
                    NSLog("[ExtensionCommunicationService] Failed to start security-scoped access")
                    continue
                }

                urls.append(url)
            }

            guard !urls.isEmpty else { continue }

            switch operation {
            case "decrypt":
                postDecryptNotification(for: urls)
            default:
                postEncryptNotification(for: urls)
            }
        }
    }

    private func deliverPendingFinderSyncErrors() {
        guard let pendingErrors = FinderSyncErrorQueue.drain() else {
            NSLog("[ExtensionCommunicationService] Failed to open app group defaults for Finder Sync errors")
            return
        }

        guard !pendingErrors.isEmpty else {
            return
        }

        let notifications = pendingErrors.map { entry in
            (id: entry.id, title: entry.title, message: entry.message)
        }

        guard !notifications.isEmpty else {
            return
        }

        notificationCenter.requestAuthorization(options: [.alert, .sound]) { [notificationCenter] granted, error in
            if let error = error {
                NSLog("[ExtensionCommunicationService] Failed to request notification authorization: \(error.localizedDescription)")
                return
            }

            guard granted else {
                NSLog("[ExtensionCommunicationService] Notification authorization denied for Finder Sync errors")
                return
            }

            for notification in notifications {
                let content = UNMutableNotificationContent()
                content.title = notification.title
                content.body = notification.message
                content.sound = .default

                let request = UNNotificationRequest(
                    identifier: "com.macpgp.finder-error-\(notification.id)",
                    content: content,
                    trigger: nil
                )

                notificationCenter.add(request) { error in
                    if let error = error {
                        NSLog("[ExtensionCommunicationService] Failed to deliver Finder Sync error notification: \(error.localizedDescription)")
                    }
                }
            }
        }
    }
}

// MARK: - Document Type Handling

extension ExtensionCommunicationService {

    /// Determines if a URL represents an encrypted PGP file.
    ///
    /// Uses bounded header sniffing (`isEncryptedHeader`) rather than a full-file
    /// analysis: operation routing and Finder handoff only need the packet header,
    /// so a large file is never read into memory just to choose encrypt vs decrypt
    /// (issue #142).
    /// - Parameter url: File URL to check
    /// - Returns: True if the file is encrypted
    func isEncryptedFile(_ url: URL) -> Bool {
        return PGPFileAnalyzer.isPGPFile(url: url) && fileAnalyzer.isEncryptedHeader(fileAt: url)
    }

    /// Returns appropriate operation for a given file
    /// - Parameter url: File URL to analyze
    /// - Returns: Operation type (encrypt or decrypt)
    func operationType(for url: URL) -> OperationType {
        if isEncryptedFile(url) {
            return .decrypt
        } else {
            return .encrypt
        }
    }
}

// MARK: - Supporting Types

extension ExtensionCommunicationService {
    enum OperationType {
        case encrypt
        case decrypt
    }
}
