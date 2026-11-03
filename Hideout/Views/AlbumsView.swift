import SwiftUI

struct AlbumsView: View {
    @EnvironmentObject private var vault: VaultStore
    @EnvironmentObject private var auth: AuthManager

    @State private var showingNewAlbum = false
    @State private var newAlbumName = ""
    @State private var renaming: Album?
    @State private var renameText = ""
    @State private var deleting: Album?
    @State private var showingSettings = false
    @State private var showingArrange = false

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 16)]

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Albums")
                .navigationDestination(for: UUID.self) { albumID in
                    AlbumDetailView(albumID: albumID)
                }
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            auth.lock()
                        } label: {
                            Image(systemName: "lock.fill")
                        }
                        .accessibilityLabel("Lock")
                    }
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Menu {
                            Button {
                                startNewAlbum()
                            } label: {
                                Label("New Album", systemImage: "plus.rectangle.on.rectangle")
                            }
                            Button {
                                showingArrange = true
                            } label: {
                                Label("Arrange Albums", systemImage: "arrow.up.arrow.down")
                            }
                            Divider()
                            Button {
                                showingSettings = true
                            } label: {
                                Label("Settings", systemImage: "gearshape")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        Button {
                            startNewAlbum()
                        } label: {
                            Image(systemName: "plus")
                        }
                        .accessibilityLabel("New Album")
                    }
                }
                .alert("New Album", isPresented: $showingNewAlbum) {
                    TextField("Album name", text: $newAlbumName)
                    Button("Cancel", role: .cancel) {}
                    Button("Create") { vault.createAlbum(named: newAlbumName) }
                }
                .alert("Rename Album", isPresented: Binding(
                    get: { renaming != nil },
                    set: { if !$0 { renaming = nil } }
                )) {
                    TextField("Album name", text: $renameText)
                    Button("Cancel", role: .cancel) {}
                    Button("Save") {
                        if let album = renaming { vault.renameAlbum(album.id, to: renameText) }
                    }
                }
                .confirmationDialog(
                    "Delete this album?",
                    isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                    titleVisibility: .visible,
                    presenting: deleting
                ) { album in
                    Button("Delete Album and Its Items", role: .destructive) {
                        vault.deleteAlbum(album.id)
                    }
                } message: { album in
                    let count = vault.items(in: album.id).count
                    Text("\"\(album.name)\" and its \(count) item\(count == 1 ? "" : "s") will be permanently deleted from the vault. This can't be undone.")
                }
                .sheet(isPresented: $showingSettings) {
                    SettingsView()
                        .environmentObject(auth)
                        .environmentObject(vault)
                }
                .sheet(isPresented: $showingArrange) {
                    ArrangeAlbumsView()
                        .environmentObject(vault)
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch vault.status {
        case .failed(let message):
            ContentUnavailableView {
                Label("The vault couldn't open", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            }
        case .closed:
            ProgressView()
        case .open:
            if vault.albums.isEmpty {
                ContentUnavailableView {
                    Label("No Albums", systemImage: "rectangle.stack")
                } description: {
                    Text("Create an album to start hiding photos and videos.")
                } actions: {
                    Button("New Album") { startNewAlbum() }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 20) {
                        ForEach(vault.albums) { album in
                            NavigationLink(value: album.id) {
                                AlbumCell(album: album)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button {
                                    renameText = album.name
                                    renaming = album
                                } label: {
                                    Label("Rename", systemImage: "pencil")
                                }
                                Button(role: .destructive) {
                                    deleting = album
                                } label: {
                                    Label("Delete Album", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .padding()
                }
            }
        }
    }

    private func startNewAlbum() {
        newAlbumName = ""
        showingNewAlbum = true
    }
}

struct AlbumCell: View {
    @EnvironmentObject private var vault: VaultStore
    let album: Album

    var body: some View {
        let count = vault.items(in: album.id).count
        VStack(alignment: .leading, spacing: 6) {
            Color(.secondarySystemBackground)
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    if let cover = vault.coverItem(for: album) {
                        ThumbnailView(item: cover, showsBadge: false)
                    } else {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            Text(album.name)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            Text("\(count) item\(count == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
    }
}

struct ThumbnailView: View {
    @EnvironmentObject private var vault: VaultStore
    let item: VaultItem
    var showsBadge = true
    @State private var image: UIImage?

    var body: some View {
        Color(.secondarySystemBackground)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                }
            }
            .clipped()
            .overlay(alignment: .bottomLeading) {
                if showsBadge && item.kind == .video {
                    HStack(spacing: 3) {
                        Image(systemName: "video.fill")
                        if let duration = item.duration {
                            Text(formatDuration(duration))
                        }
                    }
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.6), radius: 2)
                    .padding(5)
                }
            }
            .task(id: item.id) {
                image = await vault.thumbnail(for: item)
            }
    }
}

func formatDuration(_ seconds: Double) -> String {
    let total = Int(seconds.rounded())
    let hours = total / 3600
    let minutes = (total % 3600) / 60
    let secs = total % 60
    if hours > 0 {
        return String(format: "%d:%02d:%02d", hours, minutes, secs)
    }
    return String(format: "%d:%02d", minutes, secs)
}

struct ArrangeAlbumsView: View {
    @EnvironmentObject private var vault: VaultStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(vault.albums) { album in
                    Text(album.name)
                }
                .onMove { source, destination in
                    vault.moveAlbums(fromOffsets: source, toOffset: destination)
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Arrange Albums")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

struct MoveToAlbumView: View {
    let currentAlbumID: UUID
    let onSelect: (UUID) -> Void

    @EnvironmentObject private var vault: VaultStore
    @Environment(\.dismiss) private var dismiss
    @State private var showingNewAlbum = false
    @State private var newAlbumName = ""

    var body: some View {
        NavigationStack {
            List {
                Button {
                    newAlbumName = ""
                    showingNewAlbum = true
                } label: {
                    Label("New Album…", systemImage: "plus")
                }
                ForEach(vault.albums.filter { $0.id != currentAlbumID }) { album in
                    Button {
                        onSelect(album.id)
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            Color(.secondarySystemBackground)
                                .frame(width: 44, height: 44)
                                .overlay {
                                    if let cover = vault.coverItem(for: album) {
                                        ThumbnailView(item: cover, showsBadge: false)
                                    }
                                }
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            Text(album.name)
                                .foregroundStyle(.primary)
                        }
                    }
                }
            }
            .navigationTitle("Move to Album")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert("New Album", isPresented: $showingNewAlbum) {
                TextField("Album name", text: $newAlbumName)
                Button("Cancel", role: .cancel) {}
                Button("Create and Move") {
                    let album = vault.createAlbum(named: newAlbumName)
                    onSelect(album.id)
                    dismiss()
                }
            }
        }
    }
}
