// FREE SESSIONS (2026-11-08): "Whenever somebody starts a session, allow them to select from a dropdown 'dribbling,
// shooting, passing, etc.'. General things. There should also be time in minutes or hours that they worked in that
// area. Then at the end allow them to attach a photo or video of their session. For now this should be saved in their
// session logs."
//
// Profile ? START SESSION: pick the area (dropdown) ? a running clock (PAUSE / RESUME / FINISH, Live Activity) ?
// wrap-up: the time (hours + minutes, filled in from the clock, editable) + up to 4 photos/videos ? SAVE ? the usual
// SESSION DONE screen. It lands in the LOGGED list (`Completion.area` + `.media`), counts for XP, streak and team feed.
// Photos/videos stay ON THE PHONE only (Documents/SessionMedia) ? never in the cloud backup (notes/19, backup rule).
import AVKit
import PhotosUI
import PostHog
import SwiftUI
import UniformTypeIdentifiers

// MARK: - the areas

struct TrainingArea: Identifiable, Hashable, Codable {
    let id: String
    let name: String
    let icon: String

    static let all: [TrainingArea] = [
        .init(id: "dribbling", name: "Dribbling", icon: "figure.soccer"),
        .init(id: "shooting", name: "Shooting", icon: "target"),
        .init(id: "passing", name: "Passing", icon: "arrow.left.arrow.right"),
        .init(id: "crossing", name: "Crossing", icon: "arrow.turn.right.up"),
        .init(id: "first-touch", name: "First touch", icon: "soccerball.inverse"),
        .init(id: "juggling", name: "Juggling", icon: "soccerball"),
        .init(id: "weak-foot", name: "Weak foot", icon: "shoeprints.fill"),
        .init(id: "defending", name: "Defending", icon: "shield.fill"),
        .init(id: "heading", name: "Heading", icon: "arrow.up.circle.fill"),
        .init(id: "goalkeeping", name: "Goalkeeping", icon: "hand.raised.fill"),
        .init(id: "speed", name: "Speed", icon: "bolt.fill"),
        .init(id: "fitness", name: "Fitness", icon: "figure.run"),
        .init(id: "strength", name: "Strength", icon: "dumbbell.fill"),
        .init(id: "stretching", name: "Stretching", icon: "figure.flexibility"),
        .init(id: "game", name: "Scrimmage", icon: "sportscourt.fill"),
    ]
    /// Categories the player made with "+" (2026-11-08) ? on this phone, after the presets.
    static var custom: [TrainingArea] {
        get { (UserDefaults.standard.data(forKey: "sm.customAreas.v1")).flatMap { try? JSONDecoder().decode([TrainingArea].self, from: $0) } ?? [] }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: "sm.customAreas.v1") }
    }
    static var every: [TrainingArea] { all + custom }
    static func of(_ id: String?) -> TrainingArea? { every.first { $0.id == id } }
    /// Icons offered when making your own category.
    static let iconChoices = ["soccerball", "figure.soccer", "target", "flag.fill", "bolt.fill", "flame.fill", "star.fill",
                              "figure.run", "figure.walk", "figure.jumprope", "figure.core.training", "figure.cooldown",
                              "dumbbell.fill", "heart.fill", "timer", "brain.head.profile", "eye.fill", "hand.raised.fill",
                              "sportscourt.fill", "trophy.fill"]
}

/// One stretch of a session spent on one category.
struct SessionPart: Codable, Hashable {
    var area: String
    var name: String
    var icon: String
    var seconds: Int
    var minutes: Int { max(0, Int((Double(seconds) / 60).rounded())) }
}

// MARK: - photos + videos on the phone

enum SessionMedia {
    static var dir: URL {
        let d = URL.documentsDirectory.appending(path: "SessionMedia", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }
    static func url(_ name: String) -> URL { dir.appending(path: name) }
    static func exists(_ name: String) -> Bool { FileManager.default.fileExists(atPath: url(name).path) }
    static func isVideo(_ name: String) -> Bool { !name.hasSuffix(".jpg") }
    static func remove(_ names: [String]) { for n in names { try? FileManager.default.removeItem(at: url(n)) } }

    /// A picked photo or video ? a file in SessionMedia. Returns its file name.
    static func save(_ item: PhotosPickerItem) async -> String? {
        let video = item.supportedContentTypes.contains { $0.conforms(to: .movie) }
        if video, let m = try? await item.loadTransferable(type: PickedMovie.self) { return m.name }
        guard let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) else { return nil }
        let name = UUID().uuidString + ".jpg"
        guard let jpg = shrink(img, to: 2048).jpegData(compressionQuality: 0.82) else { return nil }
        do { try jpg.write(to: url(name)); return name } catch { return nil }
    }

