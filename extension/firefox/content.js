(() => {
  const POLYPTYCH_CLASS = "polyptych-button";

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

  function injectButton() {
    const existing = document.querySelector(`.${POLYPTYCH_CLASS}`);
    if (existing) return;

    const rightControls = document.querySelector(".ytp-right-controls");
    if (!rightControls) return;

    const btn = document.createElement("button");
    btn.className =
      "ytp-button " + POLYPTYCH_CLASS;
    btn.title = "Play on all monitors with polyptych";
    btn.innerHTML = `
      <svg width="20" height="20" viewBox="0 0 20 20" fill="none">
        <rect x="1" y="3" width="6" height="14" rx="1" fill="currentColor"/>
        <rect x="7" y="1" width="6" height="18" rx="1" fill="currentColor"/>
        <rect x="13" y="3" width="6" height="14" rx="1" fill="currentColor"/>
      </svg>`;

    btn.addEventListener("click", () => {
      const url = getVideoUrl();
      if (url) {
        btn.disabled = true;
        btn.title = "Launching polyptych…";
        chrome.runtime.sendMessage({ type: "play", url }, (resp) => {
          if (chrome.runtime.lastError) {
            btn.title = "Error: " + chrome.runtime.lastError.message;
            setTimeout(() => { btn.disabled = false; btn.title = "Play on all monitors with polyptych"; }, 5000);
            return;
          }
          if (resp && resp.error) {
            btn.title = "Error: " + resp.error;
            setTimeout(() => { btn.disabled = false; btn.title = "Play on all monitors with polyptych"; }, 5000);
            return;
          }
          setTimeout(() => { btn.disabled = false; btn.title = "Play on all monitors with polyptych"; }, 3000);
        });
      }
    });

    rightControls.prepend(btn);
  }

  // YouTube is an SPA — re-inject on navigation
  injectButton();
  new MutationObserver(() => injectButton()).observe(document.body, { childList: true, subtree: true });
})();
