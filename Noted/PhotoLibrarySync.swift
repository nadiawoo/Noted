// PhotoLibrarySync.swift — Noted
// Automatic, background screenshot ingestion.
//
// On photo-library access the app no longer needs the user to import images
// one by one. This service fetches the user's *screenshots* (only screenshots,
// never other photos), runs free on-device OCR on each, applies a local
// time-sensitivity heuristic, and only then pays for a Gemini call on the
// small subset that actually looks like an event/deadline.
//
// Scope: the last 30 days of screenshots plus every new screenshot going
// forward (observed live). Older screenshots are processed on demand via
// `syncEntireLibrary()`. Processed asset IDs are persisted so we never
// re-analyse — and never re-pay — for an image we've already seen.

import SwiftUI
import Combine

#if os(iOS)
import Photos
import PhotosUI
import UIKit

@MainActor
final class PhotoLibrarySync: NSObject, ObservableObject, PHPhotoLibraryChangeObserver {

    // MARK: - Published state (drives SyncProgressView)

    @Published private(set) var authorization: PHAuthorizationStatus = .notDetermined
    @Published private(set) var totalScreenshots = 0      // screenshots in current scope
    @Published private(set) var processedScreenshots = 0  // how many we've gone through
    @Published private(set) var isSyncing = false
    @Published private(set) var lastError: String?

    /// 0…1 fraction of in-scope screenshots the app has reviewed.
    var progress: Double {
        totalScreenshots == 0 ? 0 : min(1, Double(processedScreenshots) / Double(totalScreenshots))
    }
    var isLimited: Bool { authorization == .limited }
    var isAuthorized: Bool { authorization == .authorized || authorization == .limited }
    var pendingCount: Int { max(0, totalScreenshots - processedScreenshots) }

    /// Set by NotedViewModel — runs OCR-passing screenshots through Gemini and
    /// appends any detected events. Default no-op until wired.
    var processImage: (UIImage, String) async -> Void = { _, _ in }

    // MARK: - Private

    private let processedKey = "Noted.processedScreenshotIDs"
    private var processed: Set<String>
    private var observingChanges = false
    /// When true, scope is the entire library rather than the last 30 days.
    private var fullLibrary = false

    override init() {
        let saved = UserDefaults.standard.stringArray(forKey: processedKey) ?? []
        processed = Set(saved)
        super.init()
    }

    deinit {
        if observingChanges {
            PHPhotoLibrary.shared().unregisterChangeObserver(self)
        }
    }

    // MARK: - Lifecycle

    /// Call on launch / when the sync page appears. Picks up the current
    /// authorization status and, if already granted, syncs in the background.
    /// Never prompts on its own — granting happens through `requestAccessAndSync`.
    func start() {
        authorization = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard isAuthorized else { return }
        registerObserverIfNeeded()
        refresh()
    }

    /// Explicit opt-in from the sync page: prompt for access, then sync.
    func requestAccessAndSync() async {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        authorization = status
        guard isAuthorized else { return }
        registerObserverIfNeeded()
        refresh()
    }

    /// Process screenshots taken before the 30-day window too.
    func syncEntireLibrary() {
        fullLibrary = true
        refresh()
    }

