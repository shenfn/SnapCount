import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct PhotoLibraryPicker: UIViewControllerRepresentable {
    let onSelection: () -> Void
    let onImageData: (Data) -> Void
    let onCancel: () -> Void

    init(
        onSelection: @escaping () -> Void,
        onImageData: @escaping (Data) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.onSelection = onSelection
        self.onImageData = onImageData
        self.onCancel = onCancel
    }

    init(onImageData: @escaping (Data) -> Void, onCancel: @escaping () -> Void) {
        self.init(onSelection: {}, onImageData: onImageData, onCancel: onCancel)
    }

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
        Coordinator(onSelection: onSelection, onImageData: onImageData, onCancel: onCancel)
    }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        private let onSelection: () -> Void
        private let onImageData: (Data) -> Void
        private let onCancel: () -> Void

        init(
            onSelection: @escaping () -> Void,
            onImageData: @escaping (Data) -> Void,
            onCancel: @escaping () -> Void
        ) {
            self.onSelection = onSelection
            self.onImageData = onImageData
            self.onCancel = onCancel
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard let provider = results.first?.itemProvider else {
                DispatchQueue.main.async { self.onCancel() }
                return
            }

            DispatchQueue.main.async { self.onSelection() }

            guard provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) else {
                DispatchQueue.main.async { self.onCancel() }
                return
            }

            provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                DispatchQueue.main.async {
                    guard let data,
                          let uploadData = try? ImageUploadPreprocessor.jpegData(from: data) else {
                        self.onCancel()
                        return
                    }
                    self.onImageData(uploadData)
                }
            }
        }
    }
}
