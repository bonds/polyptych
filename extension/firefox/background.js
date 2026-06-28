let port = null;

function connect() {
  try {
    console.log("polyptych: connecting native host...");
    port = chrome.runtime.connectNative("com.polyptych.youtube");
    port.onMessage.addListener((msg) => {
      console.log("polyptych: native msg:", JSON.stringify(msg));
      if (msg && msg.status) {
        chrome.runtime.sendMessage({ type: "status", status: msg.status }).catch(() => {});
      }
    });
    port.onDisconnect.addListener(() => {
      console.log("polyptych: disconnected, error:", chrome.runtime.lastError?.message);
      port = null;
    });
  } catch (e) {
    console.error("polyptych: connect failed:", e);
    port = null;
  }
}

chrome.runtime.onMessage.addListener((msg, sender, sendResponse) => {
  console.log("polyptych: got message from content:", JSON.stringify(msg));
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
