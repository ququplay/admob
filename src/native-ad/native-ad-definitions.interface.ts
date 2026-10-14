import type { PluginListenerHandle } from '@capacitor/core';

import type { AdMobBannerSize } from '../banner/banner-size.interface';
import type { ValidateAllEventsEnumAreImplemented } from '../private/validate-all-events-implemented.type';
import type { AdMobError } from '../shared';

import type { NativeAdOptions } from './native-ad-options.interface';
import type { NativeAdPluginEvents } from './native-ad-plugin-events.enum';

// This is just to validate that we do not forget to implement any event name
export type NativeAdDefinitionsHasAllEvents = ValidateAllEventsEnumAreImplemented<
  NativeAdPluginEvents,
  NativeAdDefinitions
>;

export interface NativeAdDefinitions {
  /**
   * Show a native ad as a strip across the top of the screen.
   * Shows the ad loaded before when there is one and it has not expired, otherwise loads a new one.
   * Android and iOS; resolves without showing anything on the web.
   *
   * @group NativeAd
   * @param options NativeAdOptions
   * @since 8.1.0
   */
  showNativeAd(options: NativeAdOptions): Promise<void>;

  /**
   * Hide the native ad but keep it, so showNativeAd brings back the same ad.
   *
   * @group NativeAd
   * @since 8.1.0
   */
  hideNativeAd(): Promise<void>;

  /**
   * Destroy the native ad, remove it from screen.
   *
   * @group NativeAd
   * @since 8.1.0
   */
  removeNativeAd(): Promise<void>;

  /**
   * @group NativeAd
   * @param eventName nativeAdSizeChanged
   * @param listenerFunc
   * @since 8.1.0
   */
  addListener(
    eventName: NativeAdPluginEvents.SizeChanged,
    listenerFunc: (info: AdMobBannerSize) => void,
  ): Promise<PluginListenerHandle>;

  /**
   * @group NativeAd
   * @param eventName nativeAdLoaded
   * @param listenerFunc
   * @since 8.1.0
   */
  addListener(eventName: NativeAdPluginEvents.Loaded, listenerFunc: () => void): Promise<PluginListenerHandle>;

  /**
   * @group NativeAd
   * @param eventName nativeAdFailedToLoad
   * @param listenerFunc
   * @since 8.1.0
   */
  addListener(
    eventName: NativeAdPluginEvents.FailedToLoad,
    listenerFunc: (info: AdMobError) => void,
  ): Promise<PluginListenerHandle>;

  /**
   * @group NativeAd
   * @param eventName nativeAdClicked
   * @param listenerFunc
   * @since 8.1.0
   */
  addListener(eventName: NativeAdPluginEvents.Clicked, listenerFunc: () => void): Promise<PluginListenerHandle>;

  /**
   * @group NativeAd
   * @param eventName nativeAdImpression
   * @param listenerFunc
   * @since 8.1.0
   */
  addListener(eventName: NativeAdPluginEvents.AdImpression, listenerFunc: () => void): Promise<PluginListenerHandle>;
}
