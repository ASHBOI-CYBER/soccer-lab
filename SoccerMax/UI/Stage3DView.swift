// A 3D viewport. The ONLY web content in the app: a three.js canvas (Stage/stage.js, built from src/stage)
// with no HTML UI at all. The web view can't scroll, bounce, zoom or show indicators ? it's a canvas.
// SwiftUI owns every control and pushes the state in through window.SM.set(...).
import SwiftUI
import WebKit

enum StageParams: Equatable {
    /// A drill's setup: a still 3D picture (cones, goal, players, the line). Drag to turn it.
    case setup(id: String, autoRotate: Bool = true)
    case drill(scene: String, speed: Double = 1, mirror: Bool = false, angle: String = "Auto", orbit: Bool = false,
               autoRotate: Bool = true, seek: Double? = nil, seekId: Int = 0, report: Bool = false)
    case penalty(hold: Double, kicked: Bool)
    case portrait(tier: String)
    /// The Matchday film (notes/22): one clip of a real match; SwiftUI is the player around it.
    case film(FilmStage)

    var json: String {
        var d: [String: Any]
        switch self {
        case let .setup(id, autoRotate):
            d = ["kind": "setup", "id": id, "autoRotate": autoRotate]
        case let .drill(scene, speed, mirror, angle, orbit, autoRotate, seek, seekId, report):
            d = ["kind": "drill", "scene": scene, "speed": speed, "mirror": mirror, "angle": angle, "orbit": orbit,
                 "autoRotate": autoRotate, "seekId": seekId, "report": report]
            if let seek { d["seek"] = seek }
        case let .penalty(hold, kicked):
            d = ["kind": "penalty", "hold": hold, "kicked": kicked]
        case let .portrait(tier):
            d = ["kind": "portrait", "tier": tier]
        case let .film(f):
            d = f.dict
        }
        let data = try! JSONSerialization.data(withJSONObject: d)
        return String(data: data, encoding: .utf8)!
    }
}

struct Stage3DView: UIViewRepresentable {
    var params: StageParams
    /// Drag to orbit / pinch to zoom. Off = touches pass straight through to SwiftUI.
    var interactive = false
    var onTime: ((Double) -> Void)? = nil
    var onGoal: (() -> Void)? = nil
    /// Any other message from the stage (the film's clock, its callout point, a clip ending).
    var onMessage: (([String: Any]) -> Void)? = nil

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.userContentController.add(WeakHandler(context.coordinator), name: "sm")
        // Stage errors land in the Xcode console instead of failing silently.
        cfg.userContentController.addUserScript(WKUserScript(
            source: "window.onerror=function(m,s,l){webkit.messageHandlers.sm.postMessage({type:'log',m:String(m)+' @'+l})}",
            injectionTime: .atDocumentStart, forMainFrameOnly: true))
        cfg.suppressesIncrementalRendering = true
        let web = WKWebView(frame: .zero, configuration: cfg)
        web.isOpaque = false
        web.backgroundColor = .clear
        web.scrollView.backgroundColor = .clear
        web.scrollView.isScrollEnabled = false
        web.scrollView.bounces = false
        web.scrollView.showsVerticalScrollIndicator = false
        web.scrollView.showsHorizontalScrollIndicator = false
        web.scrollView.contentInsetAdjustmentBehavior = .never
        web.scrollView.pinchGestureRecognizer?.isEnabled = false
        web.allowsLinkPreview = false
        web.allowsBackForwardNavigationGestures = false
        web.isUserInteractionEnabled = interactive
        #if DEBUG
        if #available(iOS 16.4, *) { web.isInspectable = true }
        #endif
        context.coordinator.web = web
        web.navigationDelegate = context.coordinator
        context.coordinator.sync(self)
        let dir = Bundle.main.url(forResource: "Stage", withExtension: nil)!
        web.loadFileURL(dir.appendingPathComponent("stage.html"), allowingReadAccessTo: dir)
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {
        web.isUserInteractionEnabled = interactive
        context.coordinator.sync(self)
    }

