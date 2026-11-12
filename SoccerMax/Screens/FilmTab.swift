// FILM tab (SOCCER LAB, 2026-11-12). The player reviews their own clip: attach it (optional), tick what went wrong,
// and the app adds the matching drills to the Fix List on the Training tab. The matching is a fixed table
// (FilmRules in LabData.swift), not an AI service, and the clip never leaves the phone.
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
    @State private var adding = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    TabHeader("FILM")
                    intro
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
                Disp("REVIEW YOUR GAME", size: 24)
                Text("Watch a clip of yourself, tick what went wrong, and the right drills are added to your training.")
                    .font(F.round(15, .semibold)).foregroundStyle(C.creme2)
                    .fixedSize(horizontal: false, vertical: true)
                Button { adding = true } label: { Label("REVIEW A CLIP", systemImage: "plus") }
                    .buttonStyle(.game(.brand))
            }
        }
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
                        Image(systemName: r.clip == nil ? "note.text" : "play.rectangle.fill")
                            .font(.system(size: 18, weight: .bold)).foregroundStyle(C.brandInk)
                            .frame(width: 42, height: 42).background(Circle().fill(C.brand))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.title).font(F.round(16, .bold)).foregroundStyle(C.creme).lineLimit(1)
                            Text("\(r.date.formatted(.dateTime.day().month(.abbreviated))) · \(r.mistakes.count) to fix · \(r.drills.count) drills")
                                .font(F.round(13, .semibold)).foregroundStyle(C.muted)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.system(size: 13, weight: .heavy)).foregroundStyle(C.muted)
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(C.char800)
                        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(C.charInk, lineWidth: 2.5)))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - new review

struct FilmReviewSheet: View {
    let position: String
    @Environment(\.dismiss) private var dismiss
    @State private var lab = Lab.shared
    @State private var title = ""
    @State private var note = ""
    @State private var picked: Set<String> = []
    @State private var item: PhotosPickerItem?
    @State private var clip: String?
    @State private var loading = false
    @State private var clipError = false
    /// Set once saved: the sheet then shows what was added.
    @State private var added: [String]?

    var body: some View {
        ScrollView {
            if let added { result(added) } else { form }
        }
        .scrollIndicators(.hidden)
        .presentationDetents([.large])
        .presentationBackground(C.char900)
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

    private var form: some View {
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
                LabKicker("THE CLIP (OPTIONAL)")
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
                Text("Your clip stays on this phone.").font(F.round(13, .semibold)).foregroundStyle(C.muted)
            }

            VStack(alignment: .leading, spacing: 12) {
                LabKicker("WHAT WENT WRONG?")
                ForEach(FilmRules.areas(position: position), id: \.self) { area in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(area).font(F.round(15, .bold)).foregroundStyle(C.creme2)
                        ForEach(FilmRules.list(position: position).filter { $0.area == area }) { m in
                            mistakeRow(m)
                        }
                    }
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

            Button(picked.isEmpty ? "TICK AT LEAST ONE" : "SAVE AND ADD DRILLS") { save() }
                .buttonStyle(.gameLarge(.brand, feel: .goal))
                .disabled(picked.isEmpty || loading)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 24)
    }

    private func mistakeRow(_ m: FilmMistake) -> some View {
        let on = picked.contains(m.id)
        return Button {
            if on { picked.remove(m.id) } else { picked.insert(m.id) }
            Haptics.play(.stud)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: on ? "checkmark.square.fill" : "square")
                    .font(.system(size: 22, weight: .bold)).foregroundStyle(on ? C.brand : C.char600)
                Text(m.label).font(F.round(16, .semibold)).foregroundStyle(C.creme)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 10).padding(.horizontal, 12)
            .frame(minHeight: 44)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(on ? C.brand.opacity(0.18) : C.char800))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func result(_ ids: [String]) -> some View {
        VStack(spacing: 18) {
            Image(systemName: "checkmark.seal.fill").font(.system(size: 54, weight: .bold)).foregroundStyle(C.brand)
                .padding(.top, 40)
            Disp(ids.count == 1 ? "1 DRILL ADDED" : "\(ids.count) DRILLS ADDED", size: 30)
            Text("They're on your Fix List in Training. Do each one \(Lab.fixGoal) times and it clears.")
                .font(F.round(15, .semibold)).foregroundStyle(C.creme2).multilineTextAlignment(.center)
            VStack(spacing: 8) {
                ForEach(ids, id: \.self) { id in
                    let d = Library.shared.drill(id)
                    HStack {
                        Text(d.name).font(F.round(16, .bold)).foregroundStyle(C.creme)
                        Spacer()
                        Text(d.skill).font(F.round(13, .semibold)).foregroundStyle(C.muted)
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(C.char800))
                }
            }
            Button("DONE") { dismiss() }.buttonStyle(.gameLarge(.brand, feel: .kick))
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 24)
    }

    private func save() {
        // keep the order the list shows them in
        let order = FilmRules.list(position: position).map(\.id).filter { picked.contains($0) }
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let review = FilmReview(title: name.isEmpty ? "Clip review" : String(name.prefix(60)), mistakes: order,
                                note: String(note.trimmingCharacters(in: .whitespacesAndNewlines).prefix(400)),
                                clip: clip, drills: FilmRules.drills(for: order))
        let ids = lab.add(review)
        Haptics.play(.goal)
        withAnimation(.snappy) { added = ids }
    }

    private func cancel() {
        if let c = clip { try? FileManager.default.removeItem(at: FilmFiles.url(c)) }
        dismiss()
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

                VStack(alignment: .leading, spacing: 8) {
                    LabKicker("WHAT WENT WRONG")
                    ForEach(review.mistakes, id: \.self) { id in
                        if let m = FilmRules.find(id) {
                            Label(m.label, systemImage: "exclamationmark.circle.fill")
                                .font(F.round(16, .semibold)).foregroundStyle(C.creme)
                        }
                    }
                }

                if !review.note.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        LabKicker("NOTE TO SELF")
                        Text(review.note).font(F.round(16, .semibold)).foregroundStyle(C.creme2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    LabKicker("DRILLS THIS ADDED")
                    ForEach(review.drills.filter { Library.shared.has($0) }, id: \.self) { id in
                        LabDrillRow(drill: Library.shared.drill(id))
                    }
                }

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
