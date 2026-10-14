package com.getcapacitor.community.admob.nativead

enum class NativeAdPluginEvents(val webEventName: String) {
    SizeChanged("nativeAdSizeChanged"),
    Loaded("nativeAdLoaded"),
    FailedToLoad("nativeAdFailedToLoad"),
    Clicked("nativeAdClicked"),
    AdImpression("nativeAdImpression"),
}
