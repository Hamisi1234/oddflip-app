import { Capacitor } from "@capacitor/core";
import { Haptics, ImpactStyle } from "@capacitor/haptics";
import { PushNotifications, type PushNotificationSchema } from "@capacitor/push-notifications";
import { SplashScreen } from "@capacitor/splash-screen";
import { StatusBar, Style } from "@capacitor/status-bar";

export async function initializeNativeApp(
  onPushReceived: (notification: PushNotificationSchema) => void,
) {
  if (!Capacitor.isNativePlatform()) return;

  await Promise.allSettled([
    StatusBar.setStyle({ style: Style.Dark }),
    SplashScreen.hide(),
  ]);

  let permission = await PushNotifications.checkPermissions();
  if (permission.receive === "prompt") {
    permission = await PushNotifications.requestPermissions();
  }

  if (permission.receive === "granted") {
    await PushNotifications.register();
  }

  await PushNotifications.addListener("pushNotificationReceived", onPushReceived);
  await PushNotifications.addListener("pushNotificationActionPerformed", ({ notification }) => {
    onPushReceived(notification);
  });
}

export async function triggerNativeAlertHaptic() {
  if (!Capacitor.isNativePlatform()) return;
  await Haptics.impact({ style: ImpactStyle.Heavy });
  window.setTimeout(() => {
    void Haptics.impact({ style: ImpactStyle.Heavy });
  }, 180);
}
