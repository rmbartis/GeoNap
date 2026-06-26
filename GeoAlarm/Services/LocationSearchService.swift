// LocationSearchService.swift
// Wraps MKLocalSearchCompleter to provide address autocomplete suggestions,
// then resolves a selected suggestion to a coordinate via MKLocalSearch.

import Foundation
import MapKit
import Combine

@MainActor
final class LocationSearchService: NSObject, ObservableObject {

    // MARK: - Published state
    @Published var query: String = ""
    @Published var completions: [MKLocalSearchCompletion] = []
    @Published var isSearching: Bool = false

    // MARK: - Private
    private let completer = MKLocalSearchCompleter()
    private var cancellables = Set<AnyCancellable>()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]

        // Debounce: wait 300 ms after the user stops typing before forwarding
        // the query to the completer, so we don't spam the API on every keystroke.
        $query
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .removeDuplicates()
            .sink { [weak self] text in
                guard let self else { return }
                if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    self.completer.cancel()
                    self.completions = []
                    self.isSearching = false
                } else {
                    self.isSearching = true
                    self.completer.queryFragment = text
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Resolve a completion to a coordinate

    /// Performs a full MKLocalSearch for the selected completion and returns the
    /// first map item's coordinate, or nil if the search fails.
    func resolve(_ completion: MKLocalSearchCompletion) async -> CLLocationCoordinate2D? {
        let request = MKLocalSearch.Request(completion: completion)
        let search  = MKLocalSearch(request: request)
        do {
            let response = try await search.start()
            // iOS 26: MKMapItem.placemark is deprecated — use .location.
            return response.mapItems.first?.location.coordinate
        } catch {
            print("📍 LocationSearchService resolve error: \(error.localizedDescription)")
            return nil
        }
    }

    /// Searches directly for a free-form address or place name without requiring
    /// the user to select from the autocomplete list first.
    /// Called when the user presses Return or taps the search button.
    func searchByText(_ text: String) async -> CLLocationCoordinate2D? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        isSearching = true
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = trimmed
        let search = MKLocalSearch(request: request)
        do {
            let response = try await search.start()
            isSearching = false
            // iOS 26: MKMapItem.placemark is deprecated — use .location.
            return response.mapItems.first?.location.coordinate
        } catch {
            print("📍 LocationSearchService searchByText error: \(error.localizedDescription)")
            isSearching = false
            return nil
        }
    }

    /// Clears the query and results (e.g. after a result is selected).
    func clear() {
        query = ""
        completions = []
        isSearching = false
        completer.cancel()
    }
}

// MARK: - MKLocalSearchCompleterDelegate

extension LocationSearchService: MKLocalSearchCompleterDelegate {

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        Task { @MainActor in
            self.completions = Array(completer.results.prefix(5))
            self.isSearching = false
        }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Task { @MainActor in
            self.completions = []
            self.isSearching = false
        }
    }
}
