// CuratedFeeds.swift
// Built-in list of popular transit agencies with confirmed-public GTFS feed URLs.
// All feeds are freely accessible without API keys or registration unless noted.
// URLs verified May 2026 — use "Enter custom GTFS URL" if a feed stops working.
//
// Agencies intentionally omitted:
//   WMATA (DC Metro)  — requires a registered API key; no public ZIP URL.
//   NJ Transit        — requires account registration to download.
//   SEPTA (Philly)    — requires clicking through a web licence form.
//   ÖBB (Austria)     — same ToS click-through issue; see https://data.oebb.at

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

        // MARK: USA — sorted alphabetically by city

        CuratedFeed(
            name: "Amtrak",
            region: "USA · National",
            feedURL: "https://content.amtrak.com/content/gtfs/GTFS.zip",
            routeTypes: "Rail"
        ),
        CuratedFeed(
            name: "MARTA",
            region: "USA · Atlanta",
            // Official MARTA developer page — no API key. Updated Apr 2026.
            // Source: https://itsmarta.com/app-developer-resources.aspx
            feedURL: "https://www.itsmarta.com/google_transit_feed/google_transit.zip",
            routeTypes: "Rail · Bus"
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
            name: "Metra",
            region: "USA · Chicago",
            // Metra commuter rail. Static feed, no API key required.
            // Source: https://metra.com/metra-gtfs-api
            feedURL: "https://schedules.metrarail.com/gtfs/schedule.zip",
            routeTypes: "Commuter Rail"
        ),
        CuratedFeed(
            name: "DART",
            region: "USA · Dallas",
            // Official DART fixed-route schedule page — HTTPS, no API key.
            // DART server returns 404 for HEAD requests (use GET fallback in tests).
            // Source: https://www.dart.org/about/about-dart/fixed-route-schedule
            feedURL: "https://www.dart.org/transitdata/latest/google_transit.zip",
            routeTypes: "Light Rail · Bus"
        ),
        CuratedFeed(
            name: "Denver RTD",
            region: "USA · Denver",
            feedURL: "https://www.rtd-denver.com/files/gtfs/google_transit.zip",
            routeTypes: "Rail · Bus"
        ),
        CuratedFeed(
            name: "Houston Metro",
            region: "USA · Houston",
            // URL sourced from Transitland Atlas feed registry (May 2026).
            // The legacy ridemetro.org/Downloads path is no longer active.
            feedURL: "https://metro.resourcespace.com/pages/download.php?ref=4835&ext=zip",
            routeTypes: "Rail · Bus"
        ),
        CuratedFeed(
            name: "LA Metro Rail",
            region: "USA · Los Angeles",
            feedURL: "https://gitlab.com/LACMTA/gtfs_rail/-/raw/master/gtfs_rail.zip",
            routeTypes: "Rail · Bus"
        ),
        CuratedFeed(
            name: "Miami-Dade Transit",
            region: "USA · Miami",
            // Official Miami-Dade open data feeds page — no API key.
            // Source: https://www.miamidade.gov/global/transportation/open-data-feeds.page
            feedURL: "https://www.miamidade.gov/transit/googletransit/current/google_transit.zip",
            routeTypes: "Metrorail · Bus"
        ),
        CuratedFeed(
            name: "Metro Transit",
            region: "USA · Minneapolis–St. Paul",
            feedURL: "https://svc.metrotransit.org/mtgtfs/gtfs.zip",
            routeTypes: "Rail · Bus"
        ),
        CuratedFeed(
            name: "NYC Subway (MTA)",
            region: "USA · New York",
            // Official MTA developer feed — no API key required.
            // Source: https://www.mta.info/developers (verified May 2026)
            feedURL: "https://rrgtfsfeeds.s3.amazonaws.com/gtfs_subway.zip",
            routeTypes: "Subway"
        ),
        CuratedFeed(
            name: "MTA Metro-North",
            region: "USA · New York",
            // MTA commuter rail serving NYC northern suburbs and Connecticut.
            // Source: https://www.mta.info/developers
            feedURL: "https://rrgtfsfeeds.s3.amazonaws.com/gtfsmnr.zip",
            routeTypes: "Commuter Rail"
        ),
        CuratedFeed(
            name: "MTA Long Island Rail Road",
            region: "USA · New York",
            // Source: https://www.mta.info/developers
            feedURL: "https://rrgtfsfeeds.s3.amazonaws.com/gtfslirr.zip",
            routeTypes: "Commuter Rail"
        ),
        CuratedFeed(
            name: "PATH",
            region: "USA · New York",
            // Port Authority Trans-Hudson (NY ⇄ NJ). PANYNJ has no stable keyless
            // direct ZIP, so we use the freely accessible Trillium-hosted mirror
            // (no API key / registration). Verified June 2026.
            // NOTE: NJ Transit rail/bus still omitted — see header (account login).
            feedURL: "https://data.trilliumtransit.com/gtfs/path-nj-us/path-nj-us.zip",
            routeTypes: "Rapid Transit · Rail"
        ),
        CuratedFeed(
            name: "Valley Metro",
            region: "USA · Phoenix",
            // City of Phoenix Open Data portal (ArcGIS). Resource ID is stable.
            // Source: https://www.phoenixopendata.com
            feedURL: "https://phoenixopendata.com/dataset/3eae9a4a-98b9-40c8-8df7-8c00c1756235/resource/28ccc0a5-49c8-495c-b91f-193de5ce2cb7/download/googletransit.zip",
            routeTypes: "Light Rail · Bus"
        ),
        CuratedFeed(
            name: "TriMet",
            region: "USA · Portland",
            // Official TriMet developer page — no API key required.
            // Source: https://developer.trimet.org/GTFS.shtml
            feedURL: "https://developer.trimet.org/schedule/gtfs.zip",
            routeTypes: "Light Rail · Bus · Streetcar"
        ),
        CuratedFeed(
            name: "UTA (TRAX)",
            region: "USA · Salt Lake City",
            // Utah Transit Authority — TRAX light rail, FrontRunner commuter rail, bus.
            // Source: https://www.rideuta.com/data
            feedURL: "https://gtfsfeed.rideuta.com/GTFS.zip",
            routeTypes: "Light Rail · Commuter Rail · Bus"
        ),
        CuratedFeed(
            name: "BART",
            region: "USA · San Francisco Bay Area",
            feedURL: "https://www.bart.gov/dev/schedules/google_transit.zip",
            routeTypes: "Subway · Rail"
        ),
        CuratedFeed(
            name: "SFMTA / Muni",
            region: "USA · San Francisco",
            // SFMTA posts data under a licence agreement (view at sfmta.com/reports/gtfs-transit-data).
            // The download URL is publicly accessible without authentication.
            feedURL: "https://muni-gtfs.apps.sfmta.com/data/muni_gtfs-current.zip",
            routeTypes: "Streetcar · Cable Car · Bus"
        ),
        CuratedFeed(
            name: "Sound Transit",
            region: "USA · Seattle",
            // Old URL (sites/default/files/googletransit.zip) returned HTTP 404.
            // New URL from Sound Transit Open Transit Data portal (May 2026).
            feedURL: "https://www.soundtransit.org/GTFS-rail/40_gtfs.zip",
            routeTypes: "Rail · Bus"
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
        // ÖBB (Austria) — official feed at https://data.oebb.at requires clicking
        // through a licence agreement in a browser; no unauthenticated direct ZIP URL
        // is available. Use "Enter custom GTFS URL" after downloading manually.

        // MARK: Canada

        CuratedFeed(
            name: "OC Transpo",
            region: "Canada · Ottawa",
            // Old URL (octranspo.com/files/…) returned HTTP 404 after April 2025.
            // New feed is hosted on Azure Front Door.
            feedURL: "https://oct-gtfs-emasagcnfmcgeham.z01.azurefd.net/public-access/GTFSExport.zip",
            routeTypes: "Bus · Rail"
        ),
        CuratedFeed(
            name: "TTC",
            region: "Canada · Toronto",
            // City of Toronto Open Data (CKAN). Resource ID is stable.
            // Source: https://open.toronto.ca/dataset/ttc-routes-and-schedules/
            feedURL: "https://ckan0.cf.opendata.inter.prod-toronto.ca/dataset/7795b45e-e65a-4465-81fc-c36b9dfff169/resource/cfb6b2b8-6191-41e3-bda1-b175c51148cb/download/TTC%20Routes%20and%20Schedules%20Data.zip",
            routeTypes: "Subway · Bus · Streetcar"
        ),
        CuratedFeed(
            name: "TransLink",
            region: "Canada · Vancouver",
            // Official TransLink GTFS static feed — updated weekly, no API key.
            // Source: https://www.translink.ca/about-us/doing-business-with-translink/app-developer-resources/gtfs/gtfs-data
            feedURL: "https://gtfs-static.translink.ca/gtfs/google_transit.zip",
            routeTypes: "Rail · Bus · Ferry"
        ),
        CuratedFeed(
            name: "Calgary Transit",
            region: "Canada · Calgary",
            // Direct attachment URL from Open Calgary portal (Socrata). blobId verified May 2026.
            feedURL: "https://data.calgary.ca/api/views/npk7-z3bj/files/5bd6ab18-b1e5-44be-8915-cf0d4d7ddce0?filename=CT_GTFS.zip",
            routeTypes: "Bus · Rail"
        ),

        // MARK: Australia

        CuratedFeed(
            name: "Transport for NSW",
            region: "Australia · Sydney",
            // TfNSW Open Data Hub — no API key required. CC BY licence.
            // Resource ID 67974f14 has been stable since 2016.
            // Note: ~280 MB download; parsing may take 30–60 s on device.
            feedURL: "https://opendata.transport.nsw.gov.au/data/dataset/d1f68d4f-b778-44df-9823-cf2fa922e47f/resource/67974f14-01bf-47b7-bfa5-c7f2f8a950ca/download/full_greater_sydney_gtfs_static_0.zip",
            routeTypes: "Rail · Bus · Ferry · Light Rail"
        ),
        CuratedFeed(
            name: "PTV (Metro Trains Melbourne)",
            region: "Australia · Melbourne",
            // Transport Victoria Open Data — no API key required. CC BY 4.0.
            // Covers trains, trams, and buses statewide. ~200 MB download.
            // Source: https://opendata.transport.vic.gov.au/dataset/gtfs-schedule
            feedURL: "https://opendata.transport.vic.gov.au/dataset/3f4e292e-7f8a-4ffe-831f-1953be0fe448/resource/fb152201-859f-4882-9206-b768060b50ad/download/gtfs.zip",
            routeTypes: "Rail · Tram · Bus"
        ),
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
