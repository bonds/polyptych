let port = null;

function connect() {
  try {
    port = chrome.runtime.connectNative("com.polyptych.youtube");
    port.onMessage.addListener((msg) => {
      // Forward status updates from native host to content scripts
      if (msg && msg.status) {
        chrome.runtime.sendMessage({ type: "status", status: msg.status }).catch(() => {});
      }
    });
    port.onDisconnect.addListener(() => {
      console.log("polyptych: disconnected");
      port = null;
    });
  } catch (e) {
    console.error("polyptych: connect failed:", e);
    port = null;
  }
}

chrome.runtime.onMessage.addListener((msg, sender, sendResponse) => {
  if (msg.type === "play") {
    if (!port) connect();
    if (!port) {
      sendResponse({ error: "native host not found" });
      return;
    }
    try {
      port.postMessage({ url: msg.url });
      sendResponse({ ok: true });
    } catch (e) {
      sendResponse({ error: String(e) });
    }
  }
});