    private static func shrink(_ img: UIImage, to side: CGFloat) -> UIImage {
        let s = img.size, k = min(1, side / max(s.width, s.height))
        guard k < 1 else { return img }
        let size = CGSize(width: s.width * k, height: s.height * k)
        return UIGraphicsImageRenderer(size: size).image { _ in img.draw(in: CGRect(origin: .zero, size: size)) }
    }

    /// Send one file to the team bucket (videos shrunk to a medium-quality mp4 first). Returns the stored path.
    static func upload(_ name: String, api: SupabaseREST) async -> String? {
        let src = url(name)
        guard FileManager.default.fileExists(atPath: src.path) else { return nil }
        if !isVideo(name) { return try? await api.uploadMedia(src, name: name, mime: "image/jpeg") }
        let out = URL.temporaryDirectory.appending(path: UUID().uuidString + ".mp4")
        guard let ex = AVAssetExportSession(asset: AVURLAsset(url: src), presetName: AVAssetExportPresetMediumQuality) else { return nil }
        do { try await ex.export(to: out, as: .mp4) } catch { return nil }
        defer { try? FileManager.default.removeItem(at: out) }
        let base = (name as NSString).deletingPathExtension + ".mp4"
        return try? await api.uploadMedia(out, name: base, mime: "video/mp4")
    }

    /// A still picture of the file (the photo itself, or a video's first frame).
    static func thumb(_ name: String) async -> UIImage? { await thumb(file: url(name)) }
    static func thumb(file u: URL) async -> UIImage? {
        guard isVideo(u.lastPathComponent) else { return UIImage(contentsOfFile: u.path) }
        let gen = AVAssetImageGenerator(asset: AVURLAsset(url: u))
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 600, height: 600)
        guard let cg = try? await gen.image(at: .zero).image else { return nil }
        return UIImage(cgImage: cg)
    }
}

/// A video from the photo library, copied straight into SessionMedia (videos are too big to load as Data).
struct PickedMovie: Transferable {
    let name: String
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .movie) { received in
            let ext = received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension.lowercased()
            let name = UUID().uuidString + "." + ext
            try FileManager.default.copyItem(at: received.file, to: SessionMedia.url(name))
            return PickedMovie(name: name)
        }
    }
}

/// One square tile: the picture (video = a play mark on it). Missing file (e.g. after a reinstall) = a quiet tile.
struct MediaTile: View {
    let name: String
    @State private var img: UIImage?
    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let img { Image(uiImage: img).resizable().scaledToFill() }
                else { C.char800.overlay { Image(systemName: "photo").font(.system(size: 22, weight: .bold)).foregroundStyle(C.muted) } }
            }
            .overlay {
                if SessionMedia.isVideo(name) {
                    Image(systemName: "play.fill").font(.system(size: 20, weight: .bold)).foregroundStyle(C.creme)
                        .frame(width: 44, height: 44).background(Circle().fill(C.char950.opacity(0.6)))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .task(id: name) { img = await SessionMedia.thumb(name) }
    }
}

/// Full screen: the photo, or the video playing.
struct MediaViewer: View {
    let name: String
    /// A file somewhere else (a teammate's, downloaded to the cache) ? wins over `name`.
    var file: URL? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?
    private var u: URL { file ?? SessionMedia.url(name) }
    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            if SessionMedia.isVideo(u.lastPathComponent) {
                VideoPlayer(player: player).ignoresSafeArea(edges: .bottom)
                    .onAppear { player = AVPlayer(url: u); player?.play() }
                    .onDisappear { player?.pause() }
            } else if let img = UIImage(contentsOfFile: u.path) {
                Image(uiImage: img).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            GlassIcon(symbol: "xmark", label: "Close") { dismiss() }.padding(16)
        }
    }
}

/// So a file name can drive `.fullScreenCover(item:)`.
struct MediaName: Identifiable { let id: String }

// MARK: - the flow

/// What to open over the whole app (MainTabs shows it): a blank session (Sessions tab START), or one already on a
/// category (START AGAIN, a teammate's session in the feed, the Map).
struct FreeRequest: Identifiable { let id = UUID(); var area: TrainingArea? }

