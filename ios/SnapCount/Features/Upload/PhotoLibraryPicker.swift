import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct PhotoLibraryPicker: UIViewControllerRepresentable {
    let onImageData: (Data) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .images
        configuration.selectionLimit = 1
        configuration.preferredAssetRepresentationMode = .current

        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onImageData: onImageData, onCancel: onCancel)
    }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        private let onImageData: (Data) -> Void
        private let onCancel: () -> Void

        init(onImageData: @escaping (Data) -> Void, onCancel: @escaping () -> Void) {
            self.onImageData = onImageData
            self.onCancel = onCancel
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard let provider = results.first?.itemProvider else {
                DispatchQueue.main.async { self.onCancel() }
                return
            }

            guard provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) else {
                DispatchQueue.main.async { self.onCancel() }
                return
            }

            provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                DispatchQueue.main.async {
                    guard let data,
                          let image = UIImage(data: data),
                          let uploadData = image.normalizedForLibraryUpload().jpegData(compressionQuality: 0.84) else {
                        self.onCancel()
                        return
                    }
                    self.onImageData(uploadData)
                }
            }
        }
    }
}

private extension UIImage {
    func normalizedForLibraryUpload(maxDimension: CGFloat = 1800) -> UIImage {
        let oriented = fixedOrientation()
        let longest = max(oriented.size.width, oriented.size.height)
        guard longest > maxDimension else { return oriented }

        let scale = maxDimension / longest
        let targetSize = CGSize(width: oriented.size.width * scale, height: oriented.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { _ in
            oriented.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }

    func fixedOrientation() -> UIImage {
        guard imageOrientation != .up else { return self }
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
