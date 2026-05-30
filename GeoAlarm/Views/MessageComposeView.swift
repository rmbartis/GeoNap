// MessageComposeView.swift
// UIViewControllerRepresentable wrapper for MFMessageComposeViewController.
// Presents a pre-composed iMessage/SMS sheet that the user reviews and sends.

import SwiftUI
import MessageUI

/// The data needed to open the SMS compose sheet.
/// `phones` may contain multiple recipients — MFMessageComposeViewController
/// supports a pre-filled "To:" line with multiple numbers.
struct ContactMessage: Equatable {
    let phones: [String]
    let body:   String
}

struct MessageComposeView: UIViewControllerRepresentable {

    let message: ContactMessage
    var onFinish: () -> Void

    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let vc = MFMessageComposeViewController()
        vc.recipients    = message.phones
        vc.body          = message.body
        vc.messageComposeDelegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: MFMessageComposeViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, MFMessageComposeViewControllerDelegate {
        let onFinish: () -> Void
        init(onFinish: @escaping () -> Void) { self.onFinish = onFinish }

        func messageComposeViewController(
            _ controller: MFMessageComposeViewController,
            didFinishWith result: MessageComposeResult
        ) {
            controller.dismiss(animated: true)
            onFinish()
        }
    }
}
