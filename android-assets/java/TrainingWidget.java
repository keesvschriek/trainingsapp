package nl.keesvschriek.trainingsapp;

import android.app.PendingIntent;
import android.appwidget.AppWidgetManager;
import android.appwidget.AppWidgetProvider;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.view.View;
import android.widget.RemoteViews;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.Locale;
import org.json.JSONObject;

/** Widget op het startscherm: training van vandaag en een knop voor push-ups tussendoor. */
public class TrainingWidget extends AppWidgetProvider {
    static final String ACTION_ADD = "nl.keesvschriek.trainingsapp.PUSHUPS_ADD";
    static final String ACTION_ADD_PULL = "nl.keesvschriek.trainingsapp.PULLUPS_ADD";
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
            WidgetStore.addPending(context, "pushups", today(), snap.optInt("setSize", 20));
            refreshAll(context);
        } else if (ACTION_ADD_PULL.equals(intent.getAction())) {
            JSONObject snap = WidgetStore.snapshot(context);
            WidgetStore.addPending(context, "pullups", today(), snap.optInt("pullSet", 3));
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
        int total = (counts != null ? counts.optInt(date, 0) : 0) + WidgetStore.pendingTotal(context, "pushups", date);
        boolean rest = day != null && day.optBoolean("rest", false);

        v.setTextViewText(R.id.w_count, total + " / " + goal);
        String label = total >= goal ? "Push-ups: doel gehaald" : rest ? "Push-ups: rustdag" : "Push-ups vandaag";
        v.setTextViewText(R.id.w_label, label);
        v.setProgressBar(R.id.w_progress, 100, Math.min(100, Math.round(total * 100f / goal)), false);
        v.setTextViewText(R.id.w_add, "+" + setSize);

        // Pull-ups tussendoor: alleen op dagen dat ze in het schema staan
        boolean pull = day != null && day.optBoolean("pull", false);
        v.setViewVisibility(R.id.w_pull_row, pull ? View.VISIBLE : View.GONE);
        if (pull) {
            int pullGoal = Math.max(1, snap.optInt("pullGoal", 15));
            int pullSet = snap.optInt("pullSet", 3);
            JSONObject pc = snap.optJSONObject("pullCounts");
            int pullTotal = (pc != null ? pc.optInt(date, 0) : 0) + WidgetStore.pendingTotal(context, "pullups", date);
            v.setTextViewText(R.id.w_pull_count, pullTotal + " / " + pullGoal);
            v.setTextViewText(R.id.w_pull_label, pullTotal >= pullGoal ? "Pull-ups: doel gehaald" : "Pull-ups vandaag");
            v.setProgressBar(R.id.w_pull_progress, 100, Math.min(100, Math.round(pullTotal * 100f / pullGoal)), false);
            v.setTextViewText(R.id.w_pull_add, "+" + pullSet);
        }

        int flags = PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE;
        Intent open = context.getPackageManager().getLaunchIntentForPackage(context.getPackageName());
        if (open != null) {
            v.setOnClickPendingIntent(R.id.w_root, PendingIntent.getActivity(context, 0, open, flags));
        }
        Intent add = new Intent(context, TrainingWidget.class).setAction(ACTION_ADD);
        v.setOnClickPendingIntent(R.id.w_add, PendingIntent.getBroadcast(context, 1, add, flags));
        Intent addPull = new Intent(context, TrainingWidget.class).setAction(ACTION_ADD_PULL);
        v.setOnClickPendingIntent(R.id.w_pull_add, PendingIntent.getBroadcast(context, 2, addPull, flags));
        return v;
    }
}