@Observable
final class FreeStart {
    static let shared = FreeStart()
    var request: FreeRequest?
    func open(_ a: TrainingArea?) { Haptics.play(.kick); request = FreeRequest(area: a) }
}

// LIVE SESSIONS v2 (2026-11-08): "sessions should start as a blank canvas. A start session button should be there,
// and then from there let the user pick from presets of the category? with their ongoing time and live action saying
// that category, then let them add categories so say they're 30 mins into shooting, they can switch that to
// defending and it should show up in their session. Also add a '+' to create a category."
//
// One clock runs from START. Picking a category marks where it began; switching ends that stretch and starts the
// next (time before the first pick goes to the first category). FINISH ? each category's minutes (?/+ to fix) +
// photos/videos ? SAVE: logged with every part, posted to the teams with the media (session-media bucket).
struct FreeSession: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    private enum Step { case live, wrap, done }
    private struct Mark { var area: TrainingArea; var at: TimeInterval }

    @State private var step: Step = DebugRoute.parts.contains("wrap") ? .wrap : .live
    @State private var since: Date? = Date()
    @State private var banked: TimeInterval = 0
    @State private var marks: [Mark] = []
    @State private var parts: [SessionPart] = []
    @State private var making = false
    @State private var ending = false
    @State private var picked: [PhotosPickerItem] = []
    @State private var media: [String] = []
    @State private var loading = 0
    @State private var viewing: MediaName?
    @State private var customs = TrainingArea.custom
    private let preset: TrainingArea?

    init(area preset: TrainingArea? = nil) { self.preset = preset }

    private static let maxMedia = 4
    private func elapsed(_ now: Date = Date()) -> TimeInterval { banked + (since.map { now.timeIntervalSince($0) } ?? 0) }
    private var current: TrainingArea? { marks.last?.area }
    private var total: Int { parts.reduce(0) { $0 + $1.minutes } }

    var body: some View {
        ZStack {
            AppBackground().ignoresSafeArea()
            switch step {
            case .live: live.transition(.opacity)
            case .wrap: wrap.transition(.opacity)
            case .done:
                NavigationStack { SessionDone(path: .constant(NavigationPath())) { dismiss() } }
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: step)
        .onAppear(perform: begin)
        .sheet(isPresented: $making) { NewCategory { a in customs = TrainingArea.custom; pick(a) } }
        .fullScreenCover(item: $viewing) { MediaViewer(name: $0.id) }
        .confirmationDialog("End this session?", isPresented: $ending, titleVisibility: .visible) {
            if elapsed() >= 20 && current != nil { Button("Finish and log it") { finish() } }
            Button("Discard session", role: .destructive) { discard() }
        } message: { Text("Discard = nothing is logged.") }
    }

    // MARK: live

    private var live: some View {
        VStack(spacing: 0) {
            HStack {
                HStack(spacing: 8) {
                    Circle().fill(since == nil ? C.gold : C.brand).frame(width: 9, height: 9)
                        .shadow(color: (since == nil ? C.gold : C.brand).opacity(0.8), radius: 5)
                    Text(since == nil ? "PAUSED" : "LIVE").font(F.round(14, .heavy)).kerning(1.4)
                        .foregroundStyle(since == nil ? C.gold : C.brand)
                }
                Spacer()
                GlassIcon(symbol: "xmark", label: "End or discard the session") { ending = true }
            }
            .padding(.top, 8)

            TimelineView(.periodic(from: .now, by: 1)) { t in
                let e = elapsed(t.date)
                VStack(spacing: 14) {
                    if let a = current {
                        AreaIcon(area: a, size: 96)
                            .id(a.id)
                            .transition(.scale(0.7).combined(with: .opacity))
                        Disp(a.name.uppercased(), size: 40).lineLimit(1).minimumScaleFactor(0.6)
                        Text(clock(Int(e - (marks.last?.at ?? 0))))
                            .font(F.display(78)).monospacedDigit()
                            .foregroundStyle(since == nil ? C.gold : C.creme)
                            .contentTransition(.numericText())
                        if marks.count > 1 || (marks.last?.at ?? 0) > 0 {
                            Text("TOTAL \(clock(Int(e)))").font(F.round(15, .heavy)).kerning(1.2).foregroundStyle(C.muted)
                        }
                    } else {
                        Text(clock(Int(e))).font(F.display(78)).monospacedDigit().foregroundStyle(C.creme)
                            .contentTransition(.numericText())
                        Disp("WHAT ARE YOU WORKING ON?", size: 24).multilineTextAlignment(.center)
                    }
                    if marks.count > 0 { strip(e).padding(.top, 6) }
                }
                .frame(maxWidth: .infinity)
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: current?.id)
            }
            .padding(.top, 10)

            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 16) {
                    ForEach(TrainingArea.all + customs) { a in
                        Button { pick(a) } label: { chip(a, on: a.id == current?.id) }
                            .buttonStyle(.press(.stud))
                            .accessibilityLabel(a.id == current?.id ? "\(a.name), now" : "Switch to \(a.name)")
                    }
                    Button { making = true } label: {
                        VStack(spacing: 7) {
                            Image(systemName: "plus").font(.system(size: 22, weight: .heavy)).foregroundStyle(C.brand)
                                .frame(width: 54, height: 54)
                                .background(RoundedRectangle(cornerRadius: 17, style: .continuous).fill(C.char800))
                            Text("New").font(F.round(12, .bold)).foregroundStyle(C.muted).lineLimit(1)
                        }
                    }
                    .buttonStyle(.press(.stud))
                    .accessibilityLabel("Make a new category")
                }
                .padding(.vertical, 18)
            }
            .scrollIndicators(.hidden)
            .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.04),
                                         .init(color: .black, location: 0.9), .init(color: .clear, location: 1)],
                                 startPoint: .top, endPoint: .bottom))

            Group {
                if since != nil {
                    Button { pause() } label: { Label("PAUSE", systemImage: "pause.fill") }
                        .buttonStyle(.gameLarge(.charcoal, feel: .latch))
                } else {
                    HStack(spacing: 12) {
                        Button { resume() } label: { Label("RESUME", systemImage: "play.fill") }
                            .buttonStyle(.gameLarge(.charcoal, feel: .latch))
                        Button { finish() } label: { Label("FINISH", systemImage: "checkmark") }
                            .buttonStyle(.gameLarge(.gold, feel: .goal))
                            .disabled(current == nil)
                            .opacity(current == nil ? 0.45 : 1)
                    }
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: since == nil)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }

    /// The session so far: one green stretch per category, sized by its time.
    private func strip(_ e: TimeInterval) -> some View {
        let segs = segments(e)
        let sum = max(1, segs.reduce(0) { $0 + $1.1 })
        return GeometryReader { g in
            HStack(spacing: 3) {
                ForEach(Array(segs.enumerated()), id: \.offset) { i, s in
                    Capsule().fill(i == segs.count - 1 ? C.brand : C.brandMid.opacity(0.55))
                        .frame(width: max(6, (g.size.width - CGFloat(segs.count - 1) * 3) * s.1 / sum))
                }
            }
        }
        .frame(height: 6)
        .frame(maxWidth: 260)
    }

    private func chip(_ a: TrainingArea, on: Bool) -> some View {
        VStack(spacing: 7) {
            AreaIcon(area: a, size: 54, dim: !on)
            Text(a.name).font(F.round(12, .bold)).foregroundStyle(on ? C.creme : C.muted).lineLimit(1).minimumScaleFactor(0.7)
        }
        .scaleEffect(on ? 1.06 : 1)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: on)
    }

    // MARK: wrap-up

    private var wrap: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                VStack(alignment: .leading, spacing: 4) {
                    Disp("NICE WORK", size: 40)
                    Text(minText(Double(total))).font(F.display(26)).foregroundStyle(C.brand)
                }
                .padding(.top, 16)

                VStack(spacing: 14) {
                    ForEach(parts.indices, id: \.self) { i in partRow(i) }
                }

                VStack(alignment: .leading, spacing: 12) {
                    Disp("PHOTOS + VIDEOS", size: 20)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                        ForEach(media, id: \.self) { n in
                            Button { viewing = MediaName(id: n) } label: { MediaTile(name: n) }
                                .buttonStyle(.press(.stud))
                                .overlay(alignment: .topTrailing) {
                                    Button { SessionMedia.remove([n]); media.removeAll { $0 == n } } label: {
                                        Image(systemName: "xmark").font(.system(size: 11, weight: .heavy)).foregroundStyle(C.creme)
                                            .frame(width: 26, height: 26).background(Circle().fill(C.char950.opacity(0.8)))
                                    }
                                    .padding(6)
                                    .accessibilityLabel("Remove")
                                }
                        }
                        ForEach(0..<loading, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(C.char800)
                                .aspectRatio(1, contentMode: .fit)
                                .overlay { ProgressView().tint(C.creme) }
                        }
                        if media.count + loading < Self.maxMedia {
                            PhotosPicker(selection: $picked, maxSelectionCount: Self.maxMedia - media.count - loading,
                                         matching: .any(of: [.images, .videos])) {
                                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(C.char850)
                                    .aspectRatio(1, contentMode: .fit)
                                    .overlay {
                                        Image(systemName: "plus").font(.system(size: 26, weight: .heavy)).foregroundStyle(C.brand)
                                    }
                            }
                            .accessibilityLabel("Add a photo or video")
                        }
                    }
                    if !Team.shared.teams.isEmpty && !media.isEmpty {
                        Text("They stay with this session.").font(F.round(14, .semibold)).foregroundStyle(C.muted)
                    }
                }

                VStack(spacing: 14) {
                    Button { save() } label: { Label("SAVE SESSION", systemImage: "checkmark") }
                        .buttonStyle(.gameLarge(.brand, feel: .goal))
                        .disabled(total < 1 || loading > 0)
                        .opacity(total < 1 || loading > 0 ? 0.45 : 1)
                    Button("Discard session", role: .destructive) { discard() }
                        .font(F.round(16, .bold)).foregroundStyle(C.muted)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 30)
        }
        .scrollIndicators(.hidden)
        .onChange(of: picked) { _, items in
            guard !items.isEmpty else { return }
            picked = []
            loading += items.count
            Task {
                for it in items {
                    if let n = await SessionMedia.save(it) { media.append(n) }
                    loading -= 1
                }
                Haptics.play(.pop)
            }
        }
    }

    /// One category's time: icon, name, ? minutes +.
    private func partRow(_ i: Int) -> some View {
        let p = parts[i]
        let a = TrainingArea(id: p.area, name: p.name, icon: p.icon)
        return HStack(spacing: 14) {
            AreaIcon(area: a, size: 48)
            Text(p.name).font(F.round(18, .bold)).foregroundStyle(C.creme).lineLimit(1)
            Spacer(minLength: 6)
            step(i, -1, "minus")
            Text("\(p.minutes)").font(F.display(24)).monospacedDigit().foregroundStyle(C.creme)
                .frame(minWidth: 40).contentTransition(.numericText())
            Text("min").font(F.round(14, .semibold)).foregroundStyle(C.muted)
            step(i, 1, "plus")
        }
    }

    private func step(_ i: Int, _ d: Int, _ sym: String) -> some View {
        Button {
            parts[i].seconds = max(0, (parts[i].minutes + d) * 60)
        } label: {
            Image(systemName: sym).font(.system(size: 14, weight: .heavy)).foregroundStyle(C.creme)
                .frame(width: 34, height: 34).background(Circle().fill(C.char800))
        }
        .buttonStyle(.press(.stud))
        .accessibilityLabel(d > 0 ? "One more minute" : "One less minute")
    }

    // MARK: flow

    private func segments(_ e: TimeInterval) -> [(TrainingArea, Double)] {
        marks.enumerated().map { i, m in
            (m.area, max(0, (i + 1 < marks.count ? marks[i + 1].at : e) - m.at))
        }
    }

    private var liveState: SessionActivityAttributes.ContentState {
        let e = elapsed()
        return .init(drill: current?.name ?? "Training", dose: "Live session", index: 0, count: 1,
                     startedAt: Date().addingTimeInterval(-e), paused: since == nil ? Int(e) : nil)
    }

    private func begin() {
        if step == .wrap {   // DEBUG `free:x:wrap`
            parts = [SessionPart(area: "shooting", name: "Shooting", icon: "target", seconds: 30 * 60),
                     SessionPart(area: "defending", name: "Defending", icon: "shield.fill", seconds: 17 * 60)]
            return
        }
        guard marks.isEmpty && banked == 0 else { return }
        PostHogSDK.shared.capture("session_started", properties: ["drill_count": 0, "session_type": "free", "area": preset?.id ?? "none"])
        since = Date()
        if let preset { marks = [Mark(area: preset, at: 0)] }
        LiveRun.start("Session", liveState)
        if TEAMS_ON { SessionSpot.shared.refresh() }   // MAP tab: where this session is played
    }

    /// Start (or switch to) a category. The first pick also takes the time before it.
    private func pick(_ a: TrainingArea) {
        guard a.id != current?.id else { return }
        Haptics.play(.latch)
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            marks.append(Mark(area: a, at: marks.isEmpty ? 0 : elapsed()))
        }
        LiveRun.update(liveState)
    }
    private func pause() { banked = elapsed(); since = nil; LiveRun.update(liveState) }
    private func resume() { since = Date(); LiveRun.update(liveState) }

    private func finish() {
        guard current != nil else { return }
        if TEAMS_ON { SessionSpot.shared.refresh() }
        banked = elapsed()
        since = nil
        LiveRun.end()
        // merge repeat visits to the same category, keep first-seen order
        var out: [SessionPart] = []
        for (a, secs) in segments(banked) {
            if let j = out.firstIndex(where: { $0.area == a.id }) { out[j].seconds += Int(secs) }
            else { out.append(SessionPart(area: a.id, name: a.name, icon: a.icon, seconds: Int(secs))) }
        }
        // anything that ran at all counts as at least a minute
        for j in out.indices where out[j].seconds >= 20 && out[j].minutes == 0 { out[j].seconds = 60 }
        parts = out.filter { $0.seconds >= 20 }
        if parts.isEmpty, let a = current { parts = [SessionPart(area: a.id, name: a.name, icon: a.icon, seconds: 60)] }
        step = .wrap
    }

    private func save() {
        let kept = parts.filter { $0.minutes > 0 }
        guard total >= 1, let top = kept.max(by: { $0.seconds < $1.seconds }) else { return }
        let name = kept.count <= 2 ? kept.map(\.name).joined(separator: " + ") : "\(kept[0].name) + \(kept.count - 1) more"
        let secs = kept.reduce(0) { $0 + $1.minutes * 60 }
        let k = dateKey(Date())
        store.trained[k] = (store.trained[k] ?? 0) + Double(secs) / 60
        store.complete(name, minutes: Double(total), seconds: secs, area: top.area, media: media.isEmpty ? nil : media, parts: kept)
        PostHogSDK.shared.capture("session_completed", properties: [
            "completed_drill_count": 0, "duration_seconds": secs, "session_type": "free",
            "area": top.area, "category_count": kept.count, "media_count": media.count
        ])
        Team.shared.log(session: name, minutes: total, items: [], pro: nil, area: top.area, parts: kept, media: media)
        Team.shared.syncStats(store)
        ActiveRun.shared.finished += 1
        step = .done
    }
    private func discard() {
        LiveRun.end()
        SessionMedia.remove(media)
        Haptics.play(.unlatch)
        dismiss()
    }
}

