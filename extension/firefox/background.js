let port = null;
let statusTimer = null;

function connect() {
  try {
    port = chrome.runtime.connectNative("com.polyptych.youtube");
    port.onMessage.addListener((msg) => {
      console.log("polyptych: host message:", msg);
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

function broadcastStatus() {
  fetch("file:///tmp/polyptych-yt-status")
    .then(r => r.text())
    .then(text => {
      const status = text.trim();
      if (!status) return;
      // Forward to all content scripts
      chrome.runtime.sendMessage({ type: "status", status }).catch(() => {});
    })
    .catch(() => {});
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
      if (statusTimer) clearInterval(statusTimer);
      broadcastStatus();
      statusTimer = setInterval(broadcastStatus, 1500);
    } catch (e) {
      sendResponse({ error: String(e) });
    }
  }
});
