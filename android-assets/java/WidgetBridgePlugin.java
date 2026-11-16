package nl.keesvschriek.trainingsapp;

import com.getcapacitor.JSObject;
import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.CapacitorPlugin;

@CapacitorPlugin(name = "WidgetBridge")
public class WidgetBridgePlugin extends Plugin {

    /** De app stuurt nieuwe gegevens voor de widget. */
    @PluginMethod
    public void update(PluginCall call) {
        String json = call.getString("snapshot", "{}");
        WidgetStore.setSnapshot(getContext(), json);
        TrainingWidget.refreshAll(getContext());
        call.resolve();
    }

    /** De app haalt de sets op die via de widget zijn getikt. */
    @PluginMethod
    public void takePending(PluginCall call) {
        JSObject ret = new JSObject();
        ret.put("sets", WidgetStore.takePending(getContext()).toString());
        call.resolve(ret);
    }

    /** Wat er via Delen naar K is gestuurd (leeg als er niets is). */
    @PluginMethod
    public void takeShared(PluginCall call) {
        String[] v = WidgetStore.takeShared(getContext());
        JSObject ret = new JSObject();
        ret.put("text", v[0]);
        ret.put("subject", v[1]);
        call.resolve(ret);
    }
}
