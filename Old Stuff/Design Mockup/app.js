const ASSET_ROOT = "./Mockup Assets/";

const pokemon = [
  { name: "Bulbasaur", number: "#001", type: "Grass", stage: "Base Pokémon", image: "001.png", family: "bulbasaur", glow: "rgba(75, 189, 105, .26)", description: "A strange seed was planted on its back at birth. The plant sprouts and grows with this Pokémon.", height: "0.7 m", weight: "6.9 kg", category: "Seed", ability: "Overgrow", gender: "87.5% ♂ · 12.5% ♀", weakness: ["Fire", "Ice", "Flying", "Psychic"] },
  { name: "Ivysaur", number: "#002", type: "Grass", stage: "Stage 1", image: "002.png", family: "bulbasaur", glow: "rgba(80, 174, 127, .27)", description: "When the bulb on its back grows large, it appears to lose the ability to stand on its hind legs.", height: "1.0 m", weight: "13.0 kg", category: "Seed", ability: "Overgrow", gender: "87.5% ♂ · 12.5% ♀", weakness: ["Fire", "Ice", "Flying", "Psychic"] },
  { name: "Venusaur", number: "#003", type: "Grass", stage: "Stage 2", image: "003.png", family: "bulbasaur", glow: "rgba(202, 83, 130, .25)", description: "Its plant blooms when it is absorbing solar energy. It stays on the move to seek sunlight.", height: "2.0 m", weight: "100.0 kg", category: "Seed", ability: "Overgrow", gender: "87.5% ♂ · 12.5% ♀", weakness: ["Fire", "Ice", "Flying", "Psychic"] },
  { name: "Charmander", number: "#004", type: "Fire", stage: "Base Pokémon", image: "004.png", family: "charmander", glow: "rgba(239, 103, 26, .28)", description: "The flame on its tail shows the strength of its life-force. If it is weak, the flame burns weakly.", height: "0.6 m", weight: "8.5 kg", category: "Lizard", ability: "Blaze", gender: "87.5% ♂ · 12.5% ♀", weakness: ["Water", "Ground", "Rock"] },
  { name: "Charmeleon", number: "#005", type: "Fire", stage: "Stage 1", image: "005.png", family: "charmander", glow: "rgba(218, 70, 49, .28)", description: "It has a barbaric nature. In battle, it whips its fiery tail around and slashes with sharp claws.", height: "1.1 m", weight: "19.0 kg", category: "Flame", ability: "Blaze", gender: "87.5% ♂ · 12.5% ♀", weakness: ["Water", "Ground", "Rock"] },
  { name: "Charizard", number: "#006", type: "Fire", stage: "Stage 2", image: "006.png", family: "charmander", glow: "rgba(239, 103, 26, .3)", description: "It spits fire hot enough to melt boulders and may cause forest fires by blowing flames.", height: "1.7 m", weight: "90.5 kg", category: "Flame", ability: "Blaze", gender: "87.5% ♂ · 12.5% ♀", weakness: ["Water", "Electric", "Rock"] }
];

const cards = [
  { image: "card_160_hires.png", name: "Pikachu — Crown Zenith 160" },
  { image: "card_188_hires.png", name: "Pikachu VMAX — Vivid Voltage 188" },
  { image: "card_49_hires.png", name: "Pikachu — Pokémon GO 049" },
  { image: "card_4_hires.png", name: "Charizard — Base Set 4" }
];

const families = {
  bulbasaur: pokemon.slice(0, 3),
  charmander: pokemon.slice(3, 6)
};

const clamp = (value, min, max) => Math.min(Math.max(value, min), max);

