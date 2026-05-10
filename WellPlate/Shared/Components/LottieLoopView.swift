import SwiftUI
import Lottie

/// SwiftUI wrapper around `LottieAnimationView` that auto-detects whether the
/// resource is a dotLottie (`.lottie`) or classic JSON (`.json`) file.
struct LottieLoopView: UIViewRepresentable {
    let name: String
    var loopMode: LottieLoopMode = .loop
    var speed: CGFloat = 1.0
    var contentMode: UIView.ContentMode = .scaleAspectFit

    func makeUIView(context: Context) -> LottieAnimationView {
        let view = LottieAnimationView()
        view.loopMode = loopMode
        view.animationSpeed = speed
        view.contentMode = contentMode
        view.backgroundBehavior = .pauseAndRestore
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.setContentHuggingPriority(.defaultLow, for: .vertical)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)

        let resourceName = name
        let loop = loopMode

        if Bundle.main.url(forResource: resourceName, withExtension: "lottie") != nil {
            DotLottieFile.named(resourceName) { result in
                DispatchQueue.main.async {
                    if case .success(let file) = result {
                        view.loadAnimation(from: file)
                        view.loopMode = loop
                        view.play()
                    }
                }
            }
        } else {
            view.animation = LottieAnimation.named(resourceName)
            view.play()
        }

        return view
    }

    func updateUIView(_ uiView: LottieAnimationView, context: Context) {
        uiView.animationSpeed = speed
        uiView.loopMode = loopMode
        if !uiView.isAnimationPlaying { uiView.play() }
    }
}
