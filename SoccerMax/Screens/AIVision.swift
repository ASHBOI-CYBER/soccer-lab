// AI VISION (2026-11-15): what the Film AI review and the Food photo scan share.
//   AIConsent / AIGate   one yes covers Coach, film reviews and food scans (App Store 5.1.2(i)); sign in first.
//   AIUsage              how many of today's reviews / scans are left, as the server last said.
//   AICall               POST to an AI edge function (supabase/functions/film-review, food-scan).
//   ClipFrames + Pose    up to 8 still frames from a clip, and Apple Vision's body reading of each (on the phone,
//                        free): knee bend and lean. The video itself never leaves the phone.
//   PhotoPrep / CameraPicker   a meal photo, made small before it is sent.
import AVFoundation
import SwiftUI
import UIKit
import Vision

// MARK: - consent

enum AIConsent {
    static let key = "ai.consent.v2"
    static let text = "Coach, AI film reviews and food scans send what they need to Anthropic, the company that makes the Claude AI: your messages, a short summary of your training (position, age, level, goals, sessions, Fix List, food log), still frames from clips you choose to review, and photos of meals you scan. Your name and email are not sent, and none of it is used to train their AI."
}

/// The one-time yes, before anything goes to the AI company.
struct AIConsentCard: View {
    var onNo: () -> Void
    @State private var coach = Coach.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Before you start").font(.system(size: 17, weight: .bold)).foregroundStyle(C.creme)
            Text(AIConsent.text)
                .font(F.round(14, .medium)).foregroundStyle(C.creme2)
                .fixedSize(horizontal: false, vertical: true)
            Link("How your data is used", destination: Legal.privacy)
                .font(F.round(14, .semibold)).foregroundStyle(C.brandHi)
            HStack(spacing: 10) {
                Button("Not now") { onNo() }
                    .buttonStyle(.game(.charcoal, height: 48, font: 17))
                Button("I agree") { coach.consent(true); Haptics.play(.latch) }
                    .buttonStyle(.game(.brand, height: 48, font: 17))
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(C.char800)
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(C.line, lineWidth: 1)))
    }
}

/// Signed in, then the one-time yes, then `content`.
struct AIGate<Content: View>: View {
    /// "AI film reviews", "food scans"
    let what: String
    var onNo: () -> Void
    @ViewBuilder var content: () -> Content
    @State private var team = Team.shared
    @State private var coach = Coach.shared

    var body: some View {
        if !team.signedIn {
            VStack(spacing: 12) {
                Text("Sign in to use \(what). It keeps your daily allowance fair.")
                    .font(F.round(15, .semibold)).foregroundStyle(C.creme2).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                AppleSignIn()
                if let e = team.error {
                    Text(e).font(F.round(13, .semibold)).foregroundStyle(C.gold).multilineTextAlignment(.center)
                }
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(C.char800))
        } else if !coach.consented {
            AIConsentCard(onNo: onNo)
        } else {
            content()
        }
    }
}

// MARK: - today's allowance

@MainActor @Observable
final class AIUsage {
    static let shared = AIUsage()
    /// The daily allowances (supabase/functions/_shared/ai.ts LIMITS). Payments aren't on yet: everyone has trial.
    static let trial: [String: Int] = ["film": 2, "food": 5]
    static let paid: [String: Int] = ["film": 5, "food": 15]

    private var left: [String: Int] = (UserDefaults.standard.dictionary(forKey: "ai.left.v1") as? [String: Int]) ?? [:]

    /// Left today, once the server has said; nil before the first use today.
    func remaining(_ kind: String) -> Int? { left[kind + "|" + dateKey(Date())] }
    func set(_ kind: String, _ n: Int) {
        let today = dateKey(Date())
        left = left.filter { $0.key.hasSuffix(today) }
        left[kind + "|" + today] = n
        UserDefaults.standard.set(left, forKey: "ai.left.v1")
    }
    /// "2 left today" / "5 a day"
    func line(_ kind: String) -> String {
        if let n = remaining(kind) { return n == 0 ? "None left today" : "\(n) left today" }
        return "\(Self.trial[kind] ?? 0) a day"
    }
}

// MARK: - calling the server

