import Foundation
import Capacitor
import GoogleMobileAds
import UserMessagingPlatform

class ConsentExecutor: NSObject {
    weak var plugin: AdMobPlugin?

    func requestConsentInfo(_ call: CAPPluginCall, _ debugGeography: Int, _ testDeviceIdentifiers: [String], _ tagForUnderAgeOfConsent: Bool) {
        let parameters = RequestParameters()
        let debugSettings = DebugSettings()

        debugSettings.geography = DebugGeography(rawValue: debugGeography) ?? DebugGeography.disabled
        debugSettings.testDeviceIdentifiers = testDeviceIdentifiers

        parameters.debugSettings = debugSettings
        parameters.isTaggedForUnderAgeOfConsent = tagForUnderAgeOfConsent

        // Request an update to the consent information.
        ConsentInformation.shared.requestConsentInfoUpdate(
            with: parameters,
            completionHandler: { error in
                if error != nil {
                    call.reject("Request consent info failed")
                } else {
                    call.resolve(self.getConsentInfoDictionary())
                }
            })
    }

    @MainActor
    func showPrivacyOptionsForm(_ call: CAPPluginCall) {
        guard let rootViewController = plugin?.getRootVC() else {
            return call.reject("No ViewController")
        }

        Task {
            do {
                try await ConsentForm.presentPrivacyOptionsForm(from: rootViewController)
                call.resolve()
            } catch {
                call.reject("Failed to show privacy options form: \(error.localizedDescription)")
            }
        }
    }

    @MainActor
    func showConsentForm(_ call: CAPPluginCall) {
        guard let rootViewController = plugin?.getRootVC() else {
            return call.reject("No ViewController")
        }

        guard ConsentInformation.shared.formStatus == FormStatus.available else {
            return call.reject("Consent Form not available")
        }

        Task {
            do {
                let form = try await ConsentForm.load()
                try await form.present(from: rootViewController)
                call.resolve(getConsentInfoDictionary())
            } catch {
                call.reject("Request consent info failed")
            }
        }
    }

    func resetConsentInfo(_ call: CAPPluginCall) {
        ConsentInformation.shared.reset()
        call.resolve()
    }

    private func getConsentInfoDictionary() -> [String: Any] {
        // Check (and possibly purge) outdated consent before reading the
        // remaining values, so they reflect the post-cleanup state.
        let isConsentOutdated = isConsentOutdated()

        return [
            "status": getConsentStatusString(ConsentInformation.shared.consentStatus),
            "isConsentFormAvailable": ConsentInformation.shared.formStatus == FormStatus.available,
            "canRequestAds": ConsentInformation.shared.canRequestAds,
            "privacyOptionsRequirementStatus": getPrivacyOptionsRequirementStatus(ConsentInformation.shared.privacyOptionsRequirementStatus),
            "canShowAds": canShowAds(),
            "canShowPersonalizedAds": canShowPersonalizedAds(),
            "isConsentOutdated": isConsentOutdated
        ]
    }

    func getConsentStatusString(_ consentStatus: ConsentStatus) -> String {
        switch consentStatus {
        case ConsentStatus.required:
            return "REQUIRED"
        case ConsentStatus.notRequired:
            return "NOT_REQUIRED"
        case ConsentStatus.obtained:
            return "OBTAINED"
        default:
            return "UNKNOWN"
        }
    }

    func isGDPR() -> Bool {
        let settings = UserDefaults.standard
        let gdpr = settings.integer(forKey: "IABTCF_gdprApplies")
        return gdpr == 1
    }

    // Check if a binary string has a "1" at position "index" (1-based)
    private func hasAttribute(input: String, index: Int) -> Bool {
        return input.count >= index && String(Array(input)[index-1]) == "1"
    }

    // Check if consent is given for a list of purposes
    private func hasConsentFor(_ purposes: [Int], _ purposeConsent: String, _ hasVendorConsent: Bool) -> Bool {
        return purposes.allSatisfy { i in hasAttribute(input: purposeConsent, index: i) } && hasVendorConsent
    }

    // Check if a vendor either has consent or legitimate interest for a list of purposes
    private func hasConsentOrLegitimateInterestFor(_ purposes: [Int], _ purposeConsent: String, _ purposeLI: String, _ hasVendorConsent: Bool, _ hasVendorLI: Bool) -> Bool {
        return purposes.allSatisfy { i in
            (hasAttribute(input: purposeLI, index: i) && hasVendorLI) ||
            (hasAttribute(input: purposeConsent, index: i) && hasVendorConsent)
        }
    }

