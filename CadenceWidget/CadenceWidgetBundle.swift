import WidgetKit
import SwiftUI
import ActivityKit

@main
struct CadenceWidgetBundle: WidgetBundle {
    var body: some Widget {
        StressWidget()
        FastingLiveActivity()
    }
}
