import SwiftUI
import AVKit

/// Full-screen viewer. Swipe left and right between items, pinch or double-tap to zoom photos.
struct MediaViewer: View {
    let albumID: UUID

    @EnvironmentObject private var vault: VaultStore
    @Environment(\.dismiss) private var dismiss

    @State private var currentID: UUID
    @State private var showsControls = true
    @State private var shareItem: ShareItem?
    @State private var confirmDelete = false
    @State private var isWorking = false
    @State private var message: String?

    init(albumID: UUID, startID: UUID) {
        self.albumID = albumID
        _currentID = State(initialValue: startID)
    }

    var body: some View {
        let items = vault.items(in: albumID)
        let current = items.first { $0.id == currentID }

        ZStack {
            Color.black.ignoresSafeArea()

            TabView(selection: $currentID) {
                ForEach(items) { item in
                    MediaPage(
                        item: item,
                        isCurrent: item.id == currentID,
                        onTap: { withAnimation(.easeInOut(duration: 0.2)) { showsControls.toggle() } }
                    )
                    .tag(item.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()

            if showsControls {
                controls(items: items, current: current)
                    .transition(.opacity)
            }

            if isWorking {
                ProgressView().tint(.white).scaleEffect(1.4)
            }
        }
        .environment(\.colorScheme, .dark)
        .statusBarHidden(!showsControls)
        .onChange(of: items.map(\.id)) { _, ids in
            if ids.isEmpty { dismiss() }
        }
        .onDisappear {
            vault.clearTemporaryFiles()
        }
        .sheet(item: $shareItem) { item in
            ShareSheet(url: item.url)
        }
        .confirmationDialog("Delete this item?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete from Vault", role: .destructive) {
                if let current { delete(current, in: items) }
            }
        } message: {
            Text("It will be permanently deleted. This can't be undone.")
        }
        .alert(
            "Hideout",
            isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(message ?? "")
        }
    }

    private func controls(items: [VaultItem], current: VaultItem?) -> some View {
        VStack {
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.headline)
                        .frame(width: 40, height: 40)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .accessibilityLabel("Close")
                Spacer()
                if let index = items.firstIndex(where: { $0.id == currentID }) {
                    Text("\(index + 1) of \(items.count)")
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial, in: Capsule())
                }
                Spacer()
                Color.clear.frame(width: 40, height: 40)
            }
            .padding(.horizontal)

            Spacer()

            if let current {
                HStack {
                    barButton("square.and.arrow.up", label: "Share") { await share(current) }
                    Spacer()
                    barButton("square.and.arrow.down", label: "Save to Photos") { await saveToPhotos(current) }
                    Spacer()
                    barButton("star", label: "Use as Album Cover") {
                        vault.setCover(current)
                        message = "This is now the album cover."
                    }
                    Spacer()
                    barButton("trash", label: "Delete") { confirmDelete = true }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
        }
        .foregroundStyle(.white)
    }

    private func barButton(_ systemImage: String, label: String, action: @escaping () async -> Void) -> some View {
        Button {
            Task { await action() }
        } label: {
            Image(systemName: systemImage)
                .font(.title3)
                .frame(width: 44, height: 44)
        }
        .accessibilityLabel(label)
        .disabled(isWorking)
    }

    // MARK: Actions

    private func share(_ item: VaultItem) async {
        isWorking = true
        defer { isWorking = false }
        do {
            shareItem = ShareItem(url: try await vault.temporaryFile(for: item))
        } catch {
            message = error.localizedDescription
        }
    }

    private func saveToPhotos(_ item: VaultItem) async {
        isWorking = true
        defer { isWorking = false }
        do {
            let url = try await vault.temporaryFile(for: item)
            try await PhotoLibraryService.save(fileAt: url, kind: item.kind)
            message = "Saved to Photos. It's still in the vault too."
        } catch {
            message = error.localizedDescription
        }
    }

    private func delete(_ item: VaultItem, in items: [VaultItem]) {
        if let index = items.firstIndex(of: item) {
            let remaining = items.filter { $0.id != item.id }
            if !remaining.isEmpty {
                currentID = remaining[min(index, remaining.count - 1)].id
            }
        }
        vault.delete([item.id])
    }
}

private struct MediaPage: View {
    let item: VaultItem
    let isCurrent: Bool
    let onTap: () -> Void