/// "+" ? make your own category: a name and an icon. Saved on this phone, shows up after the presets.
struct NewCategory: View {
    var made: (TrainingArea) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var icon = "soccerball"
    @FocusState private var typing: Bool

    var body: some View {
        let clean = name.trimmingCharacters(in: .whitespaces)
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 16) {
                AreaIcon(area: TrainingArea(id: "new", name: clean, icon: icon), size: 64)
                TextField("", text: $name, prompt: Text("Name it").foregroundStyle(C.muted))
                    .font(F.display(28)).foregroundStyle(C.creme)
                    .textInputAutocapitalization(.words)
                    .focused($typing)
                    .submitLabel(.done)
                    .onChange(of: name) { _, v in if v.count > 20 { name = String(v.prefix(20)) } }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 5), spacing: 12) {
                ForEach(TrainingArea.iconChoices, id: \.self) { sym in
                    Button { icon = sym; Haptics.play(.stud) } label: {
                        AreaIcon(area: TrainingArea(id: sym, name: "", icon: sym), size: 52, dim: sym != icon)
                    }
                    .buttonStyle(.press(.stud))
                }
            }
            Spacer(minLength: 0)
            Button {
                let a = TrainingArea(id: "c-" + UUID().uuidString.prefix(8).lowercased(), name: clean, icon: icon)
                TrainingArea.custom.append(a)
                made(a)
                dismiss()
            } label: { Label("ADD", systemImage: "plus") }
                .buttonStyle(.gameLarge(.brand, feel: .goal))
                .disabled(clean.isEmpty)
                .opacity(clean.isEmpty ? 0.45 : 1)
        }
        .padding(22)
        .padding(.top, 10)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .presentationBackground(C.char900)
        .onAppear { typing = true }
    }
}