    /// Present iOS's "select more photos" sheet for limited access.
    func presentLimitedPicker() {
        guard
            let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene }).first,
            let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController
                ?? scene.windows.first?.rootViewController
        else { return }
        PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: root)
    }

    // MARK: - Sync

    func refresh() {
        guard isAuthorized, !isSyncing else { return }
        Task { await sync() }
    }

    private func sync() async {
        let assets = fetchScreenshots()
        totalScreenshots = assets.count

        var pending: [PHAsset] = []
        assets.enumerateObjects { asset, _, _ in
            if !self.processed.contains(asset.localIdentifier) { pending.append(asset) }
        }
        processedScreenshots = totalScreenshots - pending.count
        guard !pending.isEmpty else { return }

        isSyncing = true
        lastError = nil
        defer { isSyncing = false }

        for asset in pending {
            guard let image = await loadImage(asset) else {
                markProcessed(asset.localIdentifier)
                processedScreenshots += 1
                continue
            }

            // Free, on-device OCR — never leaves the phone.
            let ocr = (try? await ScreenshotTextRecognizer.recognizeText(in: image)) ?? ""

            // Only pay Gemini for screenshots that actually look time-sensitive.
            if TimeSensitivity.looksTimeSensitive(ocr) {
                await processImage(image, ocr)
            }

            markProcessed(asset.localIdentifier)
            processedScreenshots += 1
        }
    }

    // MARK: - Photos plumbing

    private func fetchScreenshots() -> PHFetchResult<PHAsset> {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]

        let isScreenshot = NSPredicate(
            format: "(mediaSubtypes & %d) != 0",
            PHAssetMediaSubtype.photoScreenshot.rawValue
        )

        if fullLibrary {
            options.predicate = isScreenshot
        } else {
            let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? .distantPast
            let recent = NSPredicate(format: "creationDate >= %@", cutoff as NSDate)
            options.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [isScreenshot, recent])
        }
        return PHAsset.fetchAssets(with: .image, options: options)
    }

    private func loadImage(_ asset: PHAsset) async -> UIImage? {
        let opts = PHImageRequestOptions()
        opts.isNetworkAccessAllowed = true
        opts.deliveryMode = .highQualityFormat   // single, non-degraded callback
        opts.isSynchronous = false
        opts.resizeMode = .exact

        // Downscale: OCR + Gemini don't need full-res, and this caps memory
        // while looping over many screenshots.
        let target = CGSize(width: 1280, height: 1280)

        return await withCheckedContinuation { (cont: CheckedContinuation<UIImage?, Never>) in
            var resumed = false
            PHImageManager.default().requestImage(
                for: asset, targetSize: target, contentMode: .aspectFit, options: opts
            ) { image, info in
                if resumed { return }
                let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                if degraded { return }          // wait for the full-quality delivery
                resumed = true
                cont.resume(returning: image)
            }
        }
    }

    private func markProcessed(_ id: String) {
        processed.insert(id)
        UserDefaults.standard.set(Array(processed), forKey: processedKey)
    }

    private func registerObserverIfNeeded() {
        guard !observingChanges else { return }
        PHPhotoLibrary.shared().register(self)
        observingChanges = true
    }

    // MARK: - PHPhotoLibraryChangeObserver

    nonisolated func photoLibraryDidChange(_ changeInstance: PHChange) {
        // New screenshot taken (or limited selection changed) → sync the delta.
        Task { @MainActor in
            self.authorization = PHPhotoLibrary.authorizationStatus(for: .readWrite)
            self.refresh()
        }
    }
}

// MARK: - Local time-sensitivity heuristic (free pre-filter)

/// Cheap, on-device check deciding whether a screenshot's OCR text is worth a
/// paid Gemini call. Tuned to be *inclusive* — a false positive costs a little
/// API, a false negative loses an event — so we err toward sending.
enum TimeSensitivity {
    static func looksTimeSensitive(_ text: String) -> Bool {
        let lower = text.lowercased()
        guard lower.count >= 3 else { return false }

        // Explicit clock times: "9:30", "9 pm", "10am"
        if matches(#"\b\d{1,2}:\d{2}\b"#, in: lower) { return true }
        if matches(#"\b\d{1,2}\s?(am|pm)\b"#, in: lower) { return true }

        // Numeric dates: "12/05", "2026-06-13", "5.12.26"
        if matches(#"\b\d{1,2}[/.\-]\d{1,2}([/.\-]\d{2,4})?\b"#, in: lower) { return true }

        // Day-of-month ordinals: "12th", "1st", "3rd"
        if matches(#"\b\d{1,2}(st|nd|rd|th)\b"#, in: lower) { return true }

        // Month / weekday names anywhere in the text.
        if containsAny(lower, months) || containsAny(lower, weekdays) { return true }

        // Event / deadline vocabulary.
        return containsAny(lower, keywords)
    }

    private static let months = [
        "january","february","march","april","may","june","july","august",
        "september","october","november","december",
        "jan ","feb ","mar ","apr ","jun ","jul ","aug ","sep","oct ","nov ","dec "
    ]
    private static let weekdays = [
        "monday","tuesday","wednesday","thursday","friday","saturday","sunday",
        "mon ","tue","wed","thu","fri","sat","sun"
    ]
    private static let keywords = [
        "deadline","due ","due:","due date","apply by","applications close","closes",
        "rsvp","appointment","reservation","reserved","booking","booked","confirmed",
        "confirmation","interview","meeting","webinar","seminar","lecture","class",
        "event","invite","invited","ticket","tickets","gate","boarding","flight",
        "check-in","checkin","check in","starts","ends","expires","expiry","renew",
        "submission","submit by","register by","registration","sign up","signup",
        "tomorrow","today","tonight","this week","next week","tmrw","schedule",
        "scheduled","when:","where:","location:","date:","time:"
    ]

    private static func containsAny(_ haystack: String, _ needles: [String]) -> Bool {
        needles.contains { haystack.contains($0) }
    }

    private static func matches(_ pattern: String, in text: String) -> Bool {
        text.range(of: pattern, options: .regularExpression) != nil
    }
}
#endif
