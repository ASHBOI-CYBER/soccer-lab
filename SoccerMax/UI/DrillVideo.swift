// Drill videos made in Blender (notes/25): when a drill has one, its 3D box plays the video ? a silent, seamless loop
// on the page color ? instead of the live three.js stage. Drills without a video yet keep the live stage.
import AVFoundation
import SwiftUI

enum DrillVideo {
    /// The bundled loop for a drill, if it has been rendered (Resources/DrillVideos/<id>.mp4).
    static func url(_ id: String) -> URL? {
        Bundle.main.url(forResource: id, withExtension: "mp4", subdirectory: "DrillVideos")
    }
}

/// A muted video that loops forever with no gap, filling its box.
struct LoopingVideo: UIViewRepresentable {
    let url: URL
    /// See-through video (HEVC with alpha, e.g. the mascot): no backdrop, keep the picture's shape.
    var clear = false
    /// Show the whole picture (no crop) ? the full-screen session player. The backdrop matches the video's own.
    var fit = false
    /// Freeze on the current frame (the session player's pause button) ? false plays on from there.
    var paused = false
    /// Called once the first frame is on screen (so a still can stand in until then ? no blank pop-in).
    var onReady: (() -> Void)? = nil

    func makeUIView(context: Context) -> PlayerView {
        let v = PlayerView()
        v.onReady = onReady
        if clear {
            v.backgroundColor = .clear
            v.isOpaque = false
            v.gravity = .resizeAspect
        } else {
            v.backgroundColor = UIColor(red: 0x16 / 255, green: 0x19 / 255, blue: 0x1C / 255, alpha: 1)  // C.char900, the video's own backdrop
        }
        if fit { v.gravity = .resizeAspect }
        v.play(url)
        v.setPaused(paused)
        return v
    }

    func updateUIView(_ v: PlayerView, context: Context) {
        if v.url != url { v.play(url) }
        v.setPaused(paused)
    }

    static func dismantleUIView(_ v: PlayerView, coordinator: ()) { v.stop() }

    final class PlayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        private var layerPlayer: AVPlayerLayer { layer as! AVPlayerLayer }
        private var player: AVQueuePlayer?
        private var looper: AVPlayerLooper?
        private(set) var url: URL?
        var gravity: AVLayerVideoGravity = .resizeAspectFill
        var onReady: (() -> Void)?
        private var readyWatch: NSKeyValueObservation?

        func play(_ url: URL) {
            stop()
            self.url = url
            let item = AVPlayerItem(url: url)
            let p = AVQueuePlayer()
            p.isMuted = true
            p.preventsDisplaySleepDuringVideoPlayback = false
            looper = AVPlayerLooper(player: p, templateItem: item)
            layerPlayer.player = p
            layerPlayer.videoGravity = gravity
            player = p
            readyWatch = layerPlayer.observe(\.isReadyForDisplay, options: [.initial, .new]) { [weak self] l, _ in
                guard l.isReadyForDisplay else { return }
                DispatchQueue.main.async { self?.onReady?(); self?.readyWatch = nil }
            }
            p.play()
        }

        func setPaused(_ p: Bool) {
            guard let player else { return }
            if p { player.pause() } else if player.rate == 0 { player.play() }
        }

        func stop() {
            player?.pause()
            looper = nil
            player = nil
            layerPlayer.player = nil
        }
    }
}

/// The drill's 3D box: the Blender video when there is one, else the live stage (still setup or three.js animation).
struct DrillStageView: View {
    let id: String
    var interactive = false
    var fit = false
    var paused = false

    var body: some View {
        if let url = DrillVideo.url(id) {
            LoopingVideo(url: url, fit: fit, paused: paused)
        } else if let board = Library.shared.drill(id).board {
            DrillBoard(board: board)  // no video: the flat coach's board, so it never looks like a paused video
        } else {
            Stage3DView(params: .setup(id: id), interactive: interactive)
        }
    }
}


