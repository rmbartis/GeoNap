//
//  NapStopWatchWidgetBundle.swift
//  NapStopWatchWidget
//
//  Created by bartis on 7/11/26.
//

import WidgetKit
import SwiftUI

// The plain widget stub Xcode's wizard generates alongside this bundle
// has been emptied out (see NapStopWatchWidget.swift) — this extension
// only ships the real complication, NapStopComplication.

@main
struct NapStopWatchWidgetBundle: WidgetBundle {
    var body: some Widget {
        NapStopComplication()
    }
}
