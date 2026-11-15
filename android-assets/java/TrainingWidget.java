package nl.keesvschriek.trainingsapp;

import android.app.PendingIntent;
import android.appwidget.AppWidgetManager;
import android.appwidget.AppWidgetProvider;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.widget.RemoteViews;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.Locale;
import org.json.JSONArray;
import org.json.JSONObject;

/** Widget op het startscherm: training van vandaag en een knop voor push-ups tussendoor. */
public class TrainingWidget extends AppWidgetProvider {
    static final String ACTION_ADD = "nl.keesvschriek.trainingsapp.PUSHUPS_ADD";
    private static final Locale NL = Locale.forLanguageTag("nl-NL");

    @Override
    public void onUpdate(Context context, AppWidgetManager manager, int[] ids) {
        for (int id : ids) manager.updateAppWidget(id, build(context));
    }

    @Override
    public void onReceive(Context context, Intent intent) {
        super.onReceive(context, intent);
        if (ACTION_ADD.equals(intent.getAction())) {
            JSONObject snap = WidgetStore.snapshot(context);
            int n = snap.optInt("setSize", 20);
            WidgetStore.addPending(context, today(), n);
            refreshAll(context);
        }
    }

    static void refreshAll(Context context) {
        AppWidgetManager manager = AppWidgetManager.getInstance(context);
        int[] ids = manager.getAppWidgetIds(new ComponentName(context, TrainingWidget.class));
        RemoteViews views = build(context);
        for (int id : ids) manager.updateAppWidget(id, views);
    }

    private static String today() {
        return new SimpleDateFormat("yyyy-MM-dd", Locale.US).format(new Date());
    }

    private static RemoteViews build(Context context) {
        RemoteViews v = new RemoteViews(context.getPackageName(), R.layout.widget_training);
        JSONObject snap = WidgetStore.snapshot(context);
        String date = today();

        JSONObject day = snap.optJSONObject("days") != null ? snap.optJSONObject("days").optJSONObject(date) : null;
        String dayName = new SimpleDateFormat("EEEE d MMMM", NL).format(new Date());
        v.setTextViewText(R.id.w_date, dayName.substring(0, 1).toUpperCase(NL) + dayName.substring(1));
        if (day != null) {
            v.setTextViewText(R.id.w_title, day.optString("title", "Training"));
            v.setTextViewText(R.id.w_sub, day.optString("sub", ""));
        } else {
            v.setTextViewText(R.id.w_title, "Open de app");
            v.setTextViewText(R.id.w_sub, "Dan laadt de widget je schema.");
        }

        int goal = Math.max(1, snap.optInt("goal", 100));
        int setSize = snap.optInt("setSize", 20);
        JSONObject counts = snap.optJSONObject("counts");
        int total = counts != null ? counts.optInt(date, 0) : 0;
        JSONArray pending = WidgetStore.pending(context);
        for (int i = 0; i < pending.length(); i++) {
            JSONObject p = pending.optJSONObject(i);
            if (p != null && date.equals(p.optString("date"))) total += p.optInt("value", 0);
        }
        boolean rest = day != null && day.optBoolean("rest", false);

        v.setTextViewText(R.id.w_count, total + " / " + goal);
        String label = total >= goal ? "Push-ups: doel gehaald" : rest ? "Push-ups: rustdag" : "Push-ups vandaag";
        v.setTextViewText(R.id.w_label, label);
        v.setProgressBar(R.id.w_progress, 100, Math.min(100, Math.round(total * 100f / goal)), false);
        v.setTextViewText(R.id.w_add, "+" + setSize);

        int flags = PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE;
        Intent open = context.getPackageManager().getLaunchIntentForPackage(context.getPackageName());
        if (open != null) {
            v.setOnClickPendingIntent(R.id.w_root, PendingIntent.getActivity(context, 0, open, flags));
        }
        Intent add = new Intent(context, TrainingWidget.class).setAction(ACTION_ADD);
        v.setOnClickPendingIntent(R.id.w_add, PendingIntent.getBroadcast(context, 1, add, flags));
        return v;
    }
}
