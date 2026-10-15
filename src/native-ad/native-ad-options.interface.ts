import type { AdOptions } from '../shared/ad-options.interface';

export interface NativeAdOptions extends AdOptions {
  /**
   * Colours of the native ad strip, as `#RRGGBB` (or `#AARRGGBB`).
   *
   * @since 8.1.0
   */
  style?: NativeAdStyle;

  /**
   * Seconds the ad stays on screen before a new one replaces it. Only the time it is shown counts: hidden, or with
   * the app in the background, it waits. The old ad stays up until the new one loads. 0, the default, keeps it until
   * it expires after an hour.
   *
   * @since 8.2.0
   */
  refreshInterval?: number;
}

export interface NativeAdStyle {
  /**
   * Background of the strip. Defaults to white.
   */
  backgroundColor?: string;

  /**
   * Headline text. Defaults to black.
   */
  textColor?: string;

  /**
   * Body text. Defaults to textColor.
   */
  secondaryTextColor?: string;

  /**
   * Call-to-action button and "Ad" badge background.
   */
  buttonColor?: string;

  /**
   * Call-to-action button and "Ad" badge text. Defaults to white.
   */
  buttonTextColor?: string;

  /**
   * Hairline along the bottom of the strip. Defaults to none.
   */
  dividerColor?: string;
}
