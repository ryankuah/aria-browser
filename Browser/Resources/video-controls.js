// ==UserScript==
// @name         Video Controls
// @enabled      true
// @match        <all_urls>
// @run-at       document-end
// @frames       all
// @sidebar-icon speedometer
// @sidebar-label Video Controls
// ==/UserScript==

(() => {
  if (window.__browserVideoControlsInstalled) return;
  window.__browserVideoControlsInstalled = true;

  const MIN_RATE = 0.25;
  const MAX_RATE = 16;
  const RATE_STEP = 0.25;
  const SEEK_SECONDS = 10;

  let desiredRate = null;
  let hideMessageTimer = null;
  let positionFrame = null;

  // -------------------------------------------------------------------------
  // Video selection
  // -------------------------------------------------------------------------

  const getVideos = () =>
    [...document.querySelectorAll("video")].filter(
      video => video instanceof HTMLVideoElement
    );

  const visibleArea = video => {
    const rect = video.getBoundingClientRect();
    const width = Math.max(
      0,
      Math.min(rect.right, innerWidth) - Math.max(rect.left, 0)
    );
    const height = Math.max(
      0,
      Math.min(rect.bottom, innerHeight) - Math.max(rect.top, 0)
    );
    return width * height;
  };

  const bestVideo = () => {
    const fullscreenElement = document.fullscreenElement;

    return (
      getVideos()
        .map(video => {
          let score = visibleArea(video);

          if (!video.paused && !video.ended) score += 1_000_000_000;
          if (video.currentTime > 0 && !video.ended) score += 1_000_000;
          if (
            fullscreenElement &&
            (fullscreenElement === video || fullscreenElement.contains(video))
          ) {
            score += 10_000_000_000;
          }

          return { video, score };
        })
        .sort((a, b) => b.score - a.score)[0]?.video ?? null
    );
  };

  // -------------------------------------------------------------------------
  // On-video indicator
  // -------------------------------------------------------------------------

  const hudHost = document.createElement("div");
  const shadow = hudHost.attachShadow({ mode: "closed" });

  Object.assign(hudHost.style, {
    all: "initial",
    position: "fixed",
    left: "50%",
    top: "12px",
    zIndex: "2147483647",
    pointerEvents: "none",
    transform: "translateX(-50%)"
  });

  const hud = document.createElement("div");
  const speedLabel = document.createElement("span");
  const messageLabel = document.createElement("span");

  Object.assign(hud.style, {
    display: "flex",
    alignItems: "center",
    gap: "8px",
    padding: "8px 12px",
    borderRadius: "10px",
    background: "rgba(15, 15, 18, 0.88)",
    color: "#fff",
    font: "600 13px/1.2 -apple-system, BlinkMacSystemFont, sans-serif",
    boxShadow: "0 4px 18px rgba(0, 0, 0, 0.3)",
    backdropFilter: "blur(12px)",
    opacity: "0",
    transform: "translateY(-6px)",
    transition: "opacity 150ms ease, transform 150ms ease",
    whiteSpace: "nowrap"
  });

  Object.assign(messageLabel.style, {
    color: "rgba(255, 255, 255, 0.7)",
    fontWeight: "500"
  });

  hud.append(speedLabel, messageLabel);
  shadow.append(hud);

  const mountHud = () => {
    if (!hudHost.isConnected && document.documentElement) {
      document.documentElement.appendChild(hudHost);
    }
  };

  const formatRate = rate => `${Number(rate.toFixed(2)).toString()}×`;

  const positionHud = video => {
    if (!(video instanceof HTMLVideoElement)) return false;

    const rect = video.getBoundingClientRect();
    const intersectsViewport =
      rect.width > 0 &&
      rect.height > 0 &&
      rect.right > 0 &&
      rect.bottom > 0 &&
      rect.left < innerWidth &&
      rect.top < innerHeight;
    if (!intersectsViewport) return false;

    const visibleLeft = Math.max(0, rect.left);
    const visibleRight = Math.min(innerWidth, rect.right);
    const centerX = visibleLeft < visibleRight
      ? (visibleLeft + visibleRight) / 2
      : rect.left + rect.width / 2;
    const visibleTop = Math.max(0, rect.top);
    const top = Math.min(innerHeight - 44, visibleTop + 12);

    hudHost.style.left = `${Math.max(44, Math.min(innerWidth - 44, centerX))}px`;
    hudHost.style.top = `${Math.max(8, top)}px`;
    return true;
  };

  const scheduleHudPosition = () => {
    if (positionFrame !== null) return;
    positionFrame = requestAnimationFrame(() => {
      positionFrame = null;
      if (!positionHud(bestVideo())) {
        hud.style.opacity = "0";
      }
    });
  };

  const showHud = (message = "", temporary = false) => {
    const video = bestVideo();
    if (!video) return;

    mountHud();
    if (!positionHud(video)) {
      hud.style.opacity = "0";
      return;
    }

    const rate = desiredRate ?? video.playbackRate ?? 1;
    speedLabel.textContent = formatRate(rate);
    messageLabel.textContent = message;
    hud.style.opacity = "1";
    hud.style.transform = "translateY(0)";

    clearTimeout(hideMessageTimer);
    if (temporary) {
      hideMessageTimer = setTimeout(() => {
        messageLabel.textContent = "";
      }, 1200);
    }
  };

  // -------------------------------------------------------------------------
  // Playback speed and seeking
  // -------------------------------------------------------------------------

  const clampRate = rate => {
    const numericRate = Number(rate);
    const validRate = Number.isFinite(numericRate) ? numericRate : 1;
    return (
      Math.round(
        Math.min(MAX_RATE, Math.max(MIN_RATE, validRate)) * 100
      ) / 100
    );
  };

  const applyRate = video => {
    if (desiredRate === null) return;

    try {
      video.defaultPlaybackRate = desiredRate;
      video.playbackRate = desiredRate;
    } catch {
      // Some protected players may reject playback-rate changes.
    }
  };

  const setRate = rate => {
    const videos = getVideos();
    if (videos.length === 0) return false;

    desiredRate = clampRate(rate);
    videos.forEach(applyRate);
    showHud("Playback speed", true);
    return true;
  };

  const adjustRate = delta => {
    const video = bestVideo();
    if (!video) return false;

    const currentRate =
      desiredRate ??
      (Number.isFinite(video.playbackRate) ? video.playbackRate : 1);
    return setRate(currentRate + delta);
  };

  const seek = seconds => {
    const video = bestVideo();
    if (!video) return false;

    const currentTime = Number.isFinite(video.currentTime)
      ? video.currentTime
      : 0;
    const duration = Number.isFinite(video.duration)
      ? video.duration
      : Infinity;
    const newTime = Math.min(duration, Math.max(0, currentTime + seconds));

    try {
      video.currentTime = newTime;
      showHud(
        seconds < 0
          ? `−${Math.abs(seconds)} seconds`
          : `+${seconds} seconds`,
        true
      );
      return true;
    } catch {
      return false;
    }
  };

  // -------------------------------------------------------------------------
  // Keyboard controls
  // -------------------------------------------------------------------------

  const isEditable = target => {
    if (!(target instanceof Element)) return false;

    if (
      target.closest(
        [
          "textarea",
          "select",
          "[contenteditable='']",
          "[contenteditable='true']",
          "[contenteditable='plaintext-only']",
          "[role='textbox']"
        ].join(",")
      )
    ) {
      return true;
    }

    const input = target.closest("input");
    return (
      input instanceof HTMLInputElement &&
      ![
        "button",
        "checkbox",
        "color",
        "file",
        "hidden",
        "image",
        "radio",
        "range",
        "reset",
        "submit"
      ].includes(input.type.toLowerCase())
    );
  };

  document.addEventListener(
    "keydown",
    event => {
      if (
        event.defaultPrevented ||
        event.repeat ||
        event.isComposing ||
        event.metaKey ||
        event.altKey ||
        event.ctrlKey ||
        event.shiftKey ||
        isEditable(event.target)
      ) {
        return;
      }

      const key = String(event.key || "").toLowerCase();
      const handled =
        key === "g"
          ? setRate(3)
          : key === "h"
            ? setRate(1)
            : key === "d"
              ? adjustRate(RATE_STEP)
              : key === "s"
                ? adjustRate(-RATE_STEP)
                : key === "z"
                  ? seek(-SEEK_SECONDS)
                  : key === "x"
                    ? seek(SEEK_SECONDS)
                    : false;

      if (!handled) return;

      event.preventDefault();
      event.stopPropagation();
      event.stopImmediatePropagation();
    },
    true
  );

  // -------------------------------------------------------------------------
  // Dynamically added videos
  // -------------------------------------------------------------------------

  const resizeObserver = new ResizeObserver(scheduleHudPosition);

  const initializeVideo = video => {
    if (!(video instanceof HTMLVideoElement)) return;
    if (video.dataset.browserVideoControlsInitialized === "true") return;

    video.dataset.browserVideoControlsInitialized = "true";
    resizeObserver.observe(video);

    video.addEventListener("play", () => {
      applyRate(video);
      showHud();
    });
    video.addEventListener("loadedmetadata", () => {
      applyRate(video);
      showHud();
    });
    video.addEventListener("ratechange", () => {
      if (
        desiredRate !== null &&
        Math.abs(video.playbackRate - desiredRate) > 0.001
      ) {
        applyRate(video);
      }
      showHud();
    });

    applyRate(video);
    showHud();
  };

  const discoverVideos = root => {
    if (root instanceof HTMLVideoElement) initializeVideo(root);
    if (root instanceof Element || root instanceof Document) {
      root.querySelectorAll("video").forEach(initializeVideo);
    }
  };

  discoverVideos(document);

  new MutationObserver(mutations => {
    for (const mutation of mutations) {
      mutation.addedNodes.forEach(node => discoverVideos(node));
    }
  }).observe(document.documentElement, {
    childList: true,
    subtree: true
  });

  addEventListener("resize", scheduleHudPosition);
  addEventListener("scroll", scheduleHudPosition, true);
  document.addEventListener("fullscreenchange", scheduleHudPosition);

  if (typeof browserUserScript !== "undefined") {
    browserUserScript.onSidebarAction(() => {
      showHud("G/H speed · D/S adjust · Z/X seek", true);
    });
  }
})();
