// Premade session pictures (notes/23): a real player's photo (Wikimedia Commons, bundled in Resources/Players, credited
// on the page) or, for a technique session, the 3D guy mid-move (Resources/Technique). Crops keep the face in frame.
import SwiftUI
import UIKit

/// Scale-to-fill that keeps a focal point in frame (scaledToFill always centres).
struct FocalFill: View {
    let image: UIImage
    let focus: CGPoint
    let size: CGSize
    var body: some View {
        let s = max(size.width / max(1, image.size.width), size.height / max(1, image.size.height))
        let w = image.size.width * s, h = image.size.height * s
        let x = min(0, max(size.width - w, size.width / 2 - focus.x * w))
        let y = min(0, max(size.height - h, size.height / 2 - focus.y * h))
        Image(uiImage: image).resizable().interpolation(.high)
            .frame(width: w, height: h)
            .offset(x: x, y: y)
            .frame(width: size.width, height: size.height, alignment: .topLeading)
    }
}

/// A premade session's picture, filling its frame around the subject.
struct PremadeArt: View {
    let pro: ProSession
    /// Small card = the tile-size picture (already decoded at launch); false only on the session page's hero.
    var tile = true
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .topLeading) {
                DayHero<EmptyView>.floor
                if let img = pro.image(tile: tile) {
                    FocalFill(image: img, focus: pro.focus, size: g.size)
                        // photos graded a touch toward the app's look; the 3D stills are already in it
                        .saturation(pro.isPlayer ? 0.9 : 1)
                        .contrast(pro.isPlayer ? 1.05 : 1)
                }
            }
        }
        .clipped()
        .accessibilityHidden(true)
    }
}
