//
//  TraiWidgetsBundle.swift
//  TraiWidgets
//
//  Created by Nadav Avital on 1/20/26.
//

import WidgetKit
import SwiftUI

@main
struct TraiWidgetsBundle: WidgetBundle {
    var body: some Widget {
        TraiWidgets()
        TraiWidgetsControl()
        TraiWidgetsLiveActivity()
    }
}
