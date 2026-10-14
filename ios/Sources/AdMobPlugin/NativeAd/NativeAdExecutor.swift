import Foundation
import Capacitor
import GoogleMobileAds

/**
 * A native ad drawn as a strip across the top of the screen, below the status bar, over the WebView like a top banner.
 * Hiding keeps the loaded ad, so showing it again brings back the same ad without a new request.
 */
class NativeAdExecutor: NSObject, NativeAdLoaderDelegate, NativeAdDelegate {
    weak var plugin: AdMobPlugin?

    // A loaded native ad may be shown for an hour; a new one is loaded a little before that.
    private static let maxAdAge: TimeInterval = 55 * 60

    private var adView: NativeAdView?
    private var nativeAd: NativeAd?
    private var adLoader: AdLoader?
    private var loadedAdUnitID: String?
    private var loadedAt = Date.distantPast
    private var wantsVisible = false

    private let iconView = UIImageView()
    private let badgeLabel = PaddedLabel()
    private let headlineLabel = UILabel()
    private let bodyLabel = UILabel()
    private let callToActionLabel = PaddedLabel()
    private let divider = UIView()
    private let adChoicesView = AdChoicesView()

    func showNativeAd(_ call: CAPPluginCall, _ request: Request, _ adUnitID: String) {
        guard let rootViewController = plugin?.getRootVC() else {
            call.reject("AdMob: no view to show the native ad in")
            return
        }

        ensureAdView(in: rootViewController.view)
        applyStyle(call.getObject("style") ?? [:])
        wantsVisible = true

        if nativeAd != nil && loadedAdUnitID == adUnitID && !isExpired() {
            setVisible(true)
        } else {
            load(adUnitID, request, rootViewController)
        }

        call.resolve([:])
    }

    func hideNativeAd(_ call: CAPPluginCall) {
        wantsVisible = false
        if adView != nil {
            setVisible(false)
        }
        call.resolve([:])
    }

    func removeNativeAd(_ call: CAPPluginCall) {
        wantsVisible = false
        nativeAd = nil
        loadedAdUnitID = nil

        if let adView = adView {
            adView.removeFromSuperview()
            self.adView = nil
            notifySize(0, 0)
        }

        call.resolve([:])
    }

    private func load(_ adUnitID: String, _ request: Request, _ rootViewController: UIViewController) {
        if adLoader != nil { return }

        NSLog("AdMob: Native Ad ID: \(adUnitID)")
        let options = NativeAdViewAdOptions()
        options.preferredAdChoicesPosition = .topRightCorner

        let loader = AdLoader(adUnitID: adUnitID, rootViewController: rootViewController, adTypes: [.native], options: [options])
        loader.delegate = self
        adLoader = loader
        loader.load(request)
    }

    func adLoader(_ adLoader: AdLoader, didReceive nativeAd: NativeAd) {
        self.adLoader = nil

        // Removed while it loaded.
        guard let adView = adView else { return }

        nativeAd.delegate = self
        self.nativeAd = nativeAd
        loadedAdUnitID = adLoader.adUnitID
        loadedAt = Date()
        populate(adView, nativeAd)
        plugin?.notifyListeners(NativeAdPluginEvents.Loaded.rawValue, data: [:])

        if wantsVisible {
            setVisible(true)
        }
    }

    func adLoader(_ adLoader: AdLoader, didFailToReceiveAdWithError error: Error) {
        self.adLoader = nil
        NSLog("AdMob: native ad failed to load: \(error.localizedDescription)")

        // An expired ad may not be shown again; a fresh one keeps showing.
        if nativeAd != nil && isExpired() {
            nativeAd = nil
            loadedAdUnitID = nil
        }
        if nativeAd == nil && adView != nil {
            setVisible(false)
        }

        plugin?.notifyListeners(NativeAdPluginEvents.FailedToLoad.rawValue, data: [
            "code": (error as NSError).code,
            "message": error.localizedDescription
        ])
    }

