// CuratedFeeds.swift
// Built-in list of popular transit agencies with confirmed-public GTFS feed URLs.
// All feeds are freely accessible without API keys or registration.
// URLs are correct as of mid-2025 but may change — use "Enter custom GTFS URL"
// if a feed stops working.

import Foundation

struct CuratedFeed: Identifiable {
    let id = UUID()
    let name: String
    let region: String
    let feedURL: String
    let routeTypes: String  // short description e.g. "Rail · Bus"
}

enum CuratedFeeds {

    static let all: [CuratedFeed] = [

        // MARK: USA

        CuratedFeed(
            name: "Amtrak",
            region: "USA · National",
            feedURL: "https://content.amtrak.com/content/gtfs/GTFS.zip",
            routeTypes: "Rail"
        ),
        CuratedFeed(
            name: "BART",
            region: "USA · San Francisco Bay Area",
            feedURL: "https://www.bart.gov/dev/schedules/google_transit.zip",
            routeTypes: "Subway · Rail"
        ),
        CuratedFeed(
            name: "MBTA",
            region: "USA · Boston",
            feedURL: "https://cdn.mbta.com/MBTA_GTFS.zip",
            routeTypes: "Rail · Subway · Bus · Ferry"
        ),
        CuratedFeed(
            name: "Chicago Transit Authority",
            region: "USA · Chicago",
            feedURL: "https://www.transitchicago.com/downloads/sch_data/google_transit.zip",
            routeTypes: "Subway · Rail · Bus"
        ),
        CuratedFeed(
            name: "LA Metro Rail",
            region: "USA · Los Angeles",
            feedURL: "https://gitlab.com/LACMTA/gtfs_rail/-/raw/master/gtfs_rail.zip",
            routeTypes: "Rail · Bus"
        ),
        CuratedFeed(
            name: "Metro Transit",
            region: "USA · Minneapolis–St. Paul",
            feedURL: "https://svc.metrotransit.org/mtgtfs/gtfs.zip",
            routeTypes: "Rail · Bus"
        ),
        CuratedFeed(
            name: "Denver RTD",
            region: "USA · Denver",
            feedURL: "https://www.rtd-denver.com/files/gtfs/google_transit.zip",
            routeTypes: "Rail · Bus"
        ),
        CuratedFeed(
            name: "Sound Transit",
            region: "USA · Seattle",
            feedURL: "https://www.soundtransit.org/sites/default/files/googletransit.zip",
            routeTypes: "Rail · Bus · Ferry"
        ),

        // MARK: Europe

        CuratedFeed(
            name: "SNCF TER (France)",
            region: "Europe · France",
            feedURL: "https://eu.ftp.opendatasoft.com/sncf/gtfs/export-ter-gtfs-last.zip",
            routeTypes: "Rail"
        ),
        CuratedFeed(
            name: "DB Fernverkehr (Germany)",
            region: "Europe · Germany",
            feedURL: "https://download.gtfs.de/germany/fv_free/latest.zip",
            routeTypes: "Rail"
        ),
        CuratedFeed(
            name: "ÖBB (Austria)",
            region: "Europe · Austria",
            feedURL: "https://data.oebb.at/oebb?dataset=datasets/gtfs",
            routeTypes: "Rail · Bus"
        ),

        // MARK: Canada

        CuratedFeed(
            name: "OC Transpo",
            region: "Canada · Ottawa",
            feedURL: "https://www.octranspo.com/files/google_transit.zip",
            routeTypes: "Bus · Rail"
        ),
        CuratedFeed(
            name: "Calgary Transit",
            region: "Canada · Calgary",
            feedURL: "https://data.calgary.ca/download/npk7-z3bj/application%2Fzip",
            routeTypes: "Bus · Rail"
        ),

        // MARK: Australia

        CuratedFeed(
            name: "Brisbane Translink",
            region: "Australia · Brisbane",
            feedURL: "https://gtfsrt.api.translink.com.au/GTFS/SEQ_GTFS.zip",
            routeTypes: "Rail · Bus · Ferry"
        ),
    ]

    static var regions: [String] {
        Array(Set(all.map { $0.region.components(separatedBy: " · ").first ?? $0.region })).sorted()
    }
}
