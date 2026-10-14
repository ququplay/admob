// This enum should be keep in sync with their native equivalents with the same name
export enum NativeAdPluginEvents {
  /**
   * The strip's size in dp; 0 when it is hidden or removed.
   */
  SizeChanged = 'nativeAdSizeChanged',
  Loaded = 'nativeAdLoaded',
  FailedToLoad = 'nativeAdFailedToLoad',
  Clicked = 'nativeAdClicked',
  AdImpression = 'nativeAdImpression',
}