enum AICall {
    struct Failure: Error { let message: String }

    /// POST to an AI edge function. Returns the decoded reply, or throws the server's own message.
    @MainActor static func post<T: Decodable>(_ fn: String, _ body: [String: Any], kind: String, as: T.Type) async throws -> T {
        let code: Int, data: Data
        do {
            (code, data) = try await Team.shared.api.function(fn, body)
        } catch let e as SupabaseError {
            throw Failure(message: e.message)
        } catch {
            throw Failure(message: "Couldn't connect. Check your internet and try again.")
        }
        struct Meta: Decodable { let error: String?; let remaining: Int? }
        let meta = try? JSONDecoder().decode(Meta.self, from: data)
        if let n = meta?.remaining { AIUsage.shared.set(kind, n) }
        guard (200..<300).contains(code) else {
            throw Failure(message: meta?.error ?? (code == 401 ? "Sign in again, then try once more." : "Something went wrong. Try again."))
        }
        guard let value = try? JSONDecoder().decode(T.self, from: data) else {
            throw Failure(message: "Something went wrong. Try again.")
        }
        return value
    }
}

// MARK: - film: frames and body reading

/// What the AI film review returns (supabase/functions/film-review).
struct FilmAIReport: Codable, Hashable {
    var usable: Bool
    var problem: String
    var action: String
    var score: Int
    var verdict: String
    var strengths: [String]
    var fixes: [FilmAIFix]
    var cues: [String]
}

struct FilmAIFix: Codable, Hashable {
    var title: String
    var detail: String
    var drill_ids: [String]
    /// Only drills this app has.
    var drills: [String] { drill_ids.filter { Library.shared.has($0) } }
}

enum ClipFrames {
    struct Result {
        let frames: [Data]
        /// Frames where the phone found at least one person.
        let withPerson: Int
        /// One line per frame: when it is and what the body reading found.
        let notes: [String]
        let seconds: Double
    }
    struct Failure: Error { let message: String }

    /// Up to `count` frames spread across the clip, each a small JPEG, with Apple Vision's body reading.
    static func make(_ url: URL, count: Int = 8) async throws -> Result {
        let asset = AVURLAsset(url: url)
        let secs = (try? await asset.load(.duration))?.seconds ?? 0
        guard secs.isFinite, secs >= 0.5 else { throw Failure(message: "That clip is too short to review. Use one of at least a second.") }
        guard secs <= 600 else { throw Failure(message: "That clip is long. Trim it to the moment you want reviewed (under 10 minutes).") }
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 768, height: 768)
        let tol = CMTime(seconds: 0.15, preferredTimescale: 600)
        gen.requestedTimeToleranceBefore = tol
        gen.requestedTimeToleranceAfter = tol

        let n = secs < 2 ? 4 : count
        var frames: [Data] = [], notes: [String] = []
        var people = 0
        for i in 0..<n {
            let at = secs * (0.04 + 0.92 * Double(i) / Double(max(1, n - 1)))
            guard let cg = try? await gen.image(at: CMTime(seconds: at, preferredTimescale: 600)).image,
                  let jpg = jpeg(cg, limit: 340_000) else { continue }
            frames.append(jpg)
            let pose = Pose.read(cg)
            if pose.people > 0 { people += 1 }
            notes.append("Frame \(frames.count) at \(String(format: "%.1f", at)) s: \(pose.note)")
        }
        guard !frames.isEmpty else { throw Failure(message: "Couldn't read that clip. Try another one.") }
        return Result(frames: frames, withPerson: people, notes: notes, seconds: secs)
    }

    static func jpeg(_ cg: CGImage, limit: Int) -> Data? {
        let img = UIImage(cgImage: cg)
        for q: CGFloat in [0.65, 0.5, 0.35] {
            if let d = img.jpegData(compressionQuality: q), d.count <= limit { return d }
        }
        return nil
    }
}

/// Apple Vision's body pose on one frame: how many people, and for the biggest one (most likely the player filming
/// themselves) the knee angles and how far the upper body leans. Hints for the AI, not the verdict.
enum Pose {
    struct Reading { let people: Int; let note: String }
    typealias Joint = VNHumanBodyPoseObservation.JointName