/// A still from a drill's own video (the current 3D guy in the kit) for thumbnails ? the bundled `Covers/*.jpg` show
/// the retired creme mannequin (2026-10-30). Made once per video (1 s in), kept in memory and in Caches on disk, so
/// re-rendered videos get fresh frames by themselves (the key carries the video's size + date).
enum DrillFrames {
    private static let mem = NSCache<NSString, UIImage>()
    private static let dir: URL = {
        let d = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("DrillFrames")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()

    private static func key(_ id: String, _ url: URL) -> String {
        let a = try? FileManager.default.attributesOfItem(atPath: url.path)
        let size = (a?[.size] as? NSNumber)?.intValue ?? 0
        let date = Int((a?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0)
        return "\(id)-\(size)-\(date)-c3"   // c3 = cropped to the players (2026-10-30)
    }

    /// The bundled poster (`DrillVideos/<id>.jpg`, made by `app/pathtrace/posters.py`): the best frame, zoomed in on the
    /// player and lifted ? wide drills used to be a few dots in a dark square (2026-10-30, "easy to see").
    private static func poster(_ id: String) -> UIImage? {
        let k = "poster-\(id)" as NSString
        if let hit = mem.object(forKey: k) { return hit }
        guard let url = Bundle.main.url(forResource: id, withExtension: "jpg", subdirectory: "DrillVideos"),
              let img = UIImage(contentsOfFile: url.path) else { return nil }
        mem.setObject(img, forKey: k)
        return img
    }

    static func cached(_ id: String) -> UIImage? {
        if let p = poster(id) { return p }
        guard let url = DrillVideo.url(id) else { return nil }
        return mem.object(forKey: key(id, url) as NSString)
    }

    static func frame(_ id: String) async -> UIImage? {
        if let p = poster(id) { return p }
        guard let url = DrillVideo.url(id) else { return nil }
        let k = key(id, url)
        if let hit = mem.object(forKey: k as NSString) { return hit }
        let file = dir.appendingPathComponent(k + ".jpg")
        if let d = try? Data(contentsOf: file), let img = UIImage(data: d) {
            mem.setObject(img, forKey: k as NSString)
            return img
        }
        let gen = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        gen.appliesPreferredTrackTransform = true
        guard let cg = try? await gen.image(at: CMTime(seconds: 1.2, preferredTimescale: 600)).image else { return nil }
        let crop = UIImage(cgImage: focus(cg))
        let side = min(300, crop.size.width)
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        let img = UIGraphicsImageRenderer(size: CGSize(width: side, height: side * crop.size.height / crop.size.width), format: fmt)
            .image { _ in crop.draw(in: CGRect(x: 0, y: 0, width: side, height: side * crop.size.height / crop.size.width)) }
        mem.setObject(img, forKey: k as NSString)
        if let d = img.jpegData(compressionQuality: 0.8) { try? d.write(to: file) }
        return img
    }
}

extension DrillFrames {
    /// Crops a frame to the players so they FILL a small thumbnail (user, 2026-10-30: "make sure the previews are good
    /// and easy to see" ? wide drills showed a tiny guy in a big dark box). Finds the skin + shirt pixels (creme skin,
    /// kit green) on a small copy, boxes them, pads for the legs/ball, and cuts a square around that.
    static func focus(_ cg: CGImage) -> CGImage {
        let n = 96
        guard let ctx = CGContext(data: nil, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return cg }
        ctx.interpolationQuality = .low
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: n, height: n))
        guard let px = ctx.data?.assumingMemoryBound(to: UInt8.self) else { return cg }
        var x0 = n, y0 = n, x1 = -1, y1 = -1
        for y in 0..<n {
            for x in 0..<n {
                let i = (y * n + x) * 4
                let r = Int(px[i]), g = Int(px[i + 1]), b = Int(px[i + 2])
                let skin = r > 165 && g > 150 && b > 125 && r - b > 12 && r - b < 70       // creme mannequin skin
                let shirt = g > 150 && g - r > 70 && g - b > 40 && r < 120                 // the green kit
                if skin || shirt { x0 = min(x0, x); x1 = max(x1, x); y0 = min(y0, y); y1 = max(y1, y) }
            }
        }
        guard x1 >= x0, y1 >= y0 else { return cg }
        // CGContext rows run bottom-up; flip to image space
        let top = n - 1 - y1, bottom = n - 1 - y0
        let w = CGFloat(x1 - x0 + 1), h = CGFloat(bottom - top + 1)
        // the box already holds head ? green boots; a small pad for the ball and some air
        var side = max(w, h) * 1.14 + 4
        side = min(CGFloat(n), max(side, CGFloat(n) * 0.34))
        let cx = CGFloat(x0) + w / 2, cy = CGFloat(top) + h / 2 + h * 0.03
        var ox = cx - side / 2, oy = cy - side / 2
        ox = min(max(0, ox), CGFloat(n) - side); oy = min(max(0, oy), CGFloat(n) - side)
        let k = CGFloat(cg.width) / CGFloat(n), kh = CGFloat(cg.height) / CGFloat(n)
        let rect = CGRect(x: ox * k, y: oy * kh, width: side * k, height: side * kh).integral
        return cg.cropping(to: rect) ?? cg
    }
}

/// A drill thumbnail from its video; `placeholder` until the frame is ready (or when there's no video).
struct DrillFrameImage<Placeholder: View>: View {
    let id: String
    @ViewBuilder var placeholder: Placeholder
    @State private var img: UIImage?

    var body: some View {
        ZStack {
            if let shown = img ?? DrillFrames.cached(id) {
                Image(uiImage: shown).resizable().scaledToFill()
            } else {
                placeholder
            }
        }
        .task(id: id) {
            guard img == nil, DrillFrames.cached(id) == nil else { return }
            if let f = await DrillFrames.frame(id) { withAnimation(.easeOut(duration: 0.15)) { img = f } }
        }
    }
}
