let port = null;

function getPort() {
  if (port) return port;
  try {
    port = chrome.runtime.connectNative("com.polyptych.youtube");
    port.onDisconnect.addListener(() => {
      port = null;
    });
  } catch (e) {
    port = null;
  }
  return port;
}

chrome.runtime.onMessage.addListener((msg, sender, sendResponse) => {
  if (msg.type === "play") {
    const p = getPort();
    if (!p) {
      sendResponse({ error: "native host not found" });
      return;
    }
    p.postMessage({ url: msg.url });
    sendResponse({ ok: true });
  }
});
