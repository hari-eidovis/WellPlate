import WidgetKit
import SwiftUI
import ActivityKit

@main
struct WellPlateWidgetBundle: WidgetBundle {
    var body: some Widget {
        StressWidget()
        FastingLiveActivity()
        BreathingLiveActivity()
    }
}
