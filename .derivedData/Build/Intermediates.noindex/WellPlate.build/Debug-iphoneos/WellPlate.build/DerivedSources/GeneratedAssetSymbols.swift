import Foundation
#if canImport(AppKit)
import AppKit
#endif
#if canImport(UIKit)
import UIKit
#endif
#if canImport(SwiftUI)
import SwiftUI
#endif
#if canImport(DeveloperToolsSupport)
import DeveloperToolsSupport
#endif

#if SWIFT_PACKAGE
private let resourceBundle = Foundation.Bundle.module
#else
private class ResourceBundleClass {}
private let resourceBundle = Foundation.Bundle(for: ResourceBundleClass.self)
#endif

// MARK: - Color Symbols -

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
extension DeveloperToolsSupport.ColorResource {

    /// The "AccentColor" asset catalog color resource.
    static let accent = DeveloperToolsSupport.ColorResource(name: "AccentColor", bundle: resourceBundle)

    /// The "AppPrimary" asset catalog color resource.
    static let appPrimary = DeveloperToolsSupport.ColorResource(name: "AppPrimary", bundle: resourceBundle)

    /// The "BorderSubtle" asset catalog color resource.
    static let borderSubtle = DeveloperToolsSupport.ColorResource(name: "BorderSubtle", bundle: resourceBundle)

    /// The "Error" asset catalog color resource.
    static let error = DeveloperToolsSupport.ColorResource(name: "Error", bundle: resourceBundle)

    /// The "OnPrimary" asset catalog color resource.
    static let onPrimary = DeveloperToolsSupport.ColorResource(name: "OnPrimary", bundle: resourceBundle)

    /// The "PrimaryContainer" asset catalog color resource.
    static let primaryContainer = DeveloperToolsSupport.ColorResource(name: "PrimaryContainer", bundle: resourceBundle)

    /// The "Success" asset catalog color resource.
    static let success = DeveloperToolsSupport.ColorResource(name: "Success", bundle: resourceBundle)

    /// The "Surface" asset catalog color resource.
    static let surface = DeveloperToolsSupport.ColorResource(name: "Surface", bundle: resourceBundle)

    /// The "TextPrimary" asset catalog color resource.
    static let textPrimary = DeveloperToolsSupport.ColorResource(name: "TextPrimary", bundle: resourceBundle)

    /// The "TextSecondary" asset catalog color resource.
    static let textSecondary = DeveloperToolsSupport.ColorResource(name: "TextSecondary", bundle: resourceBundle)

    /// The "Warning" asset catalog color resource.
    static let warning = DeveloperToolsSupport.ColorResource(name: "Warning", bundle: resourceBundle)

}

// MARK: - Image Symbols -

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
extension DeveloperToolsSupport.ImageResource {

    /// The "Good-Onboard" asset catalog image resource.
    static let goodOnboard = DeveloperToolsSupport.ImageResource(name: "Good-Onboard", bundle: resourceBundle)

    /// The "Groovy-Onboard" asset catalog image resource.
    static let groovyOnboard = DeveloperToolsSupport.ImageResource(name: "Groovy-Onboard", bundle: resourceBundle)

    /// The "Group 10" asset catalog image resource.
    static let group10 = DeveloperToolsSupport.ImageResource(name: "Group 10", bundle: resourceBundle)

    /// The "Group 11" asset catalog image resource.
    static let group11 = DeveloperToolsSupport.ImageResource(name: "Group 11", bundle: resourceBundle)

    /// The "Group 16" asset catalog image resource.
    static let group16 = DeveloperToolsSupport.ImageResource(name: "Group 16", bundle: resourceBundle)

    /// The "Group 17" asset catalog image resource.
    static let group17 = DeveloperToolsSupport.ImageResource(name: "Group 17", bundle: resourceBundle)

    /// The "Group 18" asset catalog image resource.
    static let group18 = DeveloperToolsSupport.ImageResource(name: "Group 18", bundle: resourceBundle)

    /// The "Group 9" asset catalog image resource.
    static let group9 = DeveloperToolsSupport.ImageResource(name: "Group 9", bundle: resourceBundle)

