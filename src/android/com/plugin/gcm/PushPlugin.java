package com.plugin.gcm;

import java.io.IOException;
import java.util.Iterator;

import org.apache.cordova.CallbackContext;
import org.apache.cordova.CordovaInterface;
import org.apache.cordova.CordovaPlugin;
import org.apache.cordova.CordovaWebView;
import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import android.app.NotificationManager;
import android.content.Context;
import android.os.AsyncTask;
import android.os.Bundle;
import android.util.Log;

import com.google.android.gms.gcm.GoogleCloudMessaging;

/**
 * @author awysocki
 */

public class PushPlugin extends CordovaPlugin {
  public static final String TAG = "PushPlugin";

  public static final String REGISTER = "register";
  public static final String UNREGISTER = "unregister";
  public static final String EXIT = "exit";

  private static CordovaWebView gWebView;
  private static CordovaInterface gCordovaInterface;
  private static String gECB;
  private static String gSenderID;
  private static Bundle gCachedExtras = null;
  private static boolean gForeground = false;

  /**
   * Gets the application context from cordova's main activity.
   * 
   * @return the application context
   */
  private Context getApplicationContext() {
    return this.cordova.getActivity().getApplicationContext();
  }

  @Override
  public boolean execute(String action, JSONArray data, CallbackContext callbackContext) throws JSONException {

    boolean result = true;

    Log.v(TAG, "execute: action=" + action);

    if (REGISTER.equals(action)) {
      Log.v(TAG, "execute: data=" + data.toString());
      JSONObject jo = data.getJSONObject(0);
      executeRegister(jo, callbackContext);

    } else if (UNREGISTER.equals(action)) {
      executeUnregister(callbackContext);

    } else {
      result = false;
      Log.e(TAG, "Invalid action : " + action);
      callbackContext.error("Invalid action : " + action);
    }

    return result;
  }

  private void executeRegister(JSONObject jo, final CallbackContext callbackContext) throws JSONException {
    gWebView = this.webView;
    gCordovaInterface = this.cordova;
    gECB = (String) jo.get("ecb");
    gSenderID = (String) jo.get("senderID");

    // If javascript is sending regId, it's not needed to register again, it was already registered
    if (!jo.has("regId")) {
      new AsyncTask<Object, Object, Boolean>() {
        String result = "";

        @Override
        protected Boolean doInBackground(Object... arg0) {
          Boolean success = false;

          try {
            result = GoogleCloudMessaging.getInstance(getApplicationContext()).register(gSenderID);
            success = true;

          } catch (IOException ex) {
            Log.e(TAG, "onRegistered: IO exception");
            result = ex.getMessage();
          }

          return success;
        }

        protected void onPostExecute(Boolean success) {
          JSONObject json;
          if (success) {
            try {
              json = new JSONObject().put("event", "registered");
              json.put("regid", result);
              // Send this JSON data to the JavaScript application above EVENT should be set to the msg type
              // In this case this is the registration ID

              PushPlugin.sendJavascript(json);
              callbackContext.success();

            } catch (JSONException ex) {
              // No message to the user is sent, JSON failed
              Log.e(TAG, "onRegistered: JSON exception");
              callbackContext.error(ex.getMessage());
            }
          } else {
            callbackContext.error(result);
          }

        }

      }.execute(null, null, null);
    }

    if (gCachedExtras != null) {
      Log.v(TAG, "sending cached extras");
      sendExtras(gCachedExtras);
      gCachedExtras = null;
    }

  }

  private void executeUnregister(CallbackContext callbackContext) {
    try {
      GoogleCloudMessaging.getInstance(getApplicationContext()).unregister();
      callbackContext.success();

    } catch (IOException ex) {
      callbackContext.error(ex.getMessage());
    }
  }

  /*
   * Sends a json object to the client as parameter to a method which is defined in gECB.
   */
  public static void sendJavascript(JSONObject _json) {
    final String _d = "javascript:" + gECB + "(" + _json.toString() + ")";
    Log.v(TAG, "sendJavascript: " + _d);

    if (gECB != null && gWebView != null && gCordovaInterface != null) {
      gCordovaInterface.getActivity().runOnUiThread(new Runnable() {
        @Override
        public void run() {
          gWebView.loadUrl(_d);
        }
      });
    }
  }

  /*
   * Sends the pushbundle extras to the client application.
   * If the client application isn't currently active, it is cached for later processing.
   */
  public static void sendExtras(final Bundle extras) {
    if (extras != null) {
      if (gECB != null && gWebView != null && gCordovaInterface != null) {
        sendJavascript(convertBundleToJson(extras));

      } else {
        Log.v(TAG, "sendExtras: caching extras to send at a later time.");
        gCachedExtras = extras;
      }
    }
  }

  @Override
  public void initialize(CordovaInterface cordova, CordovaWebView webView) {
    super.initialize(cordova, webView);
    gForeground = true;
  }

  @Override
  public void onPause(boolean multitasking) {
    super.onPause(multitasking);
    gForeground = false;
    final NotificationManager notificationManager = (NotificationManager) cordova.getActivity().getSystemService(Context.NOTIFICATION_SERVICE);
    notificationManager.cancelAll();
  }

  @Override
  public void onResume(boolean multitasking) {
    super.onResume(multitasking);
    gForeground = true;
  }

  @Override
  public void onDestroy() {
    super.onDestroy();
    gForeground = false;
    gECB = null;
    gWebView = null;
    gCordovaInterface = null;
  }

  /*
   * serializes a bundle to JSON.
   */
  private static JSONObject convertBundleToJson(Bundle extras) {
    try {
      JSONObject json;
      json = new JSONObject().put("event", "message");

      JSONObject jsondata = new JSONObject();
      Iterator<String> it = extras.keySet().iterator();
      while (it.hasNext()) {
        String key = it.next();
        Object value = extras.get(key);

        // System data from Android
        if (key.equals("from") || key.equals("collapse_key")) {
          json.put(key, value);
        } else if (key.equals("foreground")) {
          json.put(key, extras.getBoolean("foreground"));
        } else if (key.equals("coldstart")) {
          json.put(key, extras.getBoolean("coldstart"));
        } else {
          // Maintain backwards compatibility
          if (key.equals("message") || key.equals("msgcnt") || key.equals("soundname")) {
            json.put(key, value);
          }

          if (value instanceof String) {
            // Try to figure out if the value is another JSON object

            String strValue = (String) value;
            if (strValue.startsWith("{")) {
              try {
                JSONObject json2 = new JSONObject(strValue);
                jsondata.put(key, json2);
              } catch (Exception e) {
                jsondata.put(key, value);
              }
              // Try to figure out if the value is another JSON array
            } else if (strValue.startsWith("[")) {
              try {
                JSONArray json2 = new JSONArray(strValue);
                jsondata.put(key, json2);
              } catch (Exception e) {
                jsondata.put(key, value);
              }
            } else {
              jsondata.put(key, value);
            }
          }
        }
      } // while
      json.put("payload", jsondata);

      Log.v(TAG, "extrasToJSON: " + json.toString());

      return json;
    } catch (JSONException e) {
      Log.e(TAG, "extrasToJSON: JSON exception");
    }
    return null;
  }

  public static boolean isInForeground() {
    return gForeground;
  }

  public static boolean isActive() {
    return gWebView != null;
  }
}
