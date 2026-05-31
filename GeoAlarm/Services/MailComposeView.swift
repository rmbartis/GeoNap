// MailComposeView.swift
// UIViewControllerRepresentable wrapper around MFMailComposeViewController.
// Presents the device's default mail app compose sheet.
//
// Usage:
//   .sheet(item: $alarmManager.pendingMailMessage) { msg in
//       MailComposeView(message: msg)
//   }
//
// Note: MFMailComposeViewController.canSendMail() must return true before
// presenting this view. If no mail account is configured on the device,
// canSendMail() returns false — the caller should gate on this.

import SwiftUI
import MessageUI

// MARK: - MailMessage

/// Data passed to MailComposeView so it survives a notification-tap app relaunch.
struct MailMessage: Identifiable, Equatable {
    let id      = UUID()
    let to      : [String]
    let subject : String
    let body    : String
}

// MARK: - MailComposeView

struct MailComposeView: UIViewControllerRepresentable {

    let message: MailMessage
    /// Called after the compose sheet is dismissed (sent, cancelled, or failed).
    var onDismiss: (() -> Void)? = nil

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let vc = MFMailComposeViewController()
        vc.mailComposeDelegate = context.coordinator
        vc.setToRecipients(message.to)
        vc.setSubject(message.subject)
        vc.setMessageBody(message.body, isHTML: false)
        return vc
    }

    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onDismiss: onDismiss) }

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        private let onDismiss: (() -> Void)?
        init(onDismiss: (() -> Void)?) { self.onDismiss = onDismiss }

        func mailComposeController(
            _ controller: MFMailComposeViewController,
            didFinishWith result: MFMailComposeResult,
            error: Error?
        ) {
            controller.dismiss(animated: true) { [weak self] in
                self?.onDismiss?()
            }
        }
    }
}
