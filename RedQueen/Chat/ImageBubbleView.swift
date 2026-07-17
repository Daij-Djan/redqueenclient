import SwiftUI

/// Inline image rendering with async thumbnail loading, optional caption,
/// and a tap-to-expand fullscreen viewer.
struct ImageBubbleView: View {
    let message: ChatMessage
    let attachment: ImageAttachment

    @Environment(ImageLoaderService.self) private var imageLoader
    @State private var isShowingViewer = false

    private var aspectRatio: CGFloat {
        guard let width = attachment.width, let height = attachment.height,
              width > 0, height > 0 else { return 4 / 3 }
        return CGFloat(width) / CGFloat(height)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Group {
                if let image = imageLoader.thumbnails[message.id] {
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    ZStack {
                        Color.reSurface
                        ProgressView()
                    }
                }
            }
            .aspectRatio(aspectRatio, contentMode: .fit)
            .frame(maxWidth: 280, maxHeight: 340)
            .clipShape(.rect(cornerRadius: 14))
            .contentShape(.rect(cornerRadius: 14))
            .onTapGesture { isShowingViewer = true }

            if let caption = attachment.caption, !caption.isEmpty {
                Text(MessageBubble.markdown(caption))
                    .textSelection(.enabled)
            }
        }
        .onAppear { imageLoader.loadThumbnail(messageID: message.id, attachment: attachment) }
        #if os(iOS)
        .fullScreenCover(isPresented: $isShowingViewer) {
            ImageViewer(attachment: attachment, fallback: imageLoader.thumbnails[message.id])
        }
        #else
        .sheet(isPresented: $isShowingViewer) {
            ImageViewer(attachment: attachment, fallback: imageLoader.thumbnails[message.id])
        }
        #endif
    }
}

/// Fullscreen dark viewer; loads the original, falls back to the thumbnail.
struct ImageViewer: View {
    let attachment: ImageAttachment
    let fallback: Image?

    @Environment(ImageLoaderService.self) private var imageLoader
    @Environment(\.dismiss) private var dismiss
    @State private var fullImage: Image?

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()

            Group {
                if let image = fullImage ?? fallback {
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    ProgressView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onTapGesture { dismiss() }

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(10)
                    .background(.black.opacity(0.55), in: .circle)
            }
            .padding(.top, 8)
            .padding(.leading, 12)
            .accessibilityLabel("Close")
        }
        .task { fullImage = await imageLoader.loadFull(attachment: attachment) }
    }
}
