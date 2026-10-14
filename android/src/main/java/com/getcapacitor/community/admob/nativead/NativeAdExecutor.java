package com.getcapacitor.community.admob.nativead;

import android.app.Activity;
import android.content.Context;
import android.graphics.Color;
import android.graphics.drawable.GradientDrawable;
import android.os.Build;
import android.os.SystemClock;
import android.util.Log;
import android.view.Gravity;
import android.view.LayoutInflater;
import android.view.View;
import android.view.ViewGroup;
import android.view.ViewTreeObserver;
import android.widget.Button;
import android.widget.ImageView;
import android.widget.TextView;
import androidx.annotation.NonNull;
import androidx.coordinatorlayout.widget.CoordinatorLayout;
import androidx.core.util.Supplier;
import androidx.core.view.ViewCompat;
import androidx.core.view.WindowInsetsCompat;
import com.getcapacitor.JSObject;
import com.getcapacitor.PluginCall;
import com.getcapacitor.community.admob.admob.R;
import com.getcapacitor.community.admob.helpers.AdViewIdHelper;
import com.getcapacitor.community.admob.helpers.RequestHelper;
import com.getcapacitor.community.admob.models.AdMobPluginError;
import com.getcapacitor.community.admob.models.AdOptions;
import com.getcapacitor.community.admob.models.Executor;
import com.google.android.gms.ads.AdListener;
import com.google.android.gms.ads.AdLoader;
import com.google.android.gms.ads.AdRequest;
import com.google.android.gms.ads.LoadAdError;
import com.google.android.gms.ads.nativead.NativeAd;
import com.google.android.gms.ads.nativead.NativeAdView;
import com.google.android.gms.common.util.BiConsumer;

/**
 * A native ad drawn as a strip across the top of the screen, over the WebView, like a top banner.
 * Hiding keeps the loaded ad, so showing it again brings back the same ad without a new request.
 */
public class NativeAdExecutor extends Executor {

    public static final String NATIVE_TESTER_ID = "ca-app-pub-3940256099942544/2247696110";

    // A loaded native ad may be shown for an hour; a new one is loaded a little before that.
    private static final long MAX_AD_AGE_MS = 55 * 60 * 1000;

    private final JSObject emptyObject = new JSObject();
    private ViewGroup mViewGroup;
    private NativeAdView mAdView;
    private NativeAd mNativeAd;
    private String mLoadedAdId;
    private long mLoadedAt;
    private boolean mLoading;
    private boolean mWantsVisible;
    // The status bar can change height while the ad is up (rotation, display size), so its margin follows it.
    private final ViewTreeObserver.OnGlobalLayoutListener insetListener = () -> {
        if (mAdView != null) applyTopInset();
    };

    public NativeAdExecutor(
        Supplier<Context> contextSupplier,
        Supplier<Activity> activitySupplier,
        BiConsumer<String, JSObject> notifyListenersFunction,
        String pluginLogTag
    ) {
        super(contextSupplier, activitySupplier, notifyListenersFunction, pluginLogTag, "NativeAdExecutor");
    }

    public void initialize() {
        mViewGroup = (ViewGroup) ((ViewGroup) activitySupplier.get().findViewById(android.R.id.content)).getChildAt(0);
    }

    public void showNativeAd(final PluginCall call) {
        final AdOptions adOptions = AdOptions.getFactory().createGenericOptions(call, NATIVE_TESTER_ID);
        final JSObject style = call.getObject("style", new JSObject());

        activitySupplier
            .get()
            .runOnUiThread(() -> {
                try {
                    ensureAdView();
                    applyStyle(style);
                    applyTopInset();
                    mWantsVisible = true;

                    final AdRequest adRequest = RequestHelper.createRequest(adOptions);
                    final String adId = AdViewIdHelper.getFinalAdId(adOptions, adRequest, logTag, contextSupplier.get());

                    if (mNativeAd != null && adId.equals(mLoadedAdId) && !isExpired()) {
                        setVisible(true);
                    } else {
                        load(adId, adRequest);
                    }

                    call.resolve();
                } catch (Exception ex) {
                    call.reject(ex.getLocalizedMessage(), ex);
                }
            });
    }

