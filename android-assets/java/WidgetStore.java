package nl.keesvschriek.trainingsapp;

import android.content.Context;
import android.content.SharedPreferences;
import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

/**
 * Gedeelde opslag tussen app en widget.
 * snapshot: wat de widget toont (training per dag, push-ups per dag, doel, setgrootte), geschreven door de app.
 * pending: sets die via de widget zijn getikt en nog niet in de app staan.
 */
final class WidgetStore {
    private static final String PREFS = "training_widget";
    private static final String SNAPSHOT = "snapshot";
    private static final String PENDING = "pending";

    private WidgetStore() {}

    private static SharedPreferences prefs(Context c) {
        return c.getApplicationContext().getSharedPreferences(PREFS, Context.MODE_PRIVATE);
    }

    /** Totaal van getikte sets van een soort op een dag. */
    static synchronized int pendingTotal(Context c, String type, String date) {
        JSONArray list = pending(c);
        int total = 0;
        for (int i = 0; i < list.length(); i++) {
            JSONObject p = list.optJSONObject(i);
            if (p != null && date.equals(p.optString("date")) && type.equals(p.optString("type", "pushups"))) total += p.optInt("value", 0);
        }
        return total;
    }

    static synchronized void setSnapshot(Context c, String json) {
        prefs(c).edit().putString(SNAPSHOT, json).apply();
    }

    static synchronized JSONObject snapshot(Context c) {
        try {
            return new JSONObject(prefs(c).getString(SNAPSHOT, "{}"));
        } catch (JSONException e) {
            return new JSONObject();
        }
    }

    static synchronized JSONArray pending(Context c) {
        try {
            return new JSONArray(prefs(c).getString(PENDING, "[]"));
        } catch (JSONException e) {
            return new JSONArray();
        }
    }

    static synchronized void addPending(Context c, String type, String date, int value) {
        JSONArray list = pending(c);
        try {
            JSONObject o = new JSONObject();
            o.put("type", type);
            o.put("date", date);
            o.put("value", value);
            o.put("ts", System.currentTimeMillis());
            list.put(o);
        } catch (JSONException ignored) {
            return;
        }
        prefs(c).edit().putString(PENDING, list.toString()).commit();
    }

    /** Geeft de getikte sets terug en maakt de lijst leeg. */
    static synchronized JSONArray takePending(Context c) {
        JSONArray list = pending(c);
        prefs(c).edit().putString(PENDING, "[]").commit();
        return list;
    }
}
