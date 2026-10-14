import type { AdOptions } from '../shared/ad-options.interface';

export interface NativeAdOptions extends AdOptions {
  /**
   * Colours of the native ad strip, as `#RRGGBB` (or `#AARRGGBB`).
   *
   * @since 8.1.0
   */
  style?: NativeAdStyle;
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
