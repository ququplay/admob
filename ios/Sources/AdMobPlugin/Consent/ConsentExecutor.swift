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
                    call.resolve([
                        "status": self.getConsentStatusString(ConsentInformation.shared.consentStatus),
                        "isConsentFormAvailable": ConsentInformation.shared.formStatus == FormStatus.available,
                        "canRequestAds": ConsentInformation.shared.canRequestAds,
                        "privacyOptionsRequirementStatus": self.getPrivacyOptionsRequirementStatus(ConsentInformation.shared.privacyOptionsRequirementStatus),
                        "canShowAds": self.canShowAds(),
                        "canShowPersonalizedAds": self.canShowPersonalizedAds(),
                        "isConsentOutdated": self.isConsentOutdated()
                    ])
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

    func showConsentForm(_ call: CAPPluginCall) {
        guard let rootViewController = plugin?.getRootVC() else {
            call.reject("No ViewController available", "NO_VIEW_CONTROLLER")
            return
        }

        let formStatus = ConsentInformation.shared.formStatus
        guard formStatus == FormStatus.available else {
            call.reject("Consent Form not available. Current status: \(formStatus.rawValue)", "FORM_NOT_AVAILABLE")
            return
        }

        ConsentForm.load { [weak self] form, loadError in
            guard let self = self else { return }

            if let error = loadError {
                let errorMessage = "Failed to load consent form: \(error.localizedDescription)"
                print("AdMob Consent Error: \(errorMessage)")
                call.reject(errorMessage, "LOAD_ERROR", error)
                return
            }

            guard let consentForm = form else {
                call.reject("Consent form is nil after successful load", "FORM_NIL")
                return
            }

            DispatchQueue.main.async {
                consentForm.present(from: rootViewController) { [weak self] dismissError in
                    guard let self = self else { return }

                    if let error = dismissError {
                        let errorMessage = "Failed to present consent form: \(error.localizedDescription)"
                        print("AdMob Consent Error: \(errorMessage)")
                        call.reject(errorMessage, "PRESENT_ERROR", error)
                        return
                    }

                    // Form was presented and dismissed successfully
                    let response = self.buildConsentResponse()
                    call.resolve(response)
                }
            }
        }
    }

    private func buildConsentResponse() -> [String: Any] {
        return [
            "status": getConsentStatusString(ConsentInformation.shared.consentStatus),
            "canRequestAds": ConsentInformation.shared.canRequestAds,
            "privacyOptionsRequirementStatus": getPrivacyOptionsRequirementStatus(ConsentInformation.shared.privacyOptionsRequirementStatus),
            "canShowAds": canShowAds(),
            "canShowPersonalizedAds": canShowPersonalizedAds(),
            "isConsentOutdated": isConsentOutdated()
        ]
    }

    func resetConsentInfo(_ call: CAPPluginCall) {
        ConsentInformation.shared.reset()
        call.resolve()
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

        // https://github.com/InteractiveAdvertisingBureau/GDPR-Transparency-and-Consent-Framework/blob/master/TCFv2/IAB%20Tech%20Lab%20-%20CMP%20API%20v2.md#in-app-details
        // https://support.google.com/admob/answer/9760862?hl=en&ref_topic=9756841

        let purposeConsent = settings.string(forKey: "IABTCF_PurposeConsents") ?? ""
        let vendorConsent = settings.string(forKey: "IABTCF_VendorConsents") ?? ""
        let vendorLI = settings.string(forKey: "IABTCF_VendorLegitimateInterests") ?? ""
        let purposeLI = settings.string(forKey: "IABTCF_PurposeLegitimateInterests") ?? ""

        let googleId = 755
        let hasGoogleVendorConsent = hasAttribute(input: vendorConsent, index: googleId)
        let hasGoogleVendorLI = hasAttribute(input: vendorLI, index: googleId)

        // Minimum required for at least non-personalized ads
        return hasConsentFor([1], purposeConsent, hasGoogleVendorConsent)
            && hasConsentOrLegitimateInterestFor([2, 7, 9, 10], purposeConsent, purposeLI, hasGoogleVendorConsent, hasGoogleVendorLI)

    }

    private func canShowPersonalizedAds() -> Bool {
        let settings = UserDefaults.standard

        // https://github.com/InteractiveAdvertisingBureau/GDPR-Transparency-and-Consent-Framework/blob/master/TCFv2/IAB%20Tech%20Lab%20-%20CMP%20API%20v2.md#in-app-details
        // https://support.google.com/admob/answer/9760862?hl=en&ref_topic=9756841

        // required for personalized ads
        let purposeConsent = settings.string(forKey: "IABTCF_PurposeConsents") ?? ""
        let vendorConsent = settings.string(forKey: "IABTCF_VendorConsents") ?? ""
        let vendorLI = settings.string(forKey: "IABTCF_VendorLegitimateInterests") ?? ""
        let purposeLI = settings.string(forKey: "IABTCF_PurposeLegitimateInterests") ?? ""

        let googleId = 755
        let hasGoogleVendorConsent = hasAttribute(input: vendorConsent, index: googleId)
        let hasGoogleVendorLI = hasAttribute(input: vendorLI, index: googleId)

        return hasConsentFor([1, 3, 4], purposeConsent, hasGoogleVendorConsent)
            && hasConsentOrLegitimateInterestFor([2, 7, 9, 10], purposeConsent, purposeLI, hasGoogleVendorConsent, hasGoogleVendorLI)
    }

    private func isConsentOutdated() -> Bool {
        let settings = UserDefaults.standard
        guard let tcString = settings.string(forKey: "IABTCF_TCString"), !tcString.isEmpty else {
            return false
        }

        // base64 alphabet used to store data in IABTCF string
        let base64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"

        // date is stored in digits 1..7 of the IABTCF string
        let dateSubstring = String(tcString[tcString.index(tcString.startIndex, offsetBy: 1)..<tcString.index(tcString.startIndex, offsetBy: 7)])

        // interpret date substring as base64-encoded integer value
        var timestamp: Int64 = 0

        for char in dateSubstring {
            if let value = base64.firstIndex(of: char) {
                timestamp = timestamp * 64 + Int64(value.utf16Offset(in: base64))
            }
        }

        // timestamp is given in deci-seconds, convert to milliseconds
        timestamp *= 100

        // compare with current timestamp to get age in days
        let daysAgo = (Int64(Date().timeIntervalSince1970 * 1000) - timestamp) / (1000 * 60 * 60 * 24)

        // delete TC string if age is over a year
        if daysAgo > 365 {
            settings.removeObject(forKey: "IABTCF_TCString")
            return true
        }

        return false
    }
}