    public void hideNativeAd(final PluginCall call) {
        activitySupplier
            .get()
            .runOnUiThread(() -> {
                mWantsVisible = false;
                if (mAdView != null) {
                    setVisible(false);
                }
                call.resolve();
            });
    }

    public void removeNativeAd(final PluginCall call) {
        activitySupplier
            .get()
            .runOnUiThread(() -> {
                mWantsVisible = false;
                destroyNativeAd();

                if (mAdView != null) {
                    activitySupplier.get().getWindow().getDecorView().getViewTreeObserver().removeOnGlobalLayoutListener(insetListener);
                    mAdView.destroy();
                    mViewGroup.removeView(mAdView);
                    mAdView = null;
                    notifySize(0, 0);
                    Log.d(logTag, "Native AD Removed");
                }

                call.resolve();
            });
    }

    private void load(String adId, AdRequest adRequest) {
        if (mLoading) return;

        mLoading = true;
        Log.d(logTag, "Native Ad ID: " + adId);

        final AdLoader adLoader = new AdLoader.Builder(contextSupplier.get(), adId)
            .forNativeAd((nativeAd) -> {
                mLoading = false;
                final Activity activity = activitySupplier.get();

                // Removed, or the app went away, while it loaded.
                if (mAdView == null || activity == null || activity.isDestroyed()) {
                    nativeAd.destroy();
                    return;
                }

                destroyNativeAd();
                mNativeAd = nativeAd;
                mLoadedAdId = adId;
                mLoadedAt = SystemClock.elapsedRealtime();
                populate(nativeAd);
                notifyListeners(NativeAdPluginEvents.Loaded.getWebEventName(), emptyObject);

                if (mWantsVisible) {
                    setVisible(true);
                }
            })
            .withAdListener(
                new AdListener() {
                    @Override
                    public void onAdFailedToLoad(@NonNull LoadAdError adError) {
                        mLoading = false;

                        // An expired ad may not be shown again; a fresh one keeps showing.
                        if (mNativeAd != null && isExpired()) {
                            destroyNativeAd();
                        }
                        if (mNativeAd == null && mAdView != null) {
                            setVisible(false);
                        }

                        notifyListeners(NativeAdPluginEvents.FailedToLoad.getWebEventName(), new AdMobPluginError(adError));
                    }

                    @Override
                    public void onAdClicked() {
                        notifyListeners(NativeAdPluginEvents.Clicked.getWebEventName(), emptyObject);
                    }

                    @Override
                    public void onAdImpression() {
                        notifyListeners(NativeAdPluginEvents.AdImpression.getWebEventName(), emptyObject);
                    }
                }
            )
            .build();

        adLoader.loadAd(adRequest);
    }

    private void ensureAdView() {
        if (mAdView != null) return;

        if (mViewGroup == null) {
            initialize();
        }

        mAdView = (NativeAdView) LayoutInflater.from(activitySupplier.get()).inflate(R.layout.admob_native_ad_strip, mViewGroup, false);

        final CoordinatorLayout.LayoutParams params = new CoordinatorLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.WRAP_CONTENT
        );
        params.gravity = Gravity.TOP;
        mAdView.setLayoutParams(params);
        mAdView.setVisibility(View.GONE);

        mAdView.setHeadlineView(mAdView.findViewById(R.id.admob_native_ad_headline));
        mAdView.setBodyView(mAdView.findViewById(R.id.admob_native_ad_body));
        mAdView.setIconView(mAdView.findViewById(R.id.admob_native_ad_icon));
        mAdView.setCallToActionView(mAdView.findViewById(R.id.admob_native_ad_call_to_action));
        mAdView.setAdChoicesView(mAdView.findViewById(R.id.admob_native_ad_choices));