    /// The "Lemon-Onboard" asset catalog image resource.
    static let lemonOnboard = DeveloperToolsSupport.ImageResource(name: "Lemon-Onboard", bundle: resourceBundle)

    /// The "Today" asset catalog image resource.
    static let today = DeveloperToolsSupport.ImageResource(name: "Today", bundle: resourceBundle)

    /// The "logo" asset catalog image resource.
    static let logo = DeveloperToolsSupport.ImageResource(name: "logo", bundle: resourceBundle)

}

// MARK: - Color Symbol Extensions -

#if canImport(AppKit)
@available(macOS 14.0, *)
@available(macCatalyst, unavailable)
extension AppKit.NSColor {

    /// The "AccentColor" asset catalog color.
    static var accent: AppKit.NSColor {
#if !targetEnvironment(macCatalyst)
        .init(resource: .accent)
#else
        .init()
#endif
    }

    /// The "AppPrimary" asset catalog color.
    static var appPrimary: AppKit.NSColor {
#if !targetEnvironment(macCatalyst)
        .init(resource: .appPrimary)
#else
        .init()
#endif
    }

    /// The "BorderSubtle" asset catalog color.
    static var borderSubtle: AppKit.NSColor {
#if !targetEnvironment(macCatalyst)
        .init(resource: .borderSubtle)
#else
        .init()
#endif
    }

    /// The "Error" asset catalog color.
    static var error: AppKit.NSColor {
#if !targetEnvironment(macCatalyst)
        .init(resource: .error)
#else
        .init()
#endif
    }

    /// The "OnPrimary" asset catalog color.
    static var onPrimary: AppKit.NSColor {
#if !targetEnvironment(macCatalyst)
        .init(resource: .onPrimary)
#else
        .init()
#endif
    }

    /// The "PrimaryContainer" asset catalog color.
    static var primaryContainer: AppKit.NSColor {
#if !targetEnvironment(macCatalyst)
        .init(resource: .primaryContainer)
#else
        .init()
#endif
    }

    /// The "Success" asset catalog color.
    static var success: AppKit.NSColor {
#if !targetEnvironment(macCatalyst)
        .init(resource: .success)
#else
        .init()
#endif
    }

    /// The "Surface" asset catalog color.
    static var surface: AppKit.NSColor {
#if !targetEnvironment(macCatalyst)
        .init(resource: .surface)
#else
        .init()
#endif
    }

    /// The "TextPrimary" asset catalog color.
    static var textPrimary: AppKit.NSColor {
#if !targetEnvironment(macCatalyst)
        .init(resource: .textPrimary)
#else
        .init()
#endif
    }

    /// The "TextSecondary" asset catalog color.
    static var textSecondary: AppKit.NSColor {
#if !targetEnvironment(macCatalyst)
        .init(resource: .textSecondary)
#else
        .init()
#endif
    }

    /// The "Warning" asset catalog color.
    static var warning: AppKit.NSColor {
#if !targetEnvironment(macCatalyst)
        .init(resource: .warning)
#else
        .init()
#endif
    }

}
#endif

#if canImport(UIKit)
@available(iOS 17.0, tvOS 17.0, *)
@available(watchOS, unavailable)
extension UIKit.UIColor {

    /// The "AccentColor" asset catalog color.
    static var accent: UIKit.UIColor {
#if !os(watchOS)
        .init(resource: .accent)
#else
        .init()
#endif
    }

    /// The "AppPrimary" asset catalog color.
    static var appPrimary: UIKit.UIColor {
#if !os(watchOS)
        .init(resource: .appPrimary)
#else
        .init()
#endif
    }

    /// The "BorderSubtle" asset catalog color.
    static var borderSubtle: UIKit.UIColor {
#if !os(watchOS)
        .init(resource: .borderSubtle)
#else
        .init()
#endif
    }

    /// The "Error" asset catalog color.
    static var error: UIKit.UIColor {
#if !os(watchOS)
        .init(resource: .error)
#else
        .init()
#endif
    }

    /// The "OnPrimary" asset catalog color.
    static var onPrimary: UIKit.UIColor {
#if !os(watchOS)
        .init(resource: .onPrimary)
#else
        .init()
#endif
    }

