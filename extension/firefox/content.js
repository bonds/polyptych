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

  function pauseYoutube() {
    const video = document.querySelector("video");
    if (video && !video.paused) video.pause();
  }

  function injectButton() {
    const existing = document.querySelector(`.${POLYPTYCH_CLASS}`);
    if (existing) return;

    const rightControls = document.querySelector(".ytp-right-controls");
    if (!rightControls) return;

    const btn = document.createElement("button");
    btn.className = "ytp-button " + POLYPTYCH_CLASS;
    btn.title = "Play on all monitors with polyptych";
    btn.innerHTML = `
      <svg width="20" height="20" viewBox="0 0 20 20" fill="none">
        <rect x="1" y="3" width="6" height="14" rx="1" fill="currentColor"/>
        <rect x="7" y="1" width="6" height="18" rx="1" fill="currentColor"/>
        <rect x="13" y="3" width="6" height="14" rx="1" fill="currentColor"/>
      </svg>`;

    btn.addEventListener("click", () => {
      const url = getVideoUrl();
      if (!url) return;

      pauseYoutube();
      btn.disabled = true;
      btn.title = "Downloading… (0%)";

      chrome.runtime.sendMessage({ type: "play", url }, (resp) => {
        if (chrome.runtime.lastError || (resp && resp.error)) {
          btn.title = "Error starting polyptych";
          setTimeout(() => { btn.disabled = false; btn.title = "Play on all monitors with polyptych"; }, 5000);
          return;
        }
        // Progress: update tooltip as time passes
        const phases = [
          [5,  "Downloading… (25%)"],
          [15, "Downloading… (50%)"],
          [25, "Downloading… (75%)"],
          [35, "Starting playback…"],
          [45, "Playing on all monitors"],
        ];
        phases.forEach(([delay, text], i) => {
          setTimeout(() => {
            btn.title = text;
            if (i === phases.length - 1) {
              setTimeout(() => { btn.disabled = false; btn.title = "Play on all monitors with polyptych"; }, 5000);
            }
          }, delay * 1000);
        });
      });
    });

    rightControls.prepend(btn);
  }

  injectButton();
  new MutationObserver(() => injectButton()).observe(document.body, { childList: true, subtree: true });
})();
