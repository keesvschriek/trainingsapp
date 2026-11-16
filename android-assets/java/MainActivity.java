package nl.keesvschriek.trainingsapp;

import android.content.Intent;
import android.os.Bundle;
import com.getcapacitor.BridgeActivity;

public class MainActivity extends BridgeActivity {
    @Override
    public void onCreate(Bundle savedInstanceState) {
        // Eigen koppeling tussen de app en de widget op het startscherm, en delen naar K
        registerPlugin(WidgetBridgePlugin.class);
        super.onCreate(savedInstanceState);
        keepShared(getIntent());
    }

    @Override
    protected void onNewIntent(Intent intent) {
        super.onNewIntent(intent);
        setIntent(intent);
        keepShared(intent);
    }

    /** Gedeelde tekst of link (Delen > K) bewaren tot de app hem ophaalt. */
    private void keepShared(Intent intent) {
        if (intent == null || !Intent.ACTION_SEND.equals(intent.getAction())) return;
        String text = intent.getStringExtra(Intent.EXTRA_TEXT);
        if (text == null || text.isEmpty()) return;
        String subject = intent.getStringExtra(Intent.EXTRA_SUBJECT);
        WidgetStore.setShared(this, text, subject == null ? "" : subject);
    }
}