    func nativeAdDidRecordClick(_ nativeAd: NativeAd) {
        plugin?.notifyListeners(NativeAdPluginEvents.Clicked.rawValue, data: [:])
    }

    func nativeAdDidRecordImpression(_ nativeAd: NativeAd) {
        plugin?.notifyListeners(NativeAdPluginEvents.AdImpression.rawValue, data: [:])
    }

    // Icon, "Ad" badge, headline and body, the call to action and AdChoices in the top right corner; a hairline along
    // the bottom separates it from the screen below. The wider trailing padding keeps the button clear of AdChoices.
    private func ensureAdView(in parent: UIView) {
        if adView != nil { return }

        let adView = NativeAdView()
        adView.translatesAutoresizingMaskIntoConstraints = false
        adView.isHidden = true

        iconView.contentMode = .scaleAspectFit
        badgeLabel.text = Locale.preferredLanguages.first?.hasPrefix("pl") == true ? "Reklama" : "Ad"
        badgeLabel.font = .boldSystemFont(ofSize: 10)
        badgeLabel.insets = UIEdgeInsets(top: 1, left: 4, bottom: 1, right: 4)
        badgeLabel.layer.cornerRadius = 3
        badgeLabel.layer.masksToBounds = true
        headlineLabel.font = .boldSystemFont(ofSize: 14)
        bodyLabel.font = .systemFont(ofSize: 12)
        callToActionLabel.font = .boldSystemFont(ofSize: 13)
        callToActionLabel.insets = UIEdgeInsets(top: 0, left: 12, bottom: 0, right: 12)
        callToActionLabel.layer.cornerRadius = 18
        callToActionLabel.layer.masksToBounds = true
        callToActionLabel.textAlignment = .center
        // The SDK handles taps on the ad's views.
        callToActionLabel.isUserInteractionEnabled = false

        let headlineRow = UIStackView(arrangedSubviews: [badgeLabel, headlineLabel])
        headlineRow.spacing = 6
        headlineRow.alignment = .center
        let texts = UIStackView(arrangedSubviews: [headlineRow, bodyLabel])
        texts.axis = .vertical
        texts.spacing = 2

        badgeLabel.setContentHuggingPriority(.required, for: .horizontal)
        badgeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        callToActionLabel.setContentHuggingPriority(.required, for: .horizontal)
        callToActionLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        for view in [iconView, texts, callToActionLabel, divider, adChoicesView] as [UIView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            adView.addSubview(view)
        }

        let content = UILayoutGuide()
        adView.addLayoutGuide(content)

        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: adView.topAnchor, constant: 6),
            content.leadingAnchor.constraint(equalTo: adView.leadingAnchor, constant: 12),
            content.trailingAnchor.constraint(equalTo: adView.trailingAnchor, constant: -20),
            content.bottomAnchor.constraint(equalTo: divider.topAnchor, constant: -7),
            content.heightAnchor.constraint(greaterThanOrEqualToConstant: 41),

            iconView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            iconView.centerYAnchor.constraint(equalTo: content.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 40),
            iconView.heightAnchor.constraint(equalToConstant: 40),

