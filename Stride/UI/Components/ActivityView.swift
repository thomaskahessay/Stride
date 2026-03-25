import SwiftUI
import UniformTypeIdentifiers

struct ActivityView: UIViewControllerRepresentable {
    let url: URL
    var onComplete: (() -> Void)? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        // Create an NSItemProvider with the explicit UTType so the receiving
        // device knows the file type (critical for iMessage / AirDrop).
        let provider = NSItemProvider()
        let uti = url.pathExtension.lowercased() == "stride"
            ? UTType.strideRoute
            : UTType(filenameExtension: url.pathExtension) ?? .data

        provider.registerFileRepresentation(
            forTypeIdentifier: uti.identifier,
            visibility: .all
        ) { completion in
            completion(self.url, true, nil)
            return nil
        }

        // Also pass the raw URL so share sheet shows a file name
        let controller = UIActivityViewController(
            activityItems: [url],
            applicationActivities: nil
        )
        controller.completionWithItemsHandler = { _, _, _, _ in
            onComplete?()
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
