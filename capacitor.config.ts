import type { CapacitorConfig } from '@capacitor/cli';

const config: CapacitorConfig = {
  appId: 'nl.keesvschriek.trainingsapp',
  appName: 'Training',
  webDir: 'dist',
  android: {
    backgroundColor: '#ffffff',
  },
  plugins: {
    // Verzoeken gaan via Android zelf, niet via de browser: geen CORS-gedoe met intervals.icu
    CapacitorHttp: { enabled: true },
    SystemBars: { insetsHandling: 'css', initialViewportFitValueHint: 'cover' },
  },
};

export default config;