    var body: some View {
        switch item.kind {
        case .photo:
            PhotoPage(item: item, onTap: onTap)
        case .video:
            VideoPage(item: item, isCurrent: isCurrent, onTap: onTap)
        }
    }
}

private struct PhotoPage: View {
    @EnvironmentObject private var vault: VaultStore
    let item: VaultItem
    let onTap: () -> Void

    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        ZStack {
            if let image {
                ZoomableImageView(image: image, onSingleTap: onTap)
            } else if failed {
                Label("This photo couldn't be opened", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.white)
            } else {
                ProgressView().tint(.white)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .task(id: item.id) {
            do {
                image = try await vault.displayImage(for: item)
            } catch {
                failed = true
            }
        }
    }
}

private struct VideoPage: View {
    @EnvironmentObject private var vault: VaultStore
    let item: VaultItem
    let isCurrent: Bool
    let onTap: () -> Void

    @State private var player: AVPlayer?
    @State private var failed = false

    var body: some View {
        ZStack {
            if let player {
                VideoPlayer(player: player)
                    // Leave room for the viewer's top and bottom bars.
                    .padding(.vertical, 64)
            } else if failed {
                Label("This video couldn't be opened", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.white)
            } else {
                VStack(spacing: 12) {
                    ProgressView().tint(.white)
                    Text("Decrypting video…").font(.footnote).foregroundStyle(.white.opacity(0.7))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: item.id) {
            guard player == nil else { return }
            do {
                let url = try await vault.temporaryFile(for: item)
                player = AVPlayer(url: url)
            } catch {
                failed = true
            }
        }
        .onChange(of: isCurrent) { _, isCurrent in
            if !isCurrent { player?.pause() }
        }
        .onDisappear {
            player?.pause()
        }
    }
}

// MARK: - Zooming

/// Wraps a UIScrollView, which gives the same smooth pinch-to-zoom as the Photos app.
private struct ZoomableImageView: UIViewRepresentable {
    let image: UIImage
    let onSingleTap: () -> Void

    func makeUIView(context: Context) -> ZoomingImageScrollView {
        let view = ZoomingImageScrollView()
        view.imageView.image = image
        view.onSingleTap = onSingleTap
        return view
    }

    func updateUIView(_ view: ZoomingImageScrollView, context: Context) {
        if view.imageView.image !== image {
            view.imageView.image = image
            view.setZoomScale(1, animated: false)
        }
        view.onSingleTap = onSingleTap
    }
}

private final class ZoomingImageScrollView: UIScrollView, UIScrollViewDelegate {
    let imageView = UIImageView()
    var onSingleTap: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        delegate = self
        minimumZoomScale = 1
        maximumZoomScale = 5
        bouncesZoom = true
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        contentInsetAdjustmentBehavior = .never
        backgroundColor = .clear
        imageView.contentMode = .scaleAspectFit
        addSubview(imageView)

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)

        let singleTap = UITapGestureRecognizer(target: self, action: #selector(handleSingleTap))
        singleTap.require(toFail: doubleTap)
        addGestureRecognizer(singleTap)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if zoomScale <= minimumZoomScale {
            imageView.frame = CGRect(origin: .zero, size: bounds.size)
            contentSize = bounds.size
        }
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        imageView
    }

    @objc private func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
        if zoomScale > minimumZoomScale {
            setZoomScale(minimumZoomScale, animated: true)
        } else {
            let point = recognizer.location(in: imageView)
            let size = CGSize(width: bounds.width / 2.5, height: bounds.height / 2.5)
            let rect = CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height)
            zoom(to: rect, animated: true)
        }
    }

    @objc private func handleSingleTap() {
        onSingleTap?()
    }
}

// MARK: - Sharing

struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

struct ShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
