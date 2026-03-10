import Photos
import SwiftUI
import UIKit

struct CapturePreviewSheet: View {
    let title: String
    let image: UIImage
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showActivitySheet = false
    @State private var feedbackMessage: String?
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                ScrollView([.vertical, .horizontal]) {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .padding(8)
                }
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(.secondarySystemBackground))
                )

                HStack(spacing: 12) {
                    actionButton(title: "Share", systemImage: "square.and.arrow.up") {
                        showActivitySheet = true
                    }

                    actionButton(title: "Copy", systemImage: "doc.on.doc") {
                        UIPasteboard.general.image = image
                        feedbackMessage = "Copied to clipboard."
                    }

                    actionButton(title: isSaving ? "Saving…" : "Save", systemImage: "photo.on.rectangle") {
                        saveToPhotos()
                    }
                    .disabled(isSaving)
                }

                Button(role: .destructive) {
                    onDelete()
                    dismiss()
                } label: {
                    Label("Delete Capture", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                if let feedbackMessage {
                    Text(feedbackMessage)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .sheet(isPresented: $showActivitySheet) {
            ActivityViewController(activityItems: [image])
        }
    }

    private func actionButton(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
    }

    private func saveToPhotos() {
        guard !isSaving else { return }
        isSaving = true
        feedbackMessage = nil

        Task {
            do {
                try await PhotoLibrarySaver.save(image: image)
                await MainActor.run {
                    feedbackMessage = "Saved to Photos."
                    isSaving = false
                }
            } catch {
                await MainActor.run {
                    feedbackMessage = error.localizedDescription
                    isSaving = false
                }
            }
        }
    }
}

private enum PhotoLibrarySaver {
    static func save(image: UIImage) async throws {
        let status = await requestAuthorization()
        guard status == .authorized || status == .limited else {
            throw CapturePreviewError.photoAccessDenied
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume(returning: ())
                } else {
                    continuation.resume(throwing: CapturePreviewError.saveFailed)
                }
            }
        }
    }

    private static func requestAuthorization() async -> PHAuthorizationStatus {
        await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                continuation.resume(returning: status)
            }
        }
    }
}

private enum CapturePreviewError: LocalizedError {
    case photoAccessDenied
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .photoAccessDenied:
            return "Photo Library access is required to save captures."
        case .saveFailed:
            return "The capture could not be saved."
        }
    }
}
