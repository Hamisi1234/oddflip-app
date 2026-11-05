import type { CapacitorConfig } from "@capacitor/cli";

const config: CapacitorConfig = {
  appId: "com.redcardalert.app",
  appName: "Red Card Alert",
  webDir: "dist",
  backgroundColor: "#FFFFFF",
  android: {
    backgroundColor: "#FFFFFF",
  },
  ios: {
    backgroundColor: "#FFFFFF",
    contentInset: "automatic",
  },
  plugins: {
    SplashScreen: {
      launchShowDuration: 1800,
      launchAutoHide: true,
      backgroundColor: "#E50914",
      showSpinner: false,
    },
    PushNotifications: {
      presentationOptions: ["badge", "sound", "alert"],
    },
  },
};

export default config;