    /// The "PrimaryContainer" asset catalog color.
    static var primaryContainer: UIKit.UIColor {
#if !os(watchOS)
        .init(resource: .primaryContainer)
#else
        .init()
#endif
    }

    /// The "Success" asset catalog color.
    static var success: UIKit.UIColor {
#if !os(watchOS)
        .init(resource: .success)
#else
        .init()
#endif
    }

    /// The "Surface" asset catalog color.
    static var surface: UIKit.UIColor {
#if !os(watchOS)
        .init(resource: .surface)
#else
        .init()
#endif
    }

    /// The "TextPrimary" asset catalog color.
    static var textPrimary: UIKit.UIColor {
#if !os(watchOS)
        .init(resource: .textPrimary)
#else
        .init()
#endif
    }

    /// The "TextSecondary" asset catalog color.
    static var textSecondary: UIKit.UIColor {
#if !os(watchOS)
        .init(resource: .textSecondary)
#else
        .init()
#endif
    }

    /// The "Warning" asset catalog color.
    static var warning: UIKit.UIColor {
#if !os(watchOS)
        .init(resource: .warning)
#else
        .init()
#endif
    }

}
#endif

#if canImport(SwiftUI)
@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
extension SwiftUI.Color {

    /// The "AccentColor" asset catalog color.
    static var accent: SwiftUI.Color { .init(.accent) }

    /// The "AppPrimary" asset catalog color.
    static var appPrimary: SwiftUI.Color { .init(.appPrimary) }

    /// The "BorderSubtle" asset catalog color.
    static var borderSubtle: SwiftUI.Color { .init(.borderSubtle) }

    /// The "Error" asset catalog color.
    static var error: SwiftUI.Color { .init(.error) }

    /// The "OnPrimary" asset catalog color.
    static var onPrimary: SwiftUI.Color { .init(.onPrimary) }

    /// The "PrimaryContainer" asset catalog color.
    static var primaryContainer: SwiftUI.Color { .init(.primaryContainer) }

    /// The "Success" asset catalog color.
    static var success: SwiftUI.Color { .init(.success) }

    /// The "Surface" asset catalog color.
    static var surface: SwiftUI.Color { .init(.surface) }

    /// The "TextPrimary" asset catalog color.
    static var textPrimary: SwiftUI.Color { .init(.textPrimary) }

    /// The "TextSecondary" asset catalog color.
    static var textSecondary: SwiftUI.Color { .init(.textSecondary) }

    /// The "Warning" asset catalog color.
    static var warning: SwiftUI.Color { .init(.warning) }

}

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
extension SwiftUI.ShapeStyle where Self == SwiftUI.Color {

    /// The "AccentColor" asset catalog color.
    static var accent: SwiftUI.Color { .init(.accent) }

    /// The "AppPrimary" asset catalog color.
    static var appPrimary: SwiftUI.Color { .init(.appPrimary) }

    /// The "BorderSubtle" asset catalog color.
    static var borderSubtle: SwiftUI.Color { .init(.borderSubtle) }

    /// The "Error" asset catalog color.
    static var error: SwiftUI.Color { .init(.error) }

    /// The "OnPrimary" asset catalog color.
    static var onPrimary: SwiftUI.Color { .init(.onPrimary) }

    /// The "PrimaryContainer" asset catalog color.
    static var primaryContainer: SwiftUI.Color { .init(.primaryContainer) }

    /// The "Success" asset catalog color.
    static var success: SwiftUI.Color { .init(.success) }

    /// The "Surface" asset catalog color.
    static var surface: SwiftUI.Color { .init(.surface) }

    /// The "TextPrimary" asset catalog color.
    static var textPrimary: SwiftUI.Color { .init(.textPrimary) }

    /// The "TextSecondary" asset catalog color.
    static var textSecondary: SwiftUI.Color { .init(.textSecondary) }

    /// The "Warning" asset catalog color.
    static var warning: SwiftUI.Color { .init(.warning) }

}
#endif

// MARK: - Image Symbol Extensions -

#if canImport(AppKit)
@available(macOS 14.0, *)
@available(macCatalyst, unavailable)
extension AppKit.NSImage {