            texts.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 10),
            texts.centerYAnchor.constraint(equalTo: content.centerYAnchor),
            texts.topAnchor.constraint(greaterThanOrEqualTo: content.topAnchor),
            texts.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor),

            callToActionLabel.leadingAnchor.constraint(equalTo: texts.trailingAnchor, constant: 10),
            callToActionLabel.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            callToActionLabel.centerYAnchor.constraint(equalTo: content.centerYAnchor),
            callToActionLabel.heightAnchor.constraint(equalToConstant: 36),
            callToActionLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 64),
            callToActionLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 120),

            divider.leadingAnchor.constraint(equalTo: adView.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: adView.trailingAnchor),
            divider.bottomAnchor.constraint(equalTo: adView.bottomAnchor),
            divider.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale),

            adChoicesView.topAnchor.constraint(equalTo: adView.topAnchor),
            adChoicesView.trailingAnchor.constraint(equalTo: adView.trailingAnchor),
            adChoicesView.widthAnchor.constraint(equalToConstant: 15),
            adChoicesView.heightAnchor.constraint(equalToConstant: 15)
        ])

        adView.iconView = iconView
        adView.headlineView = headlineLabel
        adView.bodyView = bodyLabel
        adView.callToActionView = callToActionLabel
        adView.adChoicesView = adChoicesView

        // Below the status bar, like a banner at the top; it follows the safe area when that changes (rotation).
        parent.addSubview(adView)
        NSLayoutConstraint.activate([
            adView.topAnchor.constraint(equalTo: parent.safeAreaLayoutGuide.topAnchor),
            adView.leadingAnchor.constraint(equalTo: parent.leadingAnchor),
            adView.trailingAnchor.constraint(equalTo: parent.trailingAnchor)
        ])

        self.adView = adView
    }

    private func populate(_ adView: NativeAdView, _ nativeAd: NativeAd) {
        headlineLabel.text = nativeAd.headline
        bodyLabel.text = nativeAd.body
        bodyLabel.isHidden = nativeAd.body == nil
        iconView.image = nativeAd.icon?.image
        iconView.isHidden = nativeAd.icon == nil
        callToActionLabel.text = nativeAd.callToAction
        callToActionLabel.isHidden = nativeAd.callToAction == nil

        adView.nativeAd = nativeAd
    }

    private func applyStyle(_ style: JSObject) {
        let textColor = color(style["textColor"], .black)

        adView?.backgroundColor = color(style["backgroundColor"], .white)
        headlineLabel.textColor = textColor
        bodyLabel.textColor = color(style["secondaryTextColor"], textColor)
        badgeLabel.backgroundColor = color(style["buttonColor"], UIColor(red: 26 / 255, green: 115 / 255, blue: 232 / 255, alpha: 1))
        badgeLabel.textColor = color(style["buttonTextColor"], .white)
        callToActionLabel.backgroundColor = badgeLabel.backgroundColor
        callToActionLabel.textColor = badgeLabel.textColor
        divider.backgroundColor = color(style["dividerColor"], .clear)
    }

    private func setVisible(_ visible: Bool) {
        guard let adView = adView else { return }

        adView.isHidden = !visible

        if !visible {
            notifySize(0, 0)
            return
        }

        adView.superview?.layoutIfNeeded()
        notifySize(adView.frame.width, adView.frame.height)
    }

    private func notifySize(_ width: CGFloat, _ height: CGFloat) {
        plugin?.notifyListeners(NativeAdPluginEvents.SizeChanged.rawValue, data: [
            "width": Int(width.rounded()),
            "height": Int(height.rounded())
        ])
    }

    private func isExpired() -> Bool {
        return Date().timeIntervalSince(loadedAt) > NativeAdExecutor.maxAdAge
    }

    // "#RRGGBB" or "#AARRGGBB", as on Android.
    private func color(_ value: JSValue?, _ fallback: UIColor) -> UIColor {
        guard let string = value as? String, string.hasPrefix("#"),
              let number = UInt64(string.dropFirst(), radix: 16) else { return fallback }

        switch string.count {
        case 7:
            return UIColor(red: CGFloat((number >> 16) & 0xFF) / 255, green: CGFloat((number >> 8) & 0xFF) / 255,
                           blue: CGFloat(number & 0xFF) / 255, alpha: 1)
        case 9:
            return UIColor(red: CGFloat((number >> 16) & 0xFF) / 255, green: CGFloat((number >> 8) & 0xFF) / 255,
                           blue: CGFloat(number & 0xFF) / 255, alpha: CGFloat((number >> 24) & 0xFF) / 255)
        default:
            return fallback
        }
    }
}

// A label with padding around its text, for the badge and the call to action.
class PaddedLabel: UILabel {
    var insets = UIEdgeInsets.zero

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: insets))
    }

    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(width: size.width + insets.left + insets.right, height: size.height + insets.top + insets.bottom)
    }
}
