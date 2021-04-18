import { Component, OnInit, OnDestroy, NgZone } from '@angular/core';
import { PluginListenerHandle } from '@capacitor/core';
import { ToastController } from '@ionic/angular';

import { AdMob, AdMobBannerSize, AdMobRewardItem, AdOptions, BannerAdOptions, BannerAdPluginEvents, BannerAdPosition, BannerAdSize, RewardAdPluginEvents} from '@capacitor-community/admob';
import { BehaviorSubject, ReplaySubject } from 'rxjs';

@Component({
  selector: 'app-home',
  templateUrl: 'home.page.html',
  styleUrls: ['home.page.scss'],
})
export class HomePage implements OnInit, OnDestroy {
  private readonly lastBannerEvent$$ = new ReplaySubject<{name: string, value: any}>(1);
  public readonly lastBannerEvent$ = this.lastBannerEvent$$.asObservable()
  
  private readonly lastRewardEvent$$ = new ReplaySubject<{name: string, value: any}>(1);
  public readonly lastRewardEvent$ = this.lastRewardEvent$$.asObservable()

  private readonly listenerHandlers: PluginListenerHandle[] = [];
  /**
   * Height of AdSize
   */
  private appMargin = 0;
  private bannerPosition: 'top' | 'bottom';

  /**
   * For ion-item of template disabled
   */
  public isPrepareBanner = false;
  public isPrepareReward = false;
  public isPrepareInterstitial = false;

  /**
   * Setting of Ads
   */
  private bannerTopOptions: BannerAdOptions = {
    adId: 'ca-app-pub-3940256099942544/2934735716',
    adSize: BannerAdSize.ADAPTIVE_BANNER,
    position: BannerAdPosition.TOP_CENTER,
    // npa: false,
  };

  private bannerBottomOptions: BannerAdOptions = {
    adId: 'ca-app-pub-3940256099942544/2934735716',
    adSize: BannerAdSize.ADAPTIVE_BANNER,
    position: BannerAdPosition.BOTTOM_CENTER,
    npa: true,
  };

  private rewardOptions: AdOptions = {
    adId: 'ca-app-pub-3940256099942544/5224354917',
  };

  private interstitialOptions: AdOptions = {
    adId: 'ca-app-pub-3940256099942544/1033173712',
  };

  public isLoading = false;

  constructor(
    private readonly toastCtrl: ToastController,
    private readonly ngZone: NgZone
  ) {
  }

  ngOnInit() {
    /**
     * Run every time the Ad height changes.
     * AdMob cannot be displayed above the content, so create margin for AdMob.
     */
    const resizeHandler = AdMob.addListener(BannerAdPluginEvents.SizeChanged, (info: AdMobBannerSize) => {
      console.log(['bannerViewChangeSize', info]);
      this.appMargin = info.height;
      if (this.appMargin > 0) {
        const body = document.querySelector('body');
        const bodyStyles = window.getComputedStyle(body);
        const safeAreaBottom = bodyStyles.getPropertyValue("--ion-safe-area-bottom");

        const app: HTMLElement = document.querySelector('ion-router-outlet');
        if (this.bannerPosition === 'top') {
          app.style.marginTop = this.appMargin + 'px';
        } else {
          app.style.marginBottom = `calc(${safeAreaBottom} + ${this.appMargin}px)`;
        }
      }
    });

    this.listenerHandlers.push(resizeHandler);

    this.registerRewardListeners();
    this.registerBannerListeners();

  }

  ngOnDestroy() {
    this.listenerHandlers.forEach(handler => handler.remove());
  }

  /**
   * ==================== BANNER ====================
   */
  async showTopBanner() {
    this.bannerPosition = 'top';
    const result = await AdMob.showBanner(this.bannerTopOptions)
      .catch(e => console.log(e));
    if (result === undefined) {
      return;
    }

    this.isPrepareBanner = true;
  }

  async showBottomBanner() {
    this.bannerPosition = 'bottom';
    const result = await AdMob.showBanner(this.bannerBottomOptions)
      .catch(e => console.log(e));
    if (result === undefined) {
      return;
    }

    this.isPrepareBanner = true;
  }



  async hideBanner() {
    const result = await AdMob.hideBanner()
      .catch(e => console.log(e));
    if (result === undefined) {
      return;
    }

    const app: HTMLElement = document.querySelector('ion-router-outlet');
    app.style.marginTop = '0px';
    app.style.marginBottom = '0px';
  }

  async resumeBanner() {
    const result = await AdMob.resumeBanner()
      .catch(e => console.log(e));
    if (result === undefined) {
      return;
    }

    const app: HTMLElement = document.querySelector('ion-router-outlet');
    app.style.marginBottom = this.appMargin + 'px';
  }

  async removeBanner() {
    const result = await AdMob.removeBanner()
      .catch(e => console.log(e));
    if (result === undefined) {
      return;
    }

    const app: HTMLElement = document.querySelector('ion-router-outlet');
    app.style.marginBottom = '0px';
    this.appMargin = 0;
    this.isPrepareBanner = false;
  }
  /**
   * ==================== /BANNER ====================
   */


  /**
   * ==================== REWARD ====================
   */
  async prepareReward() {
    this.isLoading = true;
    const result = await AdMob.prepareRewardVideoAd(this.rewardOptions)
      .catch(e => console.log(e))
      .finally(() => this.isLoading = false);
    if (result === undefined) {
      return;
    }
    this.isPrepareReward = true;
  }

  async showReward() {
    const result: AdMobRewardItem = await AdMob.showRewardVideoAd()
      .catch(e => undefined);
    if (result === undefined) {
      return;
    }
    const toast = await this.toastCtrl.create({
      message: `AdMob Reward received with currency: ${result.type}, amount ${result.amount}.`,
      duration: 2000,
    });
    await toast.present();

    this.isPrepareReward = false;
  }

  private registerRewardListeners(): void {
    const eventKeys = Object.keys(RewardAdPluginEvents);

    eventKeys.forEach(key => {
      console.log(`registering ${RewardAdPluginEvents[key]}`);
      const handler = AdMob.addListener(RewardAdPluginEvents[key], (value) => {
        console.log(`Reward Event "${key}"`, value);

        this.ngZone.run(() => {
          this.lastRewardEvent$$.next({name: key, value: value});
        })
        

      });
      this.listenerHandlers.push(handler);
    });
  }

  private registerBannerListeners(): void {
    const eventKeys = Object.keys(BannerAdPluginEvents);

    eventKeys.forEach(key => {
      console.log(`registering ${BannerAdPluginEvents[key]}`);
      const handler = AdMob.addListener(BannerAdPluginEvents[key], (value) => {
        console.log(`Banner Event "${key}"`, value);

        this.ngZone.run(() => {
          this.lastBannerEvent$$.next({name: key, value: value});
        })
        
      });
      this.listenerHandlers.push(handler);

    });
  }

  /**
   * ==================== /REWARD ====================
   */

  /**
   * ==================== Interstitial ====================
   */
  async prepareInterstitial() {
    this.isLoading = true;
    const result = AdMob.prepareInterstitial(this.interstitialOptions)
      .catch(e => console.log(e))
      .finally(() => this.isLoading = false);
    if (result === undefined) {
      return;
    }
    this.isPrepareInterstitial = true;
  }


  async showInterstitial() {
    const result = await AdMob.showInterstitial()
      .catch(e => console.log(e));
    if (result === undefined) {
      return;
    }
    this.isPrepareInterstitial = false;
  }

  /**
   * ==================== /Interstitial ====================
   */
}