    static func dismantleUIView(_ web: WKWebView, coordinator: Coordinator) {
        web.configuration.userContentController.removeScriptMessageHandler(forName: "sm")
        web.stopLoading()
    }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        /// iOS can kill a hidden web view's process to save memory (the pledge stage waits hidden for a few pages):
        /// it would stay blank, so load it again and say so (the pledge shows its still until 'drawn' comes back).
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            ready = false
            sent = nil
            onMessage?(["type": "lost"])
            webView.reload()
        }

        weak var web: WKWebView?
        var ready = false
        var sent: StageParams?
        var params: StageParams?
        var onTime: ((Double) -> Void)?
        var onGoal: (() -> Void)?
        var onMessage: (([String: Any]) -> Void)?

        func sync(_ v: Stage3DView) {
            params = v.params
            onTime = v.onTime
            onGoal = v.onGoal
            onMessage = v.onMessage
            push()
        }

        func push() {
            guard ready, let params, params != sent else { return }
            sent = params
            web?.evaluateJavaScript("window.SM && SM.set(\(params.json))")
        }

        func userContentController(_ c: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
            switch type {
            case "ready":
                ready = true
                sent = nil
                push()
            case "time":
                if let t = body["t"] as? Double { onTime?(t) }
                onMessage?(body)
            case "goal":
                onGoal?()
            case "log":
                NSLog("[Stage] %@", String(describing: body["m"] ?? ""))
            default: onMessage?(body)
            }
        }
    }
}

/// What the film stage needs: both kits, both real lineups (grid slots), the clip, play/pause, a seek.
struct FilmStage: Equatable {
    struct Clip: Equatable {
        var id: Int
        var kind: String
        var side: String
        var scorer: String?
        var assist: String?
        var star: String?
        var len: Double
        var seed: Int
        var focus: String?
        var focusAt: Double
        var stops: [Stop] = []
        var play: String? = nil       // how the goal was made (cross, cutback, pocket, through, solo, long, lofted)
        var end: String? = nil        // key pass / big save: how the shot at the end goes (save, wide)
        var card: String? = nil       // card clips: yellow | red (the foul drawing is `play`)
    }
    /// A freeze on the play's key frame (notes/22 HIGHLIGHT REEL): anchor 'start' | 'pass' | 'strike' + off seconds.
    struct Stop: Equatable {
        var anchor: String
        var off: Double
        var hold: Double
        var marks: [String]
    }
    var home = "#F2F2F2", away = "#1B2A4A", homeGk = "#E8B21E", awayGk = "#2B2B2B"
    var homeGrid: [String]
    var awayGrid: [String]
    var clip: Clip
    var playing: Bool
    var seek: Double
    var seekId: Int

    var dict: [String: Any] {
        var c: [String: Any] = ["id": clip.id, "kind": clip.kind, "side": clip.side, "len": clip.len, "seed": clip.seed, "focusAt": clip.focusAt]
        if let v = clip.scorer { c["scorer"] = v }
        if let v = clip.assist { c["assist"] = v }
        if let v = clip.star { c["star"] = v }
        if let v = clip.focus { c["focus"] = v }
        if let v = clip.play { c["play"] = v }
        if let v = clip.end { c["end"] = v }
        if let v = clip.card { c["card"] = v }
        c["stops"] = clip.stops.map { ["anchor": $0.anchor, "off": $0.off, "hold": $0.hold, "marks": $0.marks] as [String: Any] }
        let d: [String: Any] = ["kind": "film", "home": home, "away": away, "homeGk": homeGk, "awayGk": awayGk,
                                "homeGrid": homeGrid, "awayGrid": awayGrid, "clip": c, "playing": playing,
                                "seek": seek, "seekId": seekId]
        return d
    }
}

/// WKUserContentController retains its handlers; this breaks the cycle.
private final class WeakHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    init(_ t: WKScriptMessageHandler) { target = t }
    func userContentController(_ c: WKUserContentController, didReceive m: WKScriptMessage) {
        target?.userContentController(c, didReceive: m)
    }
}

/// A rounded 3D stage box with the floor fading into the card (what every hero uses).
struct StageBox: View {
    var params: StageParams
    var height: CGFloat
    var interactive = false
    var onTime: ((Double) -> Void)? = nil

    var body: some View {
        Group {
            // a drill with a Blender video plays it (notes/25); everything else is the live stage
            if case let .setup(id, _) = params, DrillVideo.url(id) != nil || Library.shared.drill(id).board != nil {
                DrillStageView(id: id, interactive: interactive)
            } else {
                Stage3DView(params: params, interactive: interactive, onTime: onTime)
            }
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
    }
}
