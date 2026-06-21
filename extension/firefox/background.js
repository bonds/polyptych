let port = null;

function connect() {
  try {
    console.log("polyptych: connecting to native host...");
    port = chrome.runtime.connectNative("com.polyptych.youtube");
    port.onMessage.addListener((msg) => {
      console.log("polyptych: received message from host:", msg);
    });
    port.onDisconnect.addListener(() => {
      const err = chrome.runtime.lastError;
      console.log("polyptych: disconnected", err ? err.message : "");
      port = null;
    });
    console.log("polyptych: connected");
  } catch (e) {
    console.error("polyptych: connectNative threw:", e);
    port = null;
  }
}

chrome.runtime.onMessage.addListener((msg, sender, sendResponse) => {
  if (msg.type === "play") {
    console.log("polyptych: play requested:", msg.url);
    if (!port) connect();
    if (!port) {
      console.error("polyptych: failed to connect to native host");
      sendResponse({ error: "native host not found" });
      return;
    }
    try {
      port.postMessage({ url: msg.url });
      console.log("polyptych: message sent");
      sendResponse({ ok: true });
    } catch (e) {
      console.error("polyptych: postMessage failed:", e);
      sendResponse({ error: String(e) });
    }
  }
});
