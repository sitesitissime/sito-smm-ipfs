(() => {
  const socialProfiles = [
    "02-scarlet", "03-archivum", "04-lunare", "05-yellow-dot",
    "06-verde-dreams", "07-aqua-studio", "08-nova-objects", "09-still-works",
    "10-chrome", "11-geometrik", "12-lumen-interiors", "13-coral-table",
    "14-pulse-motel", "15-blue-hour-run", "16-lumen-bread", "17-cinder-bloom",
    "18-after-rain", "19-night-index", "20-prism-forge", "21-civic-clay",
    "22-ruby-room", "23-nocturne-ink", "24-wild-petal", "25-soft-signal",
  ];

  const socialNames = [
    "Scarlet Editorial", "Archivum Works", "Lunare Studio", "Yellow Dot",
    "Verde Dreams", "Aqua Studio", "Nova Objects", "Still Works",
    "Chrome Collective", "Geometrik", "Lumen Interiors", "Coral Table",
    "Pulse Motel", "Blue Hour Run", "Lumen Bread", "Cinder Bloom",
    "After Rain", "Night Index", "Prism Forge", "Civic Clay",
    "Ruby Room", "Nocturne Ink", "Wild Petal", "Soft Signal",
  ];

  const profileUrl = (slug) =>
    new URL(`../../social-portfolio-uniform/${slug}.webp`, window.location.href).href;

  function mountSocialRotation() {
    const frame = document.querySelector(".portfolio-showcase-frame");
    if (!frame || frame.dataset.workRotation === "true") return Boolean(frame);

    frame.dataset.workRotation = "true";
    const rotation = document.createElement("div");
    rotation.className = "work-social-rotation";

    const current = document.createElement("img");
    current.className = "work-social-current";
    current.alt = "Portfolio Social Media";

    const next = document.createElement("img");
    next.className = "work-social-next";
    next.alt = "";
    next.setAttribute("aria-hidden", "true");

    rotation.append(current, next);
    frame.append(rotation);

    socialProfiles.forEach((slug) => {
      const image = new Image();
      image.src = profileUrl(slug);
    });

    let index = 0;
    let stopped = false;
    current.src = profileUrl(socialProfiles[index]);

    const updateLabel = () => {
      frame.closest("figure")?.setAttribute(
        "aria-label",
        `Portfolio Social Media: ${socialNames[index]}`,
      );
    };

    const cycle = () => {
      if (stopped || !document.documentElement.contains(frame)) return;
      const nextIndex = (index + 1) % socialProfiles.length;
      next.src = profileUrl(socialProfiles[nextIndex]);
      next.classList.remove("is-entering");
      void next.offsetWidth;
      next.classList.add("is-entering");

      window.setTimeout(() => {
        index = nextIndex;
        current.src = next.src;
        next.classList.remove("is-entering");
        updateLabel();
        window.setTimeout(cycle, 100);
      }, 650);
    };

    updateLabel();
    window.setTimeout(cycle, 100);
    window.addEventListener("pagehide", () => {
      stopped = true;
    }, { once: true });
    return true;
  }

  function syncPortfolioSlices() {
    const rotation = document.querySelector(".portfolio-rotation");
    if (!rotation) return false;

    const activeImage = rotation.querySelector(".portfolio-rotation-slide img");
    const isFirst = activeImage?.getAttribute("src")?.includes("desktop-01.png");
    const existing = rotation.querySelector(".portfolio-slices");

    if (!isFirst) {
      existing?.remove();
      return true;
    }
    if (existing) return true;

    const slices = document.createElement("div");
    slices.className = "portfolio-slices";
    slices.setAttribute("aria-hidden", "true");
    for (let index = 0; index < 5; index += 1) {
      slices.append(document.createElement("span"));
    }
    rotation.append(slices);
    return true;
  }

  function start() {
    if (window.location.pathname.includes("/servizi/social-media")) {
      if (!mountSocialRotation()) window.setTimeout(start, 50);
      return;
    }

    if (window.location.pathname.includes("/servizi/portfolio")) {
      if (!syncPortfolioSlices()) {
        window.setTimeout(start, 50);
        return;
      }
      const rotation = document.querySelector(".portfolio-rotation");
      new MutationObserver(syncPortfolioSlices).observe(rotation, {
        childList: true,
        subtree: true,
      });
    }
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", start, { once: true });
  } else {
    start();
  }
})();
