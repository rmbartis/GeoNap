// ContactPickerView.swift
// UIViewControllerRepresentable wrapper around CNContactPickerViewController.
//
// Presented via .background() rather than .sheet() so that when the system
// contact picker auto-dismisses after a selection it does NOT cause SwiftUI
// to also dismiss the parent sheet (the bug that returned users to the Home screen).

import SwiftUI
import Contacts
import ContactsUI

struct ContactPickerView: UIViewControllerRepresentable {

    @Binding var isPresented: Bool
    var onSelect: (NotifyContact) -> Void

    func makeUIViewController(context: Context) -> UIViewController {
        // Transparent host controller; the picker is presented from here,
        // keeping it outside SwiftUI's sheet hierarchy.
        UIViewController()
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        if isPresented && uiViewController.presentedViewController == nil {
            let picker = CNContactPickerViewController()
            picker.delegate = context.coordinator
            uiViewController.present(picker, animated: true)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(isPresented: $isPresented, onSelect: onSelect)
    }

    final class Coordinator: NSObject, CNContactPickerDelegate {

        @Binding var isPresented: Bool
        let onSelect: (NotifyContact) -> Void

        init(isPresented: Binding<Bool>, onSelect: @escaping (NotifyContact) -> Void) {
            self._isPresented = isPresented
            self.onSelect     = onSelect
        }

        /// Called when the user taps a contact — picker dismisses itself automatically.
        func contactPicker(_ picker: CNContactPickerViewController,
                           didSelect contact: CNContact) {
            isPresented = false
            let name = CNContactFormatter.string(from: contact, style: .fullName)
                       ?? contact.givenName

            // Prefer primary phone; fall back to first email address.
            if let phone = contact.phoneNumbers.first?.value.stringValue {
                onSelect(NotifyContact(name: name, value: phone))
            } else if let email = contact.emailAddresses.first?.value as String? {
                onSelect(NotifyContact(name: name, value: email))
            }
        }

        func contactPickerDidCancel(_ picker: CNContactPickerViewController) {
            isPresented = false
        }
    }
}
