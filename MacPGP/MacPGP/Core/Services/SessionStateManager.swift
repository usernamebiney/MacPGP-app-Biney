import Foundation
import SwiftUI

/// Manages ephemeral session state that persists between tab switches but not across app launches
@Observable
final class SessionStateManager {
    // MARK: - Encrypt State
    var encryptInputText = ""
    var encryptOutputText = ""
    var encryptSelectedRecipients: Set<PGPKeyModel> = []
    var encryptSignerKey: PGPKeyModel?
    var encryptInputMode: InputMode = .text
    var encryptSelectedFile: URL?
    var encryptSelectedFiles: [URL] = []
    var encryptOutputLocation: URL?
    var encryptArmorOutput = true
    var encryptOutputFiles: [URL] = []
    var encryptionProgress: Double = 0.0

    // MARK: - Decrypt State
    var decryptInputText = ""
    var decryptOutputText = ""
    var decryptInputMode: InputMode = .text
    var decryptSelectedFile: URL?
    var decryptSelectedFiles: [URL] = []
    var decryptOutputLocation: URL?
    var decryptAutoDetectKey = true
    var decryptSelectedKey: PGPKeyModel?
    var decryptOutputFiles: [URL] = []
    var decryptionProgress: Double = 0.0

    // MARK: - Sign State
    var signInputText = ""
    var signOutputText = ""
    var signSignerKey: PGPKeyModel?
    var signInputMode: InputMode = .text
    var signSelectedFile: URL?
    var signDetachedSignature = false
    var signCleartextSignature = true
    var signArmorOutput = true
    var signOutputLocation: URL?
    var signOutputFiles: [URL] = []

    // MARK: - Verify State
    var verifyInputText = ""
    var verifySignatureText = ""
    var verifyResult: VerificationResult?
    var verifyInputMode: InputMode = .text
    var verifySignatureMode: SignatureMode = .inline
    var verifySelectedFile: URL?
    var verifySelectedSignatureFile: URL?

    enum OutputLocationKind: String {
        case encrypt
        case decrypt
        case sign

        var defaultsKey: String {
            "MacPGP.outputLocation.\(rawValue)"
        }
    }

    init() {
        encryptOutputLocation = Self.restoreOutputLocation(for: .encrypt)
        decryptOutputLocation = Self.restoreOutputLocation(for: .decrypt)
        signOutputLocation = Self.restoreOutputLocation(for: .sign)
    }

    /// Stores a user-selected output directory and persists its security-scoped bookmark.
    func setOutputLocation(_ url: URL, for kind: OutputLocationKind) {
        switch kind {
        case .encrypt:
            encryptOutputLocation = url
        case .decrypt:
            decryptOutputLocation = url
        case .sign:
            signOutputLocation = url
        }

        Self.persistOutputLocation(url, for: kind)
    }

    /// Uses the source file's directory as the first-use default.
    /// A previously selected output directory is never overwritten.
    func setSourceDirectoryAsDefaultIfNeeded(
        for kind: OutputLocationKind,
        source: URL
    ) {
        let directory = source.deletingLastPathComponent()

        switch kind {
        case .encrypt:
            if encryptOutputLocation == nil {
                encryptOutputLocation = directory
            }
        case .decrypt:
            if decryptOutputLocation == nil {
                decryptOutputLocation = directory
            }
        case .sign:
            if signOutputLocation == nil {
                signOutputLocation = directory
            }
        }
    }

    private static func restoreOutputLocation(
        for kind: OutputLocationKind
    ) -> URL? {
        guard let data = UserDefaults.standard.data(
            forKey: kind.defaultsKey
        ) else {
            return nil
        }

        var isStale = false

        do {
            let url = try URL(
                resolvingBookmarkData: data,
                options: [.withSecurityScope, .withoutUI],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )

            var isDirectory = ObjCBool(false)

            guard FileManager.default.fileExists(
                atPath: url.path,
                isDirectory: &isDirectory
            ), isDirectory.boolValue else {
                return nil
            }

            if isStale {
                persistOutputLocation(url, for: kind)
            }

            return url
        } catch {
            return nil
        }
    }

    private static func persistOutputLocation(
        _ url: URL,
        for kind: OutputLocationKind
    ) {
        do {
            let data = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )

            UserDefaults.standard.set(data, forKey: kind.defaultsKey)
        } catch {
            // Keep the location in memory if bookmark persistence fails.
        }
    }

    /// Resets ephemeral encryption, decryption, signing, and verification UI state.
    /// Remembered output locations intentionally survive this reset and app relaunches.
    /// 
    /// This clears input/output text, selected files/keys/recipients, output locations and file lists, modes, signature options, armor settings, and progress counters for the encrypt, decrypt, sign, and verify workflows.
    func clearAll() {
        // Encrypt
        encryptInputText = ""
        encryptOutputText = ""
        encryptSelectedRecipients = []
        encryptSignerKey = nil
        encryptInputMode = .text
        encryptSelectedFile = nil
        encryptSelectedFiles = []
        encryptArmorOutput = true
        encryptOutputFiles = []
        encryptionProgress = 0.0

        // Decrypt
        decryptInputText = ""
        decryptOutputText = ""
        decryptInputMode = .text
        decryptSelectedFile = nil
        decryptSelectedFiles = []
        decryptAutoDetectKey = true
        decryptSelectedKey = nil
        decryptOutputFiles = []
        decryptionProgress = 0.0

        // Sign
        signInputText = ""
        signOutputText = ""
        signSignerKey = nil
        signInputMode = .text
        signSelectedFile = nil
        signDetachedSignature = false
        signCleartextSignature = true
        signArmorOutput = true
        signOutputFiles = []

        // Verify
        verifyInputText = ""
        verifySignatureText = ""
        verifyResult = nil
        verifyInputMode = .text
        verifySignatureMode = .inline
        verifySelectedFile = nil
        verifySelectedSignatureFile = nil
    }
}