    /// The "Good-Onboard" asset catalog image.
    static var goodOnboard: AppKit.NSImage {
#if !targetEnvironment(macCatalyst)
        .init(resource: .goodOnboard)
#else
        .init()
#endif
    }

    /// The "Groovy-Onboard" asset catalog image.
    static var groovyOnboard: AppKit.NSImage {
#if !targetEnvironment(macCatalyst)
        .init(resource: .groovyOnboard)
#else
        .init()
#endif
    }

    /// The "Group 10" asset catalog image.
    static var group10: AppKit.NSImage {
#if !targetEnvironment(macCatalyst)
        .init(resource: .group10)
#else
        .init()
#endif
    }

    /// The "Group 11" asset catalog image.
    static var group11: AppKit.NSImage {
#if !targetEnvironment(macCatalyst)
        .init(resource: .group11)
#else
        .init()
#endif
    }

    /// The "Group 16" asset catalog image.
    static var group16: AppKit.NSImage {
#if !targetEnvironment(macCatalyst)
        .init(resource: .group16)
#else
        .init()
#endif
    }

    /// The "Group 17" asset catalog image.
    static var group17: AppKit.NSImage {
#if !targetEnvironment(macCatalyst)
        .init(resource: .group17)
#else
        .init()
#endif
    }

    /// The "Group 18" asset catalog image.
    static var group18: AppKit.NSImage {
#if !targetEnvironment(macCatalyst)
        .init(resource: .group18)
#else
        .init()
#endif
    }

    /// The "Group 9" asset catalog image.
    static var group9: AppKit.NSImage {
#if !targetEnvironment(macCatalyst)
        .init(resource: .group9)
#else
        .init()
#endif
    }

    /// The "Lemon-Onboard" asset catalog image.
    static var lemonOnboard: AppKit.NSImage {
#if !targetEnvironment(macCatalyst)
        .init(resource: .lemonOnboard)
#else
        .init()
#endif
    }

    /// The "Today" asset catalog image.
    static var today: AppKit.NSImage {
#if !targetEnvironment(macCatalyst)
        .init(resource: .today)
#else
        .init()
#endif
    }

    /// The "logo" asset catalog image.
    static var logo: AppKit.NSImage {
#if !targetEnvironment(macCatalyst)
        .init(resource: .logo)
#else
        .init()
#endif
    }

}
#endif

#if canImport(UIKit)
@available(iOS 17.0, tvOS 17.0, *)
@available(watchOS, unavailable)
extension UIKit.UIImage {

    /// The "Good-Onboard" asset catalog image.
    static var goodOnboard: UIKit.UIImage {
#if !os(watchOS)
        .init(resource: .goodOnboard)
#else
        .init()
#endif
    }

    /// The "Groovy-Onboard" asset catalog image.
    static var groovyOnboard: UIKit.UIImage {
#if !os(watchOS)
        .init(resource: .groovyOnboard)
#else
        .init()
#endif
    }

    /// The "Group 10" asset catalog image.
    static var group10: UIKit.UIImage {
#if !os(watchOS)
        .init(resource: .group10)
#else
        .init()
#endif
    }

    /// The "Group 11" asset catalog image.
    static var group11: UIKit.UIImage {
#if !os(watchOS)
        .init(resource: .group11)
#else
        .init()
#endif
    }

    /// The "Group 16" asset catalog image.
    static var group16: UIKit.UIImage {
#if !os(watchOS)
        .init(resource: .group16)
#else
        .init()
#endif
    }

    /// The "Group 17" asset catalog image.
    static var group17: UIKit.UIImage {
#if !os(watchOS)
        .init(resource: .group17)
#else
        .init()
#endif
    }

    /// The "Group 18" asset catalog image.
    static var group18: UIKit.UIImage {
#if !os(watchOS)
        .init(resource: .group18)
#else
        .init()
#endif
    }

    /// The "Group 9" asset catalog image.
    static var group9: UIKit.UIImage {
#if !os(watchOS)
        .init(resource: .group9)
#else
        .init()
#endif
    }

    /// The "Lemon-Onboard" asset catalog image.
    static var lemonOnboard: UIKit.UIImage {
#if !os(watchOS)
        .init(resource: .lemonOnboard)
#else
        .init()
#endif
    }

