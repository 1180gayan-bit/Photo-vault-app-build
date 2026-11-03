import SwiftUI
import PhotosUI
import CoreTransferable
import UniformTypeIdentifiers

struct AlbumDetailView: View {
    let albumID: UUID

    @EnvironmentObject private var vault: VaultStore

    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var importProgress: (done: Int, total: Int)?
    @State private var importedIdentifiers: [String] = []
    @State private var importFailures = 0
    @State private var askDeleteOriginals = false

    @State private var isSelecting = false
    @State private var selection: Set<UUID> = []
    @State private var showingMove = false
    @State private var confirmDelete = false
    @State private var isWorking = false

    @State private var viewerStart: ViewerStart?
    @State private var alertMessage: String?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 3)

    var body: some View {
        let items = vault.items(in: albumID)
        ScrollView {
            if items.isEmpty {
                emptyState
            } else {
                LazyVGrid(columns: columns, spacing: 2) {
                    ForEach(items) { item in
                        cell(for: item)
                    }
                }
            }
        }
        .navigationTitle(vault.album(albumID)?.name ?? "Album")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent(hasItems: !items.isEmpty) }
        .overlay {
            if let progress = importProgress {
                BusyOverlay(text: "Hiding \(min(progress.done + 1, progress.total)) of \(progress.total)…")
            } else if isWorking {
                BusyOverlay(text: "Working…")
            }
        }
        .disabled(importProgress != nil || isWorking)
        .onChange(of: pickerItems) { _, newItems in
            guard !newItems.isEmpty else { return }
            pickerItems = []
            Task { await importItems(newItems) }
        }
        .confirmationDialog(
            "Delete the originals from Photos?",
            isPresented: $askDeleteOriginals,
            titleVisibility: .visible
        ) {
            Button("Delete from Photos", role: .destructive) {
                Task { await deleteOriginals() }
            }
            Button("Keep in Photos", role: .cancel) {
                importedIdentifiers = []
            }
        } message: {
            Text(deleteOriginalsMessage)
        }
        .confirmationDialog(
            "Delete \(selection.count) item\(selection.count == 1 ? "" : "s")?",
            isPresented: $confirmDelete,
            titleVisibility: .visible
        ) {
            Button("Delete from Vault", role: .destructive) {
                vault.delete(selection)
                selection = []
                isSelecting = false
            }
        } message: {
            Text("They'll be permanently deleted. This can't be undone.")
        }
        .sheet(isPresented: $showingMove) {
            MoveToAlbumView(currentAlbumID: albumID) { destination in
                vault.move(selection, to: destination)
                selection = []
                isSelecting = false
            }
            .environmentObject(vault)
        }
        .fullScreenCover(item: $viewerStart) { start in
            MediaViewer(albumID: albumID, startID: start.itemID)
                .environmentObject(vault)
        }
        .alert(
            "Hideout",
            isPresented: Binding(get: { alertMessage != nil }, set: { if !$0 { alertMessage = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage ?? "")
        }
    }

    // MARK: Pieces

    private var importButton: some View {
        PhotosPicker(
            selection: $pickerItems,
            matching: .any(of: [.images, .videos]),
            preferredItemEncoding: .current,
            photoLibrary: .shared()
        ) {
            Label("Add Photos & Videos", systemImage: "plus")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "photo.badge.plus")
                .font(.system(size: 52))
                .foregroundStyle(.secondary)
            Text("This album is empty")
                .font(.title3.weight(.semibold))
            Text("Add photos and videos from your library. They're encrypted and kept only inside Hideout.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            importButton
                .buttonStyle(.borderedProminent)
        }
        .padding(32)
        .padding(.top, 60)
    }

    private func cell(for item: VaultItem) -> some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay { ThumbnailView(item: item) }
            .clipped()
            .overlay(alignment: .topTrailing) {
                if isSelecting {
                    Image(systemName: selection.contains(item.id) ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, selection.contains(item.id) ? Color.accentColor : Color.black.opacity(0.25))
                        .shadow(radius: 2)
                        .padding(6)
                }
            }
            .opacity(isSelecting && !selection.contains(item.id) ? 0.85 : 1)
            .contentShape(Rectangle())
            .onTapGesture {
                if isSelecting {
                    if selection.contains(item.id) {
                        selection.remove(item.id)
                    } else {
                        selection.insert(item.id)
                    }
                } else {
                    viewerStart = ViewerStart(itemID: item.id)
                }
            }
    }

    @ToolbarContentBuilder
    private func toolbarContent(hasItems: Bool) -> some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            if hasItems {
                Button(isSelecting ? "Done" : "Select") {
                    isSelecting.toggle()
                    selection = []
                }
            }
            if !isSelecting {
                importButton
            }
        }
        if isSelecting {
            ToolbarItemGroup(placement: .bottomBar) {
                Button {
                    showingMove = true
                } label: {
                    Image(systemName: "folder")
                }
                .accessibilityLabel("Move to Album")
                .disabled(selection.isEmpty)

                Spacer()
                Text(selection.isEmpty ? "Select Items" : "\(selection.count) Selected")
                    .font(.subheadline.weight(.semibold))
                Spacer()

                Button {
                    Task { await saveSelectionToPhotos() }
                } label: {
                    Image(systemName: "square.and.arrow.down")
                }
                .accessibilityLabel("Save to Photos")
                .disabled(selection.isEmpty)

                Button(role: .destructive) {
                    confirmDelete = true
                } label: {
                    Image(systemName: "trash")
                }
                .accessibilityLabel("Delete")
                .disabled(selection.isEmpty)
            }
        }
    }

    private var deleteOriginalsMessage: String {
        var text = "Your items are now hidden in Hideout. iOS will ask you to confirm. Deleted items go to \"Recently Deleted\" in the Photos app, so empty that too."
        if importFailures > 0 {
            text = "\(importFailures) item\(importFailures == 1 ? "" : "s") couldn't be imported and will stay in Photos. " + text
        }
        return text
    }

    // MARK: Actions

    private func importItems(_ picked: [PhotosPickerItem]) async {
        importProgress = (0, picked.count)
        var identifiers: [String] = []
        var failures = 0

        for item in picked {
            do {
                if item.supportedContentTypes.contains(where: { $0.conforms(to: .movie) }) {
                    guard let movie = try await item.loadTransferable(type: PickedMovie.self) else {
                        throw VaultError.importFailed
                    }
                    try await vault.importVideo(at: movie.url, into: albumID)
                } else {
                    guard let data = try await item.loadTransferable(type: Data.self) else {
                        throw VaultError.importFailed
                    }
                    let ext = item.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg"
                    try await vault.importPhoto(data: data, fileExtension: ext, into: albumID)
                }
                if let identifier = item.itemIdentifier {
                    identifiers.append(identifier)
                }
            } catch VaultError.locked {
                importProgress = nil
                return
            } catch {
                failures += 1
            }
            importProgress?.done += 1
        }

        importProgress = nil
        importFailures = failures
        if !identifiers.isEmpty {
            importedIdentifiers = identifiers
            askDeleteOriginals = true
        } else if failures > 0 {
            alertMessage = "\(failures) item\(failures == 1 ? "" : "s") couldn't be imported."
        }
    }

    private func deleteOriginals() async {
        let identifiers = importedIdentifiers
        importedIdentifiers = []
        do {
            let deleted = try await PhotoLibraryService.deleteAssets(localIdentifiers: identifiers)
            if deleted < identifiers.count {
                alertMessage = "Some originals couldn't be found, so they're still in Photos. To let Hideout delete them, open the Settings app, tap Hideout > Photos and choose Full Access. Or delete them in the Photos app."
            }
        } catch let error as PhotoLibraryError {
            alertMessage = error.localizedDescription
        } catch {
            alertMessage = "The originals were kept in Photos."
        }
    }

    private func saveSelectionToPhotos() async {
        let chosen = vault.items(in: albumID).filter { selection.contains($0.id) }
        isWorking = true
        defer {
            isWorking = false
            vault.clearTemporaryFiles()
        }
        do {
            for item in chosen {
                let url = try await vault.temporaryFile(for: item)
                try await PhotoLibraryService.save(fileAt: url, kind: item.kind)
            }
            alertMessage = "Saved \(chosen.count) item\(chosen.count == 1 ? "" : "s") to Photos. They're still in the vault too."
            selection = []
            isSelecting = false
        } catch {
            alertMessage = error.localizedDescription
        }
    }
}

struct ViewerStart: Identifiable {
    let itemID: UUID
    var id: UUID { itemID }
}

struct BusyOverlay: View {
    let text: String

    var body: some View {
        ZStack {
            Color.black.opacity(0.25).ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView()
                Text(text).font(.subheadline)
            }
            .padding(24)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }
}

/// Receives a video from the photo picker as a file (videos are too big to load into memory).
struct PickedMovie: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let destination = VaultFiles().newTemporaryURL(
                fileExtension: received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension
            )
            try FileManager.default.copyItem(at: received.file, to: destination)
            return PickedMovie(url: destination)
        }
    }
}
