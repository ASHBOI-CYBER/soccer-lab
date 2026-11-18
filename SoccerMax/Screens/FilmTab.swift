// FILM tab (SOCCER LAB, 2026-11-12). The player reviews their own clip, two ways:
//   AI REVIEW (2026-11-15, the main one): up to 8 still frames from the clip + the phone's body reading go to
//     supabase/functions/film-review (Claude), which returns a score, what went well, what to fix with drills from
//     the app, and cues. Needs sign-in and the AI yes (AIVision.swift); a daily allowance. The video stays here.
//   QUESTIONS (no clip needed): tick what went wrong; a fixed table (FilmRules in LabData.swift) picks the drills.
// Either way the drills join the Fix List on the Training tab.
import AVKit
import CoreTransferable
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// A video picked from Photos, copied into the app's own film folder.
struct ClipFile: Transferable {
    let name: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .movie) { received in
            let ext = received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension
            let name = UUID().uuidString + "." + ext
            try FileManager.default.copyItem(at: received.file, to: FilmFiles.url(name))
            return ClipFile(name: name)
        }
    }
}

struct FilmTab: View {
    @Environment(AppStore.self) private var store
    @State private var lab = Lab.shared
    // test builds: `-route tab:film:review` / `:questions` / `:result` open the review sheet on that step
    @State private var adding = ["review", "questions", "result", "airesult"].contains { DebugRoute.parts.contains($0) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    TabHeader("Film")
                    Text("Review your own game and get the drills that fix it.")
                        .font(F.round(14, .medium)).foregroundStyle(C.muted).padding(.top, -20).padding(.horizontal, 4)
                    intro
                    steps
                    if lab.reviews.isEmpty { empty } else { history }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
            .tabRoot("Film")
            .navigationDestination(for: FilmReview.self) { FilmReviewPage(review: $0) }
            .navigationDestination(for: Drill.self) { DrillDetail(drill: $0) }
            .page()
        }
        .sheet(isPresented: $adding) {
            FilmReviewSheet(position: store.answers.position)
        }
    }

    private var intro: some View {
        LabPanel {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Image(systemName: "video.fill").font(.system(size: 20, weight: .bold)).foregroundStyle(C.brandHi)
                        .frame(width: 48, height: 48).background(Circle().fill(C.brand.opacity(0.18)))
                    VStack(alignment: .leading, spacing: 2) {
                        Disp("AI film review", size: 24)
                        Text(AIUsage.shared.line("film")).font(F.round(13, .semibold)).foregroundStyle(C.muted)
                    }
                }
                Text("Upload a clip of yourself. The AI looks at your technique frame by frame, scores it, and tells you what went well, what to fix and which drills to do.")
                    .font(F.round(15, .semibold)).foregroundStyle(C.creme2)
                    .fixedSize(horizontal: false, vertical: true)
                Button { adding = true } label: { Label("REVIEW A CLIP", systemImage: "plus") }
                    .buttonStyle(.game(.brand))
            }
        }
    }

    private var steps: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("How it works").font(.system(size: 20, weight: .heavy)).foregroundStyle(C.creme)
            HStack(alignment: .top, spacing: 10) {
                step(1, "Upload", "A clip of a touch, pass, shot, dribble or run.", "video.badge.plus")
                step(2, "AI review", "Frame by frame: your body, the ball, your choices.", "sparkles")
                step(3, "Your plan", "A score, what to fix, and the drills to do.", "figure.soccer")
            }
        }
    }

    private func step(_ n: Int, _ title: String, _ text: String, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon).font(.system(size: 15, weight: .bold)).foregroundStyle(C.brandHi)
                    .frame(width: 36, height: 36)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(C.brand.opacity(0.18)))
                Spacer()
                Text("0\(n)").font(F.round(12, .bold)).foregroundStyle(C.brand)
            }
            Text(title).font(F.round(16, .bold)).foregroundStyle(C.creme)
                .lineLimit(1).minimumScaleFactor(0.6)   // big text sizes: shrink, never split a word (2026-11-18)
            Text(text).font(F.round(12, .medium)).foregroundStyle(C.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 138, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(LinearGradient(colors: [Color(hex: 0x13161D), C.char850], startPoint: .top, endPoint: .bottom))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(C.line, lineWidth: 1)))
        .accessibilityElement(children: .combine)
    }

    private var empty: some View {
        VStack(spacing: 10) {
            Image(systemName: "film").font(.system(size: 34, weight: .bold)).foregroundStyle(C.brand)
            Text("No reviews yet.").font(F.round(17, .bold)).foregroundStyle(C.creme)
            Text("Your reviews and the drills they added show up here.")
                .font(F.round(14, .semibold)).foregroundStyle(C.muted).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: 12) {
            LabKicker("YOUR REVIEWS")
            ForEach(lab.reviews) { r in
                NavigationLink(value: r) {
                    HStack(spacing: 12) {
                        if let ai = r.ai {
                            Text("\(ai.score)").font(F.round(16, .heavy)).foregroundStyle(.white).monospacedDigit()
                                .frame(width: 42, height: 42).background(Circle().fill(FilmScore.color(ai.score)))
                        } else {
                            Image(systemName: r.clip == nil ? "note.text" : "play.rectangle.fill")
                                .font(.system(size: 18, weight: .bold)).foregroundStyle(C.brandInk)
                                .frame(width: 42, height: 42).background(Circle().fill(C.brand))
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.title).font(F.round(16, .bold)).foregroundStyle(C.creme).lineLimit(1)
                            Text(r.ai.map { "\(r.date.formatted(.dateTime.day().month(.abbreviated))) · AI review · \($0.fixes.count) to fix" }
                                 ?? "\(r.date.formatted(.dateTime.day().month(.abbreviated))) · \(r.mistakes.isEmpty ? "nothing to fix" : "\(r.mistakes.count) to fix") · \(r.drills.count) drills")
                                .font(F.round(13, .semibold)).foregroundStyle(C.muted).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.system(size: 13, weight: .heavy)).foregroundStyle(C.muted)
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(C.char800)
                        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(C.line, lineWidth: 1)))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - new review (guided: the app asks, the player answers, the app says what to work on)

struct FilmReviewSheet: View {
    let position: String
    @Environment(\.dismiss) private var dismiss
    @Environment(AppStore.self) private var store
    @State private var lab = Lab.shared

    private enum Stage { case setup, questions, result, analysing, aiResult }
    @State private var stage: Stage = .setup
    // AI review
    @State private var clipKind = "game"
    @State private var whoAmI = ""
    @State private var aiError: String?
    @State private var progress = ""
    @State private var title = ""
    @State private var note = ""
    @State private var moments: Set<String> = []
    @State private var answers: [String: Bool] = [:]
    @State private var item: PhotosPickerItem?
    @State private var clip: String?
    @State private var loading = false
    @State private var clipError = false
    /// The saved review, once the questions are done.
    @State private var saved: FilmReview?

    /// The questions picked for this review, by part of the game. Picked once, so going Back doesn't reshuffle.
    @State private var asked: [String: [FilmQuestion]] = [:]

    private var chosen: [FilmMoment] { FilmGuide.list(position: position).filter { moments.contains($0.id) } }
    private var askedNow: [FilmQuestion] { chosen.flatMap { asked[$0.id] ?? [] } }
    private var questionCount: Int { askedNow.count }
    private var answered: Int { askedNow.filter { answers[$0.id] != nil }.count }

    var body: some View {
        ScrollView {
            switch stage {
            case .setup: setup
            case .questions: questions
            case .result: result
            case .analysing: analysing
            case .aiResult: aiResult
            }
        }
        .scrollIndicators(.hidden)
        .presentationDetents([.large])
        .presentationBackground(C.char900)
        .interactiveDismissDisabled(stage == .questions || stage == .analysing)
        .onAppear { debugSeed() }
        .onChange(of: item) { _, new in
            guard let new else { return }
            loading = true
            clipError = false
            Task {
                let file = try? await new.loadTransferable(type: ClipFile.self)
                // a second pick replaces the first copy
                if let old = clip, old != file?.name { try? FileManager.default.removeItem(at: FilmFiles.url(old)) }
                clip = file?.name
                clipError = file == nil
                loading = false
            }
        }
    }

    // step 1: the clip and what is in it

    private var setup: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Disp("NEW REVIEW", size: 30)
                Spacer()
                Button("Cancel") { cancel() }.font(F.round(15, .bold)).foregroundStyle(C.muted)
            }
            .padding(.top, 24)

            VStack(alignment: .leading, spacing: 8) {
                LabKicker("WHAT IS IT?")
                TextField("Saturday game, second half", text: $title)
                    .font(F.round(16, .semibold)).foregroundStyle(C.creme)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(C.char950))
            }

            VStack(alignment: .leading, spacing: 8) {
                LabKicker("THE CLIP")
                PhotosPicker(selection: $item, matching: .videos) {
                    HStack(spacing: 10) {
                        Image(systemName: clip == nil ? "video.badge.plus" : "checkmark.circle.fill")
                            .font(.system(size: 18, weight: .bold)).foregroundStyle(clip == nil ? C.creme2 : C.brand)
                        Text(loading ? "Adding your clip…" : clip == nil ? "Choose a video from Photos" : "Clip added. Tap to change it.")
                            .font(F.round(15, .bold)).foregroundStyle(C.creme)
                        Spacer(minLength: 0)
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(C.char800))
                }
                if clipError {
                    Text("That video couldn't be added. Try another one.").font(F.round(13, .semibold)).foregroundStyle(C.gold)
                }
                Text("Your video stays on this phone. For an AI review, a few still frames from it are sent.")
                    .font(F.round(13, .semibold)).foregroundStyle(C.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 10) {
                LabKicker("WHAT TYPE OF CLIP?")
                HStack(spacing: 8) {
                    kindChip("game", "In a game", "sportscourt.fill")
                    kindChip("training", "Training", "person.3.fill")
                    kindChip("solo", "On my own", "figure.soccer")
                }
            }

            if clipKind != "solo" {
                VStack(alignment: .leading, spacing: 8) {
                    LabKicker("WHICH PLAYER ARE YOU?")
                    TextField("Red shirt, number 8, left side", text: $whoAmI)
                        .font(F.round(16, .semibold)).foregroundStyle(C.creme)
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(C.char950))
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                LabKicker("WHAT HAPPENS IN THE CLIP?")
                Text("Pick what you did in it, so the review looks at the right things.")
                    .font(F.round(14, .semibold)).foregroundStyle(C.muted)
                ForEach(FilmGuide.list(position: position)) { m in momentRow(m) }
            }

            VStack(alignment: .leading, spacing: 8) {
                LabKicker("ANYTHING ELSE? (OPTIONAL)")
                TextField("A shot from outside the box, it went wide", text: $note, axis: .vertical)
                    .lineLimit(1...3)
                    .font(F.round(16, .semibold)).foregroundStyle(C.creme)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(C.char950))
            }

            if let aiError {
                Label(aiError, systemImage: "exclamationmark.triangle.fill")
                    .font(F.round(14, .semibold)).foregroundStyle(C.gold)
                    .fixedSize(horizontal: false, vertical: true)
            }

            AIGate(what: "AI film reviews", onNo: {}) {
                VStack(spacing: 8) {
                    Button(clip == nil ? "ADD A CLIP FIRST" : "GET MY AI REVIEW") { runAI() }
                        .buttonStyle(.gameLarge(.brand, feel: .goal))
                        .disabled(clip == nil || loading)
                    Text(AIUsage.shared.line("film")).font(F.round(13, .semibold)).foregroundStyle(C.muted)
                }
            }

            Button(moments.isEmpty ? "No clip? Pick what happened, then answer questions" : "No clip? Answer questions instead") {
                Haptics.play(.kick)
                for m in chosen where asked[m.id] == nil { asked[m.id] = FilmGuide.ask(m) }
                withAnimation(.snappy) { stage = .questions }
            }
            .font(F.round(15, .bold)).foregroundStyle(moments.isEmpty ? C.muted : C.brandHi)
            .frame(maxWidth: .infinity)
            .disabled(moments.isEmpty || loading)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 24)
    }

    private func kindChip(_ id: String, _ label: String, _ icon: String) -> some View {
        let on = clipKind == id
        return Button {
            clipKind = id
            Haptics.play(.stud)
        } label: {
            VStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 17, weight: .bold))
                Text(label).font(F.round(13, .bold)).lineLimit(1).minimumScaleFactor(0.8)
            }
            .foregroundStyle(on ? Color.white : C.creme2)
            .frame(maxWidth: .infinity).frame(height: 64)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(on ? C.brand : C.char800))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    // AI: working…

    private var analysing: some View {
        VStack(spacing: 18) {
            ProgressView().controlSize(.large).tint(C.brandHi).padding(.top, 80)
            Disp("REVIEWING YOUR CLIP", size: 26).multilineTextAlignment(.center)
            Text(progress).font(F.round(15, .semibold)).foregroundStyle(C.creme2).multilineTextAlignment(.center)
            Text("This takes about 20 seconds.").font(F.round(13, .semibold)).foregroundStyle(C.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
    }

    // AI: the report

    private var aiResult: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let r = saved?.ai {
                FilmAIReportView(report: r).padding(.top, 28)
                Text("The drills are on your Fix List in Training now. Do each one \(Lab.fixGoal) times and it clears.")
                    .font(F.round(14, .semibold)).foregroundStyle(C.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button("DONE") { dismiss() }.buttonStyle(.gameLarge(.brand, feel: .kick))
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 24)
    }

    private func runAI() {
        guard let clip else { return }
        aiError = nil
        progress = "Picking frames and reading your body position…"
        Haptics.play(.kick)
        withAnimation(.snappy) { stage = .analysing }
        Task {
            do {
                let frames = try await ClipFrames.make(FilmFiles.url(clip))
                guard frames.withPerson > 0 else {
                    fail("We couldn't see a player in this clip. Try one where you're clearly in the picture.")
                    return
                }
                progress = "The AI is watching your clip…"
                struct Reply: Decodable { let report: FilmAIReport }
                let reply = try await AICall.post("film-review", [
                    "frames": frames.frames.map { $0.base64EncodedString() },
                    "context": aiContext(frames),
                ], kind: "film", as: Reply.self)
                let r = reply.report
                guard r.usable else {
                    fail(r.problem.isEmpty ? "The AI couldn't review this clip. Try a clearer one of you playing." : r.problem)
                    return
                }
                var drills: [String] = []
                for f in r.fixes { for d in f.drills where !drills.contains(d) { drills.append(d) } }
                let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
                let review = FilmReview(title: name.isEmpty ? (r.action.isEmpty ? "Clip review" : String(r.action.prefix(60))) : String(name.prefix(60)),
                                        mistakes: [], note: String(note.trimmingCharacters(in: .whitespacesAndNewlines).prefix(400)),
                                        clip: clip, drills: drills, ai: r)
                lab.add(review)
                saved = review
                Haptics.play(.goal)
                withAnimation(.snappy) { stage = .aiResult }
            } catch let e as ClipFrames.Failure {
                fail(e.message)
            } catch let e as AICall.Failure {
                fail(e.message)
            } catch {
                fail("Something went wrong. Try again.")
            }
        }
    }

    private func fail(_ message: String) {
        aiError = message
        Haptics.play(.post)
        withAnimation(.snappy) { stage = .setup }
    }

    /// Who the player is and what the clip is, for the AI. No name, no email.
    private func aiContext(_ f: ClipFrames.Result) -> String {
        let a = store.answers
        let lib = Library.shared
        var l: [String] = []
        l.append("Player: \(a.positionName)" + (a.foot.map { ", \($0) foot" } ?? "") + (a.age.map { ", age \($0)" } ?? "") + (a.level.map { ", level: \($0)" } ?? ""))
        l.append("Clip: " + (clipKind == "game" ? "in a game" : clipKind == "training" ? "at team training" : "practising on their own") + String(format: ", %.0f seconds long, %d frames sent.", f.seconds, f.frames.count))
        if clipKind != "solo" {
            let who = whoAmI.trimmingCharacters(in: .whitespacesAndNewlines)
            l.append("Which player they are: " + (who.isEmpty ? "not said" : String(who.prefix(120))))
        }
        if !chosen.isEmpty { l.append("What happens in the clip (their pick): " + chosen.map(\.title).joined(separator: ", ")) }
        let n = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if !n.isEmpty { l.append("Their note: " + String(n.prefix(300))) }
        l.append("Phone body reading (Apple Vision, can be wrong):")
        l += f.notes
        let groups = Dictionary(grouping: lib.drills, by: \.skill)
        l.append("App drills, by skill (id = name):")
        for s in lib.categories where groups[s] != nil {
            l.append("\(s): " + (groups[s] ?? []).map { "\($0.id) = \($0.name)" }.joined(separator: "; "))
        }
        return l.joined(separator: "\n")
    }

    private func momentRow(_ m: FilmMoment) -> some View {
        let on = moments.contains(m.id)
        return Button {
            if on { moments.remove(m.id) } else { moments.insert(m.id) }
            Haptics.play(.stud)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: m.icon).font(.system(size: 17, weight: .bold))
                    .foregroundStyle(on ? Color.white : C.creme2)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(on ? C.brand : C.char700))
                Text(m.title).font(F.round(16, .bold)).foregroundStyle(C.creme)
                Spacer(minLength: 0)
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22, weight: .bold)).foregroundStyle(on ? C.brand : C.char600)
            }
            .padding(.vertical, 8).padding(.horizontal, 12)
            .frame(minHeight: 54)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(on ? C.brand.opacity(0.16) : C.char800))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    // step 2: the questions

    private var questions: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Button { withAnimation(.snappy) { stage = .setup } } label: {
                    Label("Back", systemImage: "chevron.left").font(F.round(15, .bold)).foregroundStyle(C.muted)
                }
                Spacer()
                Text("\(answered) of \(questionCount) answered").font(F.round(14, .bold)).foregroundStyle(C.muted)
            }
            .padding(.top, 24)
            Disp("WATCH, THEN ANSWER", size: 26)
            Text("Be honest. Nobody else sees this, and it's how your coach picks the right drills.")
                .font(F.round(14, .semibold)).foregroundStyle(C.muted)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(chosen) { m in
                VStack(alignment: .leading, spacing: 10) {
                    LabKicker(m.title.uppercased())
                    ForEach(asked[m.id] ?? []) { q in questionRow(q) }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                LabKicker("NOTE TO SELF (OPTIONAL)")
                TextField("What will you do differently next time?", text: $note, axis: .vertical)
                    .lineLimit(2...5)
                    .font(F.round(16, .semibold)).foregroundStyle(C.creme)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(C.char950))
            }

            Button(answered < questionCount ? "ANSWER THEM ALL" : "SEE WHAT TO WORK ON") { finish() }
                .buttonStyle(.gameLarge(.brand, feel: .goal))
                .disabled(answered < questionCount)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 24)
    }

    private func questionRow(_ q: FilmQuestion) -> some View {
        let a = answers[q.id]
        return VStack(alignment: .leading, spacing: 10) {
            Text(q.text).font(F.round(16, .bold)).foregroundStyle(C.creme)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                answerButton("Yes", on: a == true) { answers[q.id] = true }
                answerButton("No", on: a == false) { answers[q.id] = false }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(C.char800))
    }

    private func answerButton(_ label: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button {
            action()
            Haptics.play(.stud)
        } label: {
            Text(label).font(F.round(16, .bold))
                .foregroundStyle(on ? Color.white : C.creme2)
                .frame(maxWidth: .infinity).frame(height: 46)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(on ? C.brand : C.char700))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    // step 3: what the coach says

    private var result: some View {
        let r = saved
        let found = r?.mistakes ?? []
        return VStack(alignment: .leading, spacing: 18) {
            VStack(spacing: 10) {
                Image(systemName: found.isEmpty ? "hand.thumbsup.fill" : "checkmark.seal.fill")
                    .font(.system(size: 50, weight: .bold)).foregroundStyle(C.brand)
                Disp(found.isEmpty ? "CLEAN CLIP" : found.count == 1 ? "1 THING TO WORK ON" : "\(found.count) THINGS TO WORK ON", size: 28)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 36)

            if found.isEmpty {
                Text("Nothing to fix from your answers. Keep doing what you did here, and review another clip after your next game.")
                    .font(F.round(15, .semibold)).foregroundStyle(C.creme2).multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            } else {
                ForEach(found, id: \.self) { id in
                    if let m = FilmRules.find(id) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(m.label).font(F.round(16, .bold)).foregroundStyle(C.gold)
                            Text(FilmGuide.feedback[id] ?? "").font(F.round(15, .semibold)).foregroundStyle(C.creme)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("Drills: " + m.drills.filter { Library.shared.has($0) }.map { Library.shared.drill($0).name }.joined(separator: ", "))
                                .font(F.round(13, .semibold)).foregroundStyle(C.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(C.char800))
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    LabKicker("YOUR DRILLS")
                    ForEach((r?.drills ?? []).filter { Library.shared.has($0) }, id: \.self) { id in
                        let d = Library.shared.drill(id)
                        HStack(spacing: 12) {
                            Image(systemName: skillIcon(d.skill)).font(.system(size: 16, weight: .bold))
                                .foregroundStyle(labSkillColor(d.skill))
                                .frame(width: 38, height: 38)
                                .background(Circle().fill(labSkillColor(d.skill).opacity(0.18)))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(d.name).font(F.round(16, .bold)).foregroundStyle(C.creme)
                                Text("\(d.reps) \u{00B7} \(d.min) min").font(F.round(13, .semibold)).foregroundStyle(C.muted)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(C.char850))
                    }
                }
                Text("They're on your Fix List in Training now. Do each one \(Lab.fixGoal) times and it clears.")
                    .font(F.round(14, .semibold)).foregroundStyle(C.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button("DONE") { dismiss() }.buttonStyle(.gameLarge(.brand, feel: .kick))
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 24)
    }

    private func finish() {
        let found = FilmGuide.mistakes(asked: askedNow, answers: answers)
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let review = FilmReview(title: name.isEmpty ? "Clip review" : String(name.prefix(60)), mistakes: found,
                                note: String(note.trimmingCharacters(in: .whitespacesAndNewlines).prefix(400)),
                                clip: clip, drills: FilmRules.drills(for: found))
        lab.add(review)
        saved = review
        Haptics.play(.goal)
        withAnimation(.snappy) { stage = .result }
    }

    private func cancel() {
        if let c = clip { try? FileManager.default.removeItem(at: FilmFiles.url(c)) }
        dismiss()
    }

    /// Test builds only (`-route tab:film:questions` / `:result`): jump to a later step with made-up answers, for
    /// screenshots. Nothing is saved.
    private func debugSeed() {
        #if DEBUG
        let r = DebugRoute.parts
        if r.contains("airesult"), saved == nil {
            saved = FilmReview(title: "Saturday game, second half", mistakes: [], note: "", clip: nil,
                               drills: ["wall-first-touch", "scan-and-turn"], ai: FilmAIReport.demo)
            stage = .aiResult
            return
        }
        guard stage == .setup, moments.isEmpty, r.contains("questions") || r.contains("result") else { return }
        let list = Array(FilmGuide.list(position: position).prefix(2))
        moments = Set(list.map(\.id))
        for m in list { asked[m.id] = FilmGuide.ask(m) }
        title = "Saturday game, second half"
        let qs = list.flatMap { asked[$0.id] ?? [] }
        if r.contains("questions") {
            for (i, q) in qs.prefix(3).enumerated() { answers[q.id] = i != 1 }
            stage = .questions
        } else {
            for (i, q) in qs.enumerated() { answers[q.id] = i < 2 ? q.problemIs : !q.problemIs }
            let found = FilmGuide.mistakes(asked: qs, answers: answers)
            saved = FilmReview(title: title, mistakes: found, note: "", clip: nil, drills: FilmRules.drills(for: found))
            stage = .result
        }
        #endif
    }
}

// MARK: - one saved review

struct FilmReviewPage: View {
    let review: FilmReview
    @Environment(\.dismiss) private var dismiss
    @State private var lab = Lab.shared
    @State private var player: AVPlayer?
    @State private var confirmDelete = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Disp(review.title.uppercased(), size: 28)
                Text(review.date.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    .font(F.round(14, .semibold)).foregroundStyle(C.muted)

                if let player {
                    VideoPlayer(player: player)
                        .frame(height: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }

                if let ai = review.ai {
                    FilmAIReportView(report: ai)
                } else { VStack(alignment: .leading, spacing: 8) {
                    LabKicker(review.mistakes.isEmpty ? "NOTHING TO FIX" : "WHAT TO WORK ON")
                    ForEach(review.mistakes, id: \.self) { id in
                        if let m = FilmRules.find(id) {
                            VStack(alignment: .leading, spacing: 3) {
                                Label(m.label, systemImage: "exclamationmark.circle.fill")
                                    .font(F.round(16, .bold)).foregroundStyle(C.creme)
                                if let tip = FilmGuide.feedback[id] {
                                    Text(tip).font(F.round(14, .semibold)).foregroundStyle(C.creme2)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                } }

                if !review.note.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        LabKicker("NOTE TO SELF")
                        Text(review.note).font(F.round(16, .semibold)).foregroundStyle(C.creme2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if !review.drills.isEmpty { VStack(alignment: .leading, spacing: 10) {
                    LabKicker("DRILLS THIS ADDED")
                    ForEach(review.drills.filter { Library.shared.has($0) }, id: \.self) { id in
                        LabDrillRow(drill: Library.shared.drill(id))
                    }
                } }

                Button("Delete this review", role: .destructive) { confirmDelete = true }
                    .font(F.round(15, .bold))
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .navigationTitle("Review")
        .navigationBarTitleDisplayMode(.inline)
        .page()
        .onAppear {
            if player == nil, let c = review.clip, FileManager.default.fileExists(atPath: FilmFiles.url(c).path) {
                player = AVPlayer(url: FilmFiles.url(c))
            }
        }
        .onDisappear { player?.pause() }
        .confirmationDialog("Delete this review?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                lab.delete(review)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The clip and notes are removed. Drills already on your Fix List stay.")
        }
    }
}

// MARK: - the AI report (the result screen and a saved review)

enum FilmScore {
    static func color(_ s: Int) -> Color { s >= 80 ? C.brand : s >= 60 ? Color(hex: 0x2BB673) : s >= 40 ? C.gold : Color(hex: 0xE5484D) }
    static func word(_ s: Int) -> String { s >= 85 ? "Excellent" : s >= 70 ? "Good" : s >= 50 ? "Getting there" : "Lots to work on" }
}

struct FilmAIReportView: View {
    let report: FilmAIReport

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 16) {
                LabRing(value: Double(report.score), goal: 100) {
                    VStack(spacing: 0) {
                        Text("\(report.score)").font(F.round(26, .heavy)).foregroundStyle(C.creme).monospacedDigit()
                        Text("/ 100").font(F.round(11, .bold)).foregroundStyle(C.muted)
                    }
                }
                .frame(width: 92, height: 92)
                VStack(alignment: .leading, spacing: 4) {
                    Text(FilmScore.word(report.score).uppercased()).font(F.round(13, .heavy)).foregroundStyle(FilmScore.color(report.score))
                    Text(report.action.isEmpty ? "Your clip" : report.action)
                        .font(F.round(18, .bold)).foregroundStyle(C.creme)
                        .fixedSize(horizontal: false, vertical: true)
                    Label("AI review", systemImage: "sparkles").font(F.round(12, .bold)).foregroundStyle(C.brandHi)
                }
                Spacer(minLength: 0)
            }

            Text(report.verdict).font(F.round(16, .semibold)).foregroundStyle(C.creme2)
                .fixedSize(horizontal: false, vertical: true)

            if !report.strengths.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    LabKicker("WHAT WENT WELL")
                    ForEach(report.strengths, id: \.self) { s in
                        Label { Text(s).fixedSize(horizontal: false, vertical: true) } icon: {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(C.brand)
                        }
                        .font(F.round(15, .semibold)).foregroundStyle(C.creme)
                    }
                }
            }

            if !report.fixes.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    LabKicker("WHAT TO FIX")
                    ForEach(Array(report.fixes.enumerated()), id: \.offset) { i, f in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text("\(i + 1)").font(F.round(13, .heavy)).foregroundStyle(C.char900)
                                    .frame(width: 22, height: 22).background(Circle().fill(C.gold))
                                Text(f.title).font(F.round(16, .bold)).foregroundStyle(C.gold)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Text(f.detail).font(F.round(15, .semibold)).foregroundStyle(C.creme)
                                .fixedSize(horizontal: false, vertical: true)
                            ForEach(f.drills, id: \.self) { id in
                                LabDrillRow(drill: Library.shared.drill(id), canTick: false)
                            }
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(C.char800))
                    }
                }
            }

            if !report.cues.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    LabKicker("NEXT TIME, THINK")
                    ForEach(report.cues, id: \.self) { c in
                        Text("“\(c)”").font(F.round(15, .bold)).foregroundStyle(C.brandHi)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            Text("AI reviews can get things wrong. They look at still frames, not the whole video.")
                .font(F.round(12, .medium)).foregroundStyle(C.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