        mViewGroup.addView(mAdView);
        activitySupplier.get().getWindow().getDecorView().getViewTreeObserver().addOnGlobalLayoutListener(insetListener);
    }

    private void populate(NativeAd nativeAd) {
        ((TextView) mAdView.getHeadlineView()).setText(nativeAd.getHeadline());

        final TextView body = (TextView) mAdView.getBodyView();
        body.setText(nativeAd.getBody());
        body.setVisibility(nativeAd.getBody() == null ? View.GONE : View.VISIBLE);

        final ImageView icon = (ImageView) mAdView.getIconView();
        if (nativeAd.getIcon() == null) {
            icon.setVisibility(View.GONE);
        } else {
            icon.setImageDrawable(nativeAd.getIcon().getDrawable());
            icon.setVisibility(View.VISIBLE);
        }

        final Button callToAction = (Button) mAdView.getCallToActionView();
        callToAction.setText(nativeAd.getCallToAction());
        callToAction.setVisibility(nativeAd.getCallToAction() == null ? View.GONE : View.VISIBLE);

        mAdView.setNativeAd(nativeAd);
    }

    private void applyStyle(JSObject style) {
        final int backgroundColor = parseColor(style.getString("backgroundColor"), Color.WHITE);
        final int textColor = parseColor(style.getString("textColor"), Color.BLACK);
        final int secondaryTextColor = parseColor(style.getString("secondaryTextColor"), textColor);
        final int buttonColor = parseColor(style.getString("buttonColor"), Color.rgb(26, 115, 232));
        final int buttonTextColor = parseColor(style.getString("buttonTextColor"), Color.WHITE);
        final int dividerColor = parseColor(style.getString("dividerColor"), Color.TRANSPARENT);
        final float density = contextSupplier.get().getResources().getDisplayMetrics().density;

        mAdView.setBackgroundColor(backgroundColor);
        mAdView.findViewById(R.id.admob_native_ad_divider).setBackgroundColor(dividerColor);
        ((TextView) mAdView.getHeadlineView()).setTextColor(textColor);
        ((TextView) mAdView.getBodyView()).setTextColor(secondaryTextColor);

        final TextView badge = mAdView.findViewById(R.id.admob_native_ad_badge);
        badge.setBackground(rounded(buttonColor, 3 * density));
        badge.setTextColor(buttonTextColor);

        final Button callToAction = (Button) mAdView.getCallToActionView();
        callToAction.setBackground(rounded(buttonColor, 18 * density));
        callToAction.setTextColor(buttonTextColor);
    }

    // Below the status bar where the app draws under it (Android 15+), like a banner at the top.
    private void applyTopInset() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.VANILLA_ICE_CREAM) return;

        final WindowInsetsCompat insets = ViewCompat.getRootWindowInsets(activitySupplier.get().getWindow().getDecorView());
        final int topInset = insets == null ? 0 : insets.getInsets(WindowInsetsCompat.Type.systemBars()).top;
        final CoordinatorLayout.LayoutParams params = (CoordinatorLayout.LayoutParams) mAdView.getLayoutParams();

        if (params.topMargin != topInset) {
            params.topMargin = topInset;
            mAdView.setLayoutParams(params);
        }
    }

    private void setVisible(boolean visible) {
        mAdView.setVisibility(visible ? View.VISIBLE : View.GONE);

        if (!visible) {
            notifySize(0, 0);
            return;
        }

        // The height is known once it is laid out.
        mAdView.post(() -> {
            if (mAdView == null || mAdView.getVisibility() != View.VISIBLE) return;

            final float density = contextSupplier.get().getResources().getDisplayMetrics().density;
            notifySize(Math.round(mAdView.getWidth() / density), Math.round(mAdView.getHeight() / density));
        });
    }

    private void notifySize(int width, int height) {
        final JSObject size = new JSObject();
        size.put("width", width);
        size.put("height", height);
        notifyListeners(NativeAdPluginEvents.SizeChanged.getWebEventName(), size);
    }

    private void destroyNativeAd() {
        if (mNativeAd == null) return;

        mNativeAd.destroy();
        mNativeAd = null;
        mLoadedAdId = null;
    }

    private boolean isExpired() {
        return SystemClock.elapsedRealtime() - mLoadedAt > MAX_AD_AGE_MS;
    }

    private static GradientDrawable rounded(int color, float radius) {
        final GradientDrawable drawable = new GradientDrawable();
        drawable.setColor(color);
        drawable.setCornerRadius(radius);
        return drawable;
    }

    private static int parseColor(String color, int fallback) {
        if (color == null) return fallback;

        try {
            return Color.parseColor(color);
        } catch (IllegalArgumentException ex) {
            return fallback;
        }
    }
}
