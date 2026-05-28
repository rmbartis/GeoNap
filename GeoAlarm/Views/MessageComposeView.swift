// MessageComposeView.swift
// UIViewControllerRepresentable wrapper for MFMessageComposeViewController.
// Presents a pre-composed iMessage/SMS sheet that the user reviews and sends.

import SwiftUI
import MessageUI

/// The data needed to open the compose sheet.
struct ContactMessage: Equatable {
    let phone: String
    let body:  String
}

struct MessageComposeView: UIViewControllerRepresentable {

    let message: ContactMessage
    var onFinish: () -> Void

    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let vc = MFMessageComposeViewController()
        vc.recipients    = [message.phone]
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