    /// The "Today" asset catalog image.
    static var today: UIKit.UIImage {
#if !os(watchOS)
        .init(resource: .today)
#else
        .init()
#endif
    }

    /// The "logo" asset catalog image.
    static var logo: UIKit.UIImage {
#if !os(watchOS)
        .init(resource: .logo)
#else
        .init()
#endif
    }

}
#endif

// MARK: - Thinnable Asset Support -

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
@available(watchOS, unavailable)
extension DeveloperToolsSupport.ColorResource {

    private init?(thinnableName: Swift.String, bundle: Foundation.Bundle) {
#if canImport(AppKit) && os(macOS)
        if AppKit.NSColor(named: NSColor.Name(thinnableName), bundle: bundle) != nil {
            self.init(name: thinnableName, bundle: bundle)
        } else {
            return nil
        }
#elseif canImport(UIKit) && !os(watchOS)
        if UIKit.UIColor(named: thinnableName, in: bundle, compatibleWith: nil) != nil {
            self.init(name: thinnableName, bundle: bundle)
        } else {
            return nil
        }
#else
        return nil
#endif
    }

}

#if canImport(AppKit)
@available(macOS 14.0, *)
@available(macCatalyst, unavailable)
extension AppKit.NSColor {

    private convenience init?(thinnableResource: DeveloperToolsSupport.ColorResource?) {
#if !targetEnvironment(macCatalyst)
        if let resource = thinnableResource {
            self.init(resource: resource)
        } else {
            return nil
        }
#else
        return nil
#endif
    }

}
#endif

#if canImport(UIKit)
@available(iOS 17.0, tvOS 17.0, *)
@available(watchOS, unavailable)
extension UIKit.UIColor {

    private convenience init?(thinnableResource: DeveloperToolsSupport.ColorResource?) {
#if !os(watchOS)
        if let resource = thinnableResource {
            self.init(resource: resource)
        } else {
            return nil
        }
#else
        return nil
#endif
    }

}
#endif

#if canImport(SwiftUI)
@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
extension SwiftUI.Color {

    private init?(thinnableResource: DeveloperToolsSupport.ColorResource?) {
        if let resource = thinnableResource {
            self.init(resource)
        } else {
            return nil
        }
    }

}

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
extension SwiftUI.ShapeStyle where Self == SwiftUI.Color {

    private init?(thinnableResource: DeveloperToolsSupport.ColorResource?) {
        if let resource = thinnableResource {
            self.init(resource)
        } else {
            return nil
        }
    }

}
#endif

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
@available(watchOS, unavailable)
extension DeveloperToolsSupport.ImageResource {

    private init?(thinnableName: Swift.String, bundle: Foundation.Bundle) {
#if canImport(AppKit) && os(macOS)
        if bundle.image(forResource: NSImage.Name(thinnableName)) != nil {
            self.init(name: thinnableName, bundle: bundle)
        } else {
            return nil
        }
#elseif canImport(UIKit) && !os(watchOS)
        if UIKit.UIImage(named: thinnableName, in: bundle, compatibleWith: nil) != nil {
            self.init(name: thinnableName, bundle: bundle)
        } else {
            return nil
        }
#else
        return nil
#endif
    }

}

#if canImport(AppKit)
@available(macOS 14.0, *)
@available(macCatalyst, unavailable)
extension AppKit.NSImage {

    private convenience init?(thinnableResource: DeveloperToolsSupport.ImageResource?) {
#if !targetEnvironment(macCatalyst)
        if let resource = thinnableResource {
            self.init(resource: resource)
        } else {
            return nil
        }
#else
        return nil
#endif
    }

}
#endif

#if canImport(UIKit)
@available(iOS 17.0, tvOS 17.0, *)
@available(watchOS, unavailable)
extension UIKit.UIImage {

    private convenience init?(thinnableResource: DeveloperToolsSupport.ImageResource?) {
#if !os(watchOS)
        if let resource = thinnableResource {
            self.init(resource: resource)
        } else {
            return nil
        }
#else
        return nil
#endif
    }

}
#endif