function createDevice(device) {
  const template = document.querySelector("#device-template");
  device.append(template.content.cloneNode(true));

  const shell = device.querySelector(".app-shell");
  const carousel = shell.querySelector(".carousel");
  const launcher = shell.querySelector(".launcher-layer");
  const home = shell.querySelector(".home-layer");
  const pokemonGrid = shell.querySelector(".pokemon-grid");
  const surpriseButton = shell.querySelector(".surprise-button");
  const track = shell.querySelector(".carousel__track");
  const dots = shell.querySelector(".carousel-dots");
  const cardGrid = shell.querySelector(".card-grid");
  const modal = shell.querySelector(".card-modal");
  const modalCard = shell.querySelector(".card-modal__card");
  const modalImage = modal.querySelector("img");
  const reducedMotion = matchMedia("(prefers-reduced-motion: reduce)");

  let index = 0;
  let panel = "home";
  let lastCardTrigger = null;
  let carouselGesture = null;
  let panelGesture = null;
  let wheelLock = false;
  let suppressPanelClick = false;
  let lastPokemonTile = null;

  const visualScale = () => shell.getBoundingClientRect().width / shell.offsetWidth;

  const designWidth = device.dataset.orientation === "landscape"
    ? (device.dataset.device === "tablet" ? 1366 : 844)
    : (device.dataset.device === "tablet" ? 1024 : 390);
  const syncDeviceScale = () => {
    device.style.setProperty("--device-scale", String(device.clientWidth / designWidth));
  };
  const deviceResizeObserver = new ResizeObserver(syncDeviceScale);
  deviceResizeObserver.observe(device);
  syncDeviceScale();

  pokemon.forEach((item, itemIndex) => {
    const gridItem = document.createElement("button");
    gridItem.className = "pokemon-grid-item";
    gridItem.type = "button";
    gridItem.dataset.pokemonIndex = itemIndex;
    gridItem.style.setProperty("--pokemon-accent", item.type === "Fire" ? "#ef671a" : "#79b96b");
    gridItem.setAttribute("aria-label", `Open ${item.name}, Pokédex ${item.number}`);
    gridItem.innerHTML = `
      <img src="${ASSET_ROOT}${item.image}" alt="" draggable="false">
      <span class="pokemon-grid-item__copy"><small>${item.number}</small><strong>${item.name}</strong></span>
      <i aria-hidden="true">→</i>`;
    gridItem.addEventListener("click", () => openPokemon(itemIndex, gridItem));
    pokemonGrid.append(gridItem);

    const slide = document.createElement("div");
    slide.className = "pokemon-slide";
    slide.dataset.index = itemIndex;
    slide.innerHTML = `<img src="${ASSET_ROOT}${item.image}" alt="${item.name}" draggable="false">`;
    track.append(slide);

    const dot = document.createElement("button");
    dot.className = "carousel-dot";
    dot.type = "button";
    dot.setAttribute("aria-label", `Show ${item.name}`);
    dot.addEventListener("click", () => setIndex(itemIndex));
    dots.append(dot);
  });

  cards.forEach((card, cardIndex) => {
    const button = document.createElement("button");
    button.className = "card-button";
    button.type = "button";
    button.style.setProperty("--card-order", cardIndex);
    button.setAttribute("aria-label", `Magnify ${card.name}`);
    button.innerHTML = `<img src="${ASSET_ROOT}${card.image}" alt="${card.name}">`;
    button.addEventListener("click", () => openCard(button, card));
    cardGrid.append(button);
  });

  function setIndex(nextIndex, direction = 0) {
    const boundedIndex = clamp(nextIndex, 0, pokemon.length - 1);
    if (boundedIndex === index && direction !== 0) {
      carousel.classList.add("is-bumping");
      setTimeout(() => carousel.classList.remove("is-bumping"), 220);
    }
    index = boundedIndex;
    const current = pokemon[index];
    shell.dataset.pokemonIndex = index;
    shell.style.setProperty("--pokemon-glow", current.glow);
    shell.style.setProperty("--glow-x", `${38 + index * 5}%`);

    track.querySelectorAll(".pokemon-slide").forEach((slide, slideIndex) => {
      const position = slideIndex - index;
      slide.style.setProperty("--position", position);
      slide.style.removeProperty("--slide-offset");
      slide.style.removeProperty("--drag-scale");
      slide.style.removeProperty("--neighbor-opacity");
      slide.classList.toggle("is-current", position === 0);
      slide.classList.toggle("is-neighbor", Math.abs(position) === 1);
      slide.setAttribute("aria-hidden", position === 0 ? "false" : "true");
    });

    dots.querySelectorAll(".carousel-dot").forEach((dot, dotIndex) => {
      dot.setAttribute("aria-current", dotIndex === index ? "true" : "false");
    });

    shell.querySelector(".pokemon-copy__number").textContent = current.number;
    shell.querySelector(".pokemon-copy h2").textContent = current.name;
    const typeChip = shell.querySelector(".type-chip");
    typeChip.textContent = current.type;
    typeChip.dataset.type = current.type.toLowerCase();
    shell.querySelector(".stage-label").textContent = current.stage;
    shell.querySelector(".pokemon-copy__description").textContent = current.description;
    shell.querySelector('[data-stat="height"]').textContent = current.height;
    shell.querySelector('[data-stat="weight"]').textContent = current.weight;
    shell.querySelector('[data-stat="category"]').textContent = current.category;
    shell.querySelector('[data-stat="ability"]').textContent = current.ability;
    shell.querySelector('[data-stat="gender"]').textContent = current.gender;
    const weakness = shell.querySelector('[data-stat="weakness"]');
    weakness.replaceChildren(...current.weakness.map((item) => {
      const chip = document.createElement("span");
      chip.textContent = item;
      chip.dataset.weakness = item.toLowerCase();
      return chip;
    }));
    renderEvolution();
  }

  function moveIndex(delta) {
    setIndex(index + delta, delta);
  }

  function setView(view, { restoreFocus = false } = {}) {
    shell.dataset.view = view;
    launcher.setAttribute("aria-hidden", view === "launcher" ? "false" : "true");
    home.setAttribute("aria-hidden", view === "detail" ? "false" : "true");
    if (view === "detail") {
      setTimeout(() => carousel.focus({ preventScroll: true }), reducedMotion.matches ? 0 : 420);
    } else if (restoreFocus) {
      setTimeout(() => lastPokemonTile?.focus({ preventScroll: true }), reducedMotion.matches ? 0 : 420);
    }
  }

  function openPokemon(itemIndex, trigger) {
    lastPokemonTile = trigger;
    setIndex(itemIndex);
    setView("detail");
  }

  function shufflePokemonGrid() {
    const items = [...pokemonGrid.children];
    const previousOrder = items.map((item) => item.dataset.pokemonIndex).join(",");
    const firstRects = new Map(items.map((item) => [item, item.getBoundingClientRect()]));

    for (let itemIndex = items.length - 1; itemIndex > 0; itemIndex -= 1) {
      const swapIndex = Math.floor(Math.random() * (itemIndex + 1));
      [items[itemIndex], items[swapIndex]] = [items[swapIndex], items[itemIndex]];
    }
    if (items.map((item) => item.dataset.pokemonIndex).join(",") === previousOrder) {
      items.push(items.shift());
    }
    items.forEach((item) => pokemonGrid.append(item));

    surpriseButton.classList.remove("is-shuffling");
    void surpriseButton.offsetWidth;
    surpriseButton.classList.add("is-shuffling");

    if (!reducedMotion.matches) {
      const scale = visualScale();
      items.forEach((item) => {
        const first = firstRects.get(item);
        const last = item.getBoundingClientRect();
        item.animate([
          { transform: `translate(${(first.left - last.left) / scale}px, ${(first.top - last.top) / scale}px) scale(.97)`, opacity: .72 },
          { transform: "translate(0, 0) scale(1)", opacity: 1 }
        ], { duration: 480, easing: "cubic-bezier(.22,.82,.24,1)" });
      });
    }
    shell.querySelector(".shuffle-status").textContent = "Pokémon order shuffled.";
    setTimeout(() => surpriseButton.classList.remove("is-shuffling"), 480);
  }

  function renderEvolution() {
    const current = pokemon[index];
    const family = families[current.family];
    const chain = shell.querySelector(".evolution-chain");
    shell.querySelector(".evolution-title").textContent = `${family[0].name} family`;
    chain.replaceChildren();

    family.forEach((item, familyIndex) => {
      const globalIndex = pokemon.indexOf(item);
      const node = document.createElement("button");
      node.type = "button";
      node.className = "evolution-node";
      node.style.setProperty("--node-order", familyIndex);
      node.classList.toggle("is-current", globalIndex === index);
      node.setAttribute("aria-label", `View ${item.name}`);
      node.innerHTML = `
        <img src="${ASSET_ROOT}${item.image}" alt="">
        <span><small>${item.stage}</small><strong>${item.name}</strong></span>
        <i aria-hidden="true">→</i>`;
      node.addEventListener("click", () => {
        setIndex(globalIndex);
        closePanel();
      });
      chain.append(node);
    });
  }

  function openPanel(name) {
    panel = name;
    shell.dataset.panel = name;
    shell.querySelectorAll(".panel").forEach((item) => {
      item.setAttribute("aria-hidden", item.classList.contains(`panel--${name}`) ? "false" : "true");
      item.style.removeProperty("--panel-drag");
    });
    const focusTarget = shell.querySelector(`.panel--${name} .panel-close`);
    setTimeout(() => focusTarget?.focus({ preventScroll: true }), reducedMotion.matches ? 0 : 430);
  }

  function closePanel({ restoreFocus = true } = {}) {
    const trigger = shell.querySelector(`[data-open-panel="${panel}"]`);
    panel = "home";
    shell.dataset.panel = "home";
    shell.querySelectorAll(".panel").forEach((item) => {
      item.setAttribute("aria-hidden", "true");
      item.style.removeProperty("--panel-drag");
    });
    if (restoreFocus) trigger?.focus({ preventScroll: true });
  }

  function openCard(trigger, card) {
    lastCardTrigger = trigger;
    modalImage.src = `${ASSET_ROOT}${card.image}`;
    modalImage.alt = card.name;
    modal.setAttribute("aria-hidden", "false");
    modal.querySelector(".card-modal__close").focus({ preventScroll: true });
  }

  function closeCard() {
    if (modal.getAttribute("aria-hidden") === "true") return;
    modal.setAttribute("aria-hidden", "true");
    modalCard.style.setProperty("--rx", "0deg");
    modalCard.style.setProperty("--ry", "0deg");
    lastCardTrigger?.focus({ preventScroll: true });
  }

  shell.querySelectorAll("[data-open-panel]").forEach((button) => {
    button.addEventListener("click", (event) => {
      if (suppressPanelClick) {
        event.preventDefault();
        suppressPanelClick = false;
        return;
      }
      openPanel(button.dataset.openPanel);
    });
  });
  shell.querySelector(".nav-back").addEventListener("click", () => {
    closeCard();
    if (panel !== "home") closePanel({ restoreFocus: false });
    setView("launcher", { restoreFocus: true });
  });
  surpriseButton.addEventListener("click", shufflePokemonGrid);
  shell.querySelectorAll("[data-close-panel]").forEach((button) => button.addEventListener("click", closePanel));
  shell.querySelectorAll("[data-close-card]").forEach((button) => button.addEventListener("click", closeCard));
  shell.querySelector(".carousel-arrow--previous").addEventListener("click", () => moveIndex(-1));
  shell.querySelector(".carousel-arrow--next").addEventListener("click", () => moveIndex(1));
  carousel.addEventListener("keydown", (event) => {
    if (event.key === "ArrowLeft") { event.preventDefault(); moveIndex(-1); }
    if (event.key === "ArrowRight") { event.preventDefault(); moveIndex(1); }
  });

  carousel.addEventListener("wheel", (event) => {
    if (Math.abs(event.deltaX) < Math.abs(event.deltaY) || Math.abs(event.deltaX) < 20 || wheelLock) return;
    event.preventDefault();
    wheelLock = true;
    moveIndex(event.deltaX > 0 ? 1 : -1);
    setTimeout(() => { wheelLock = false; }, 480);
  }, { passive: false });

  carousel.addEventListener("pointerdown", (event) => {
    if (event.button !== 0) return;
    carouselGesture = { id: event.pointerId, startX: event.clientX, lastX: event.clientX, startTime: performance.now() };
    carousel.setPointerCapture(event.pointerId);
    carousel.classList.add("is-dragging");
  });

  carousel.addEventListener("pointermove", (event) => {
    if (!carouselGesture || carouselGesture.id !== event.pointerId) return;
    const width = carousel.clientWidth;
    const delta = (event.clientX - carouselGesture.startX) * .82 / visualScale();
    carouselGesture.lastX = event.clientX;
    track.querySelectorAll(".pokemon-slide").forEach((slide, slideIndex) => {
      const position = slideIndex - index;
      slide.style.setProperty("--slide-offset", `${delta}px`);
      if (position === 0) slide.style.setProperty("--drag-scale", String(1 - Math.min(Math.abs(delta) / width, 1) * .06));
      if ((delta < 0 && position === 1) || (delta > 0 && position === -1)) {
        slide.style.setProperty("--neighbor-opacity", String(.45 + Math.min(Math.abs(delta) / width, 1) * .55));
      }
    });
  });

  function finishCarouselGesture(event) {
    if (!carouselGesture || carouselGesture.id !== event.pointerId) return;
    const delta = event.clientX - carouselGesture.startX;
    const elapsed = performance.now() - carouselGesture.startTime;
    const threshold = carousel.getBoundingClientRect().width * .22;
    const isFlick = elapsed < 280 && Math.abs(delta) > 34;
    carousel.releasePointerCapture?.(event.pointerId);
    carousel.classList.remove("is-dragging");
    carouselGesture = null;
    if (Math.abs(delta) > threshold || isFlick) moveIndex(delta < 0 ? 1 : -1);
    else setIndex(index);
  }
  carousel.addEventListener("pointerup", finishCarouselGesture);
  carousel.addEventListener("pointercancel", finishCarouselGesture);

  shell.addEventListener("pointerdown", (event) => {
    const gestureButton = event.target.closest(".gesture-pill");
    if ((event.target.closest("button") && !gestureButton) || event.target.closest(".carousel, .card-modal") || panel !== "home") return;
    panelGesture = {
      id: event.pointerId,
      startY: event.clientY,
      lastY: event.clientY,
      targetPanel: gestureButton?.dataset.openPanel || null,
      panelElement: null
    };
    suppressPanelClick = false;
    shell.setPointerCapture(event.pointerId);
  });
  shell.addEventListener("pointermove", (event) => {
    if (!panelGesture || panelGesture.id !== event.pointerId) return;
    panelGesture.lastY = event.clientY;
    const delta = event.clientY - panelGesture.startY;
    if (!panelGesture.targetPanel && Math.abs(delta) > 6) {
      panelGesture.targetPanel = delta > 0 ? "cards" : "evolution";
    }
    if (!panelGesture.targetPanel) return;

    const directionMatches = panelGesture.targetPanel === "cards" ? delta > 0 : delta < 0;
    const travel = directionMatches ? Math.abs(delta) : 0;
    const internalTravel = travel / visualScale();
    const panelElement = shell.querySelector(`.panel--${panelGesture.targetPanel}`);
    panelGesture.panelElement = panelElement;
    panelElement.style.visibility = "visible";
    panelElement.style.transition = "none";
    panelElement.style.transform = panelGesture.targetPanel === "cards"
      ? `translateY(calc(-102% + ${internalTravel}px))`
      : `translateY(calc(102% - ${internalTravel}px))`;

    const progress = clamp(travel / (shell.getBoundingClientRect().height * .42), 0, 1);
    shell.querySelector(".panel-scrim").style.opacity = String(progress);
    shell.querySelector(".home-layer").style.transform = `scale(${1 - progress * .015})`;
    shell.querySelector(".home-layer").style.filter = `blur(${progress * 6}px) brightness(${1 - progress * .12})`;
  });
  shell.addEventListener("pointerup", (event) => {
    if (!panelGesture || panelGesture.id !== event.pointerId) return;
    const delta = event.clientY - panelGesture.startY;
    const targetPanel = panelGesture.targetPanel || (delta > 0 ? "cards" : "evolution");
    const directionMatches = targetPanel === "cards" ? delta > 0 : delta < 0;
    const shouldOpen = directionMatches && Math.abs(delta) > shell.getBoundingClientRect().height * .22;
    const panelElement = panelGesture.panelElement;
    panelGesture = null;
    suppressPanelClick = Math.abs(delta) > 8;

    const homeLayer = shell.querySelector(".home-layer");
    const scrim = shell.querySelector(".panel-scrim");
    homeLayer.style.removeProperty("transform");
    homeLayer.style.removeProperty("filter");
    scrim.style.removeProperty("opacity");

    if (!panelElement) return;
    if (shouldOpen) {
      openPanel(targetPanel);
      panelElement.getBoundingClientRect();
      panelElement.style.removeProperty("transition");
      panelElement.style.removeProperty("transform");
      panelElement.style.removeProperty("visibility");
    } else {
      panelElement.style.transition = "transform 420ms var(--panel-spring)";
      panelElement.style.transform = targetPanel === "cards" ? "translateY(-102%)" : "translateY(102%)";
      setTimeout(() => {
        panelElement.style.removeProperty("transition");
        panelElement.style.removeProperty("transform");
        panelElement.style.removeProperty("visibility");
      }, reducedMotion.matches ? 0 : 430);
    }
  });
  shell.addEventListener("pointercancel", () => {
    if (!panelGesture) return;
    const panelElement = panelGesture.panelElement;
    panelGesture = null;
    suppressPanelClick = false;
    shell.querySelector(".home-layer").style.removeProperty("transform");
    shell.querySelector(".home-layer").style.removeProperty("filter");
    shell.querySelector(".panel-scrim").style.removeProperty("opacity");
    panelElement?.style.removeProperty("transition");
    panelElement?.style.removeProperty("transform");
    panelElement?.style.removeProperty("visibility");
  });

  shell.querySelectorAll(".panel").forEach((panelElement) => {
    let drag = null;
    panelElement.addEventListener("pointerdown", (event) => {
      if (event.target.closest("button") && !event.target.closest(".panel-grip")) return;
      drag = { id: event.pointerId, startY: event.clientY };
      panelElement.setPointerCapture(event.pointerId);
    });
    panelElement.addEventListener("pointermove", (event) => {
      if (!drag || drag.id !== event.pointerId) return;
      const delta = event.clientY - drag.startY;
      const allowed = panelElement.classList.contains("panel--cards") ? Math.min(delta, 0) : Math.max(delta, 0);
      panelElement.style.setProperty("--panel-drag", `${allowed / visualScale()}px`);
    });
    panelElement.addEventListener("pointerup", (event) => {
      if (!drag || drag.id !== event.pointerId) return;
      const delta = event.clientY - drag.startY;
      const visualHeight = shell.getBoundingClientRect().height;
      const shouldClose = panelElement.classList.contains("panel--cards") ? delta < -visualHeight * .12 : delta > visualHeight * .12;
      drag = null;
      if (shouldClose) closePanel();
      else panelElement.style.removeProperty("--panel-drag");
    });
  });

  modalCard.addEventListener("pointermove", (event) => {
    if (reducedMotion.matches) return;
    const rect = modalCard.getBoundingClientRect();
    const x = clamp((event.clientX - rect.left) / rect.width, 0, 1);
    const y = clamp((event.clientY - rect.top) / rect.height, 0, 1);
    modalCard.classList.remove("is-returning");
    modalCard.style.setProperty("--rx", `${(0.5 - y) * 12}deg`);
    modalCard.style.setProperty("--ry", `${(x - 0.5) * 12}deg`);
    modalCard.style.setProperty("--gx", `${x * 100}%`);
    modalCard.style.setProperty("--gy", `${y * 100}%`);
  });
  modalCard.addEventListener("pointerleave", () => {
    modalCard.classList.add("is-returning");
    modalCard.style.setProperty("--rx", "0deg");
    modalCard.style.setProperty("--ry", "0deg");
  });

  shell.addEventListener("keydown", (event) => {
    if (event.key !== "Escape") return;
    if (modal.getAttribute("aria-hidden") === "false") closeCard();
    else if (panel !== "home") closePanel();
  });

  setIndex(0);
  setView("launcher");
}

document.querySelectorAll(".device").forEach(createDevice);