    static func read(_ cg: CGImage) -> Reading {
        let request = VNDetectHumanBodyPoseRequest()
        do { try VNImageRequestHandler(cgImage: cg, options: [:]).perform([request]) } catch {
            return Reading(people: 0, note: "body reading failed")
        }
        let w = CGFloat(cg.width), h = CGFloat(cg.height)
        let bodies: [[Joint: CGPoint]] = (request.results ?? []).map { body in
            var out: [Joint: CGPoint] = [:]
            for (k, p) in (try? body.recognizedPoints(.all)) ?? [:] where p.confidence > 0.3 {
                out[k] = CGPoint(x: p.location.x * w, y: p.location.y * h)
            }
            return out
        }.filter { $0.count >= 6 }
        guard !bodies.isEmpty else { return Reading(people: 0, note: "no person found") }

        func area(_ p: [Joint: CGPoint]) -> CGFloat {
            let xs = p.values.map(\.x), ys = p.values.map(\.y)
            return ((xs.max() ?? 0) - (xs.min() ?? 0)) * ((ys.max() ?? 0) - (ys.min() ?? 0))
        }
        let main = bodies.max { area($0) < area($1) } ?? bodies[0]
        var parts: [String] = []
        if let a = angle(main[.leftHip], main[.leftKnee], main[.leftAnkle]) { parts.append("left knee \(a)°") }
        if let a = angle(main[.rightHip], main[.rightKnee], main[.rightAnkle]) { parts.append("right knee \(a)°") }
        if let neck = main[.neck], let root = main[.root] {
            let lean = Int((atan2(abs(neck.x - root.x), max(1, abs(neck.y - root.y))) * 180 / .pi).rounded())
            parts.append("upper body \(lean)° from upright")
        }
        let who = bodies.count == 1 ? "1 person" : "\(bodies.count) people"
        return Reading(people: bodies.count, note: who + (parts.isEmpty ? "" : "; biggest person: " + parts.joined(separator: ", ")))
    }

    /// The angle at b, in whole degrees (180 = straight).
    static func angle(_ a: CGPoint?, _ b: CGPoint?, _ c: CGPoint?) -> Int? {
        guard let a, let b, let c else { return nil }
        let x1 = a.x - b.x, y1 = a.y - b.y, x2 = c.x - b.x, y2 = c.y - b.y
        let len = hypot(x1, y1) * hypot(x2, y2)
        guard len > 0.0001 else { return nil }
        let cos = max(-1, min(1, (x1 * x2 + y1 * y2) / len))
        return Int((acos(cos) * 180 / .pi).rounded())
    }
}

// MARK: - food: the photo

/// What the food scan returns (supabase/functions/food-scan).
struct FoodScanResult: Codable, Hashable {
    var is_food: Bool
    var message: String
    var items: [FoodScanItem]
}

struct FoodScanItem: Codable, Hashable, Identifiable {
    var id: String { name + portion }
    var name: String
    var portion: String
    var grams: Double
    var kcal: Int
    var protein: Double
    var carbs: Double
    var fat: Double
}

enum PhotoPrep {
    /// The photo made small (longest side `side` px) as a JPEG under `limit` bytes.
    static func jpeg(_ image: UIImage, side: CGFloat = 1024, limit: Int = 550_000) -> Data? {
        let s = image.size
        guard s.width > 0, s.height > 0 else { return nil }
        let scale = min(1, side / max(s.width, s.height))
        let size = CGSize(width: (s.width * scale).rounded(), height: (s.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let small = UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        for q: CGFloat in [0.7, 0.55, 0.4] {
            if let d = small.jpegData(compressionQuality: q), d.count <= limit { return d }
        }
        return nil
    }
}

/// The camera (or the photo library on a phone without one, like the simulator).
struct CameraPicker: UIViewControllerRepresentable {
    var onPick: (UIImage?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let p = UIImagePickerController()
        p.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        p.delegate = context.coordinator
        return p
    }
    func updateUIViewController(_ vc: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onPick: (UIImage?) -> Void
        init(onPick: @escaping (UIImage?) -> Void) { self.onPick = onPick }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            onPick(info[.originalImage] as? UIImage)
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { onPick(nil) }
    }
}
