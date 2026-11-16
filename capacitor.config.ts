import type { CapacitorConfig } from '@capacitor/cli';

const config: CapacitorConfig = {
  appId: 'nl.keesvschriek.trainingsapp',
  appName: 'K',
  webDir: 'dist',
  android: {
    backgroundColor: '#ffffff',
  },
  plugins: {
    // Verzoeken gaan via Android zelf, niet via de browser: geen CORS-gedoe met intervals.icu
    CapacitorHttp: { enabled: true },
    SystemBars: { insetsHandling: 'css', initialViewportFitValueHint: 'cover' },
    LocalNotifications: { smallIcon: 'ic_stat_training', iconColor: '#111111' },
  },
};

export default config;