    private func canShowAds() -> Bool {
        let settings = UserDefaults.standard

        //https://github.com/InteractiveAdvertisingBureau/GDPR-Transparency-and-Consent-Framework/blob/master/TCFv2/IAB%20Tech%20Lab%20-%20CMP%20API%20v2.md#in-app-details
        //https://support.google.com/admob/answer/9760862?hl=en&ref_topic=9756841

        let purposeConsent = settings.string(forKey: "IABTCF_PurposeConsents") ?? ""
        let vendorConsent = settings.string(forKey: "IABTCF_VendorConsents") ?? ""
        let vendorLI = settings.string(forKey: "IABTCF_VendorLegitimateInterests") ?? ""
        let purposeLI = settings.string(forKey: "IABTCF_PurposeLegitimateInterests") ?? ""

        let googleId = 755
        let hasGoogleVendorConsent = hasAttribute(input: vendorConsent, index: googleId)
        let hasGoogleVendorLI = hasAttribute(input: vendorLI, index: googleId)

        // Minimum required for at least non-personalized ads
        return hasConsentFor([1], purposeConsent, hasGoogleVendorConsent)
            && hasConsentOrLegitimateInterestFor([2,7,9,10], purposeConsent, purposeLI, hasGoogleVendorConsent, hasGoogleVendorLI)

    }

    private func canShowPersonalizedAds() -> Bool {
        let settings = UserDefaults.standard

        //https://github.com/InteractiveAdvertisingBureau/GDPR-Transparency-and-Consent-Framework/blob/master/TCFv2/IAB%20Tech%20Lab%20-%20CMP%20API%20v2.md#in-app-details
        //https://support.google.com/admob/answer/9760862?hl=en&ref_topic=9756841

        // required for personalized ads
        let purposeConsent = settings.string(forKey: "IABTCF_PurposeConsents") ?? ""
        let vendorConsent = settings.string(forKey: "IABTCF_VendorConsents") ?? ""
        let vendorLI = settings.string(forKey: "IABTCF_VendorLegitimateInterests") ?? ""
        let purposeLI = settings.string(forKey: "IABTCF_PurposeLegitimateInterests") ?? ""

        let googleId = 755
        let hasGoogleVendorConsent = hasAttribute(input: vendorConsent, index: googleId)
        let hasGoogleVendorLI = hasAttribute(input: vendorLI, index: googleId)

        return hasConsentFor([1,3,4], purposeConsent, hasGoogleVendorConsent)
            && hasConsentOrLegitimateInterestFor([2,7,9,10], purposeConsent, purposeLI, hasGoogleVendorConsent, hasGoogleVendorLI)
    }

    /// Erases ALL core IAB TCF records simultaneously to prevent leaving
    /// orphaned consent data that will crash Google Ad serving.
    private func clearAllTCFPreferences(_ settings: UserDefaults) {
        settings.removeObject(forKey: "IABTCF_TCString")
        settings.removeObject(forKey: "IABTCF_PurposeConsents")
        settings.removeObject(forKey: "IABTCF_VendorConsents")
        settings.removeObject(forKey: "IABTCF_PurposeLegitimateInterests")
        settings.removeObject(forKey: "IABTCF_VendorLegitimateInterests")
        settings.removeObject(forKey: "IABTCF_gdprApplies") // Force SDK to reassess context
        NSLog("AdMob: Successfully purged all IABTCF tracking variables from UserDefaults.")
    }

    private func isConsentOutdated() -> Bool {
        let settings = UserDefaults.standard
        guard let tcString = settings.string(forKey: "IABTCF_TCString"), !tcString.isEmpty else {
            return false
        }

        // 1. Safety Boundary Check: If string is way too short, it's corrupted.
        if tcString.count < 7 {
            clearAllTCFPreferences(settings)
            return true
        }

        // Base64url alphabet used in IAB TCF specifications
        let base64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"

        // 2. Extract and Validate TCF Specification Version (First 6 bits / 1st character)
        let versionChar = tcString[tcString.startIndex]
        let tcfVersion = base64.firstIndex(of: versionChar)?.utf16Offset(in: base64) ?? -1

        // TCF v2.0 through v2.3 strings all use a '2' value in the version bit field
        if tcfVersion != 2 {
            clearAllTCFPreferences(settings)
            return true
        }

        // 3. Extract and Parse Timestamp (Characters at indexes 1 through 6 inclusive)
        let dateSubstring = String(tcString[tcString.index(tcString.startIndex, offsetBy: 1)..<tcString.index(tcString.startIndex, offsetBy: 7)])

        var timestamp: Int64 = 0
        for char in dateSubstring {
            guard let value = base64.firstIndex(of: char) else {
                clearAllTCFPreferences(settings)
                return true
            }
            timestamp = timestamp * 64 + Int64(value.utf16Offset(in: base64))
        }

        // Timestamp is given in deci-seconds, convert to milliseconds
        timestamp *= 100

        // 4. Calculate Age in Days
        let daysAgo = (Int64(Date().timeIntervalSince1970 * 1000) - timestamp) / (1000 * 60 * 60 * 24)

        // 5. Enforce Expiration Hard Limits
        // Google hard-caps ad server acceptance at 395 days (13 months).
        // The IAB TCF policy requires CMP re-checks at 365 days (12 months).
        if daysAgo > 365 || daysAgo < 0 {
            clearAllTCFPreferences(settings)
            return true
        }

        return false
    }
    func getPrivacyOptionsRequirementStatus(_ requirementStatus: PrivacyOptionsRequirementStatus) -> String {
        switch requirementStatus {
        case PrivacyOptionsRequirementStatus.required:
            return "REQUIRED"
        case PrivacyOptionsRequirementStatus.notRequired:
            return "NOT_REQUIRED"
        default:
            return "UNKNOWN"
        }
    }
}
