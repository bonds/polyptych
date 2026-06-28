(() => {
  const BAR_ID = "polyptych-progress-bar";
  const TOAST_ID = "polyptych-toast";

  function getVideoUrl() {
    const url = new URL(location.href);
    if (url.pathname === "/watch") {
      const v = url.searchParams.get("v");
      if (v) return `https://www.youtube.com/watch?v=${v}`;
    }
    if (url.pathname.startsWith("/shorts/")) {
      const id = url.pathname.split("/")[2];
      if (id) return `https://www.youtube.com/watch?v=${id}`;
    }
    return null;
  }

  function pauseYoutube() {
    const video = document.querySelector("video");
    if (video && !video.paused) video.pause();
  }

  function launchPolyptych() {
    const url = getVideoUrl();
    if (!url) return;

    pauseYoutube();
    showToast("Sending to polyptych…");
    setBar("requesting", 10);

    chrome.runtime.sendMessage({ type: "play", url }, (resp) => {
      if (chrome.runtime.lastError || (resp && resp.error)) {
        showToast("Error starting polyptych", 3000);
        setBar("error", 0);
        setTimeout(() => hideBar(), 2000);
        return;
      }
    });
  }

  // ---- Progress bar ----

  function getBar() {
    let el = document.getElementById(BAR_ID);
    if (!el) {
      el = document.createElement("div");
      el.id = BAR_ID;
      el.style.cssText = `
        position: fixed; top: 0; left: 0; z-index: 999999;
        height: 5px; width: 0%; transition: width 0.3s ease;
        box-shadow: 0 0 8px rgba(239,68,68,0.6);
      `;
      document.body.appendChild(el);
    }
    return el;
  }

  function setBar(state, pct) {
    const el = getBar();
    el.style.width = Math.max(0, Math.min(100, pct)) + "%";
    const colors = {
      requesting: "#fbbf24",
      downloading: "#ef4444",
      playing: "#22c55e",
      error: "#7f1d1d",
      idle: "transparent",
    };
    el.style.background = colors[state] || "#ef4444";
    el.style.opacity = pct >= 100 ? "0" : "1";
  }

  function hideBar() {
    const el = document.getElementById(BAR_ID);
    if (el) el.style.width = "0%";
  }

  // ---- Toast ----

  function getToast() {
    let el = document.getElementById(TOAST_ID);
    if (!el) {
      el = document.createElement("div");
      el.id = TOAST_ID;
      el.style.cssText = `
        position: fixed; top: 16px; left: 50%; transform: translateX(-50%);
        z-index: 999999; padding: 12px 24px; border-radius: 8px;
        background: #1a1a2e; color: #fff; font: 600 15px/1.4 sans-serif;
        box-shadow: 0 4px 20px rgba(0,0,0,0.5);
        border: 1px solid rgba(255,255,255,0.12);
        pointer-events: none; transition: opacity 0.2s ease;
        opacity: 0;
      `;
      document.body.appendChild(el);
    }
    return el;
  }

  function showToast(msg, duration = 0) {
    const el = getToast();
    el.textContent = "polyptych: " + msg;
    el.style.opacity = "1";
    if (duration > 0) {
      clearTimeout(el._hideTimer);
      el._hideTimer = setTimeout(() => { el.style.opacity = "0"; }, duration);
    }
  }

  // ---- Hook fullscreen button ----

  let hooked = false;

  function setupHooks() {
    if (hooked) return;
    // Intercept fullscreen button (capture phase to fire before YouTube's handler)
    const fsBtn = document.querySelector(".ytp-fullscreen-button");
    if (!fsBtn) return;

    fsBtn.addEventListener("click", (e) => {
      if (e.ctrlKey || e.metaKey) return; // allow Cmd+click for real fullscreen
      e.preventDefault();
      e.stopPropagation();
      launchPolyptych();
    }, true);

    // Intercept F key (YouTube uses it for fullscreen)
    document.addEventListener("keydown", (e) => {
      if (e.key === "f" && !e.ctrlKey && !e.metaKey && !e.altKey) {
        const active = document.activeElement;
        if (active && (active.tagName === "INPUT" || active.tagName === "TEXTAREA")) return;
        e.preventDefault();
        e.stopPropagation();
        launchPolyptych();
      }
    }, true);

    // Listen for status updates from background
    chrome.runtime.onMessage.addListener((msg) => {
      if (msg.type === "status") {
        const parts = (msg.status || "").split("|");
        const state = parts[0] || "";
        const pct = parseInt(parts[1], 10) || 0;
        const text = parts[2] || "";
        if (state === "playing") {
          setBar("playing", 100);
          showToast(text || "Playing on all monitors", 4000);
          setTimeout(() => hideBar(), 3000);
        } else if (state === "error") {
          setBar("error", 0);
          showToast(text || "Error", 3000);
          setTimeout(() => hideBar(), 2000);
        } else if (state === "downloading") {
          setBar("downloading", pct);
          showToast(text || `Downloading… ${pct}%`, 0);
        } else if (state === "requesting") {
          setBar("requesting", 10);
          showToast(text || "Requesting…", 0);
        }
      }
    });

    hooked = true;
  }

  setupHooks();
  new MutationObserver(() => setupHooks()).observe(document.body, { childList: true, subtree: true });
})();
