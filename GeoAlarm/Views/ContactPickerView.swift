// ContactPickerView.swift
// UIViewControllerRepresentable wrapper around CNContactPickerViewController.
// Calls onSelect with the chosen contact's display name and first phone number.
// Calls onCancel if the user dismisses without picking.

import SwiftUI
import ContactsUI

struct ContactPickerView: UIViewControllerRepresentable {

    var onSelect: (_ name: String, _ phone: String) -> Void
    var onCancel: () -> Void

    func makeUIViewController(context: Context) -> CNContactPickerViewController {
        let picker = CNContactPickerViewController()
        picker.displayedPropertyKeys = [CNContactPhoneNumbersKey]
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: CNContactPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelect: onSelect, onCancel: onCancel)
    }

    final class Coordinator: NSObject, CNContactPickerDelegate {
        let onSelect: (String, String) -> Void
        let onCancel: () -> Void

        init(onSelect: @escaping (String, String) -> Void, onCancel: @escaping () -> Void) {
            self.onSelect = onSelect
            self.onCancel = onCancel
        }

        func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
            let name  = CNContactFormatter.string(from: contact, style: .fullName) ?? contact.givenName
            let phone = contact.phoneNumbers.first?.value.stringValue ?? ""
            // Strip non-digit characters for SMS sending; keep as-is for display
            onSelect(name, phone)
        }

        func contactPickerDidCancel(_ picker: CNContactPickerViewController) {
            onCancel()
        }
    }
}
