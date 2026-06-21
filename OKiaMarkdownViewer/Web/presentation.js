/* ===========================================================================
   OK-ia Markdown Viewer — slideshow ("Diaporama")
   Splits a Markdown document on top-level "---" separators and presents each
   block as a full-screen slide, reusing window.OKIA.renderFragment for the
   exact same rendering (mermaid · leaflet · images · callouts · tables).
   Content is auto-fitted to the viewport so images, diagrams and maps show as
   large as possible. Exposes window.OKIA_PRESENT.
   =========================================================================== */
(function () {
  'use strict';

  // Design canvas with a fixed reference HEIGHT (720) and a width that ADAPTS to
  // the screen's aspect ratio, so the canvas always fills the viewport exactly —
  // on phone (wide), tablet (4:3) and Mac (16:10) alike, with no letterboxing.
  // The canvas is then uniformly scaled to the viewport.
  var CH = 720, PAD_H = 72, PAD_V = 48;
  var CW = 1280;   // current canvas logical width, recomputed per fit

  function post(name, payload) {
    try {
      if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers[name]) {
        window.webkit.messageHandlers[name].postMessage(payload || {});
      }
    } catch (e) { /* outside WKWebView */ }
  }

  /* ---- slide splitting ---------------------------------------------------- */

  // Drop a leading YAML frontmatter block, if present.
  function stripFrontmatter(md) {
    var m = md.match(/^﻿?---\r?\n[\s\S]*?\r?\n---\r?\n?/);
    return m ? md.slice(m[0].length) : md;
  }

  // Split on lines that are exactly "---" (or more), but never inside a fenced
  // code block (``` or ~~~) — those dashes belong to the content.
  function splitSlides(md) {
    var lines = stripFrontmatter(md).split(/\r?\n/);
    var slides = [], cur = [], fence = null;
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i];
      var f = line.match(/^\s*(```|~~~)/);
      if (f) {
        if (fence && line.trim().indexOf(fence) === 0) fence = null;
        else if (!fence) fence = f[1];
        cur.push(line);
        continue;
      }
      if (!fence && /^\s*-{3,}\s*$/.test(line)) { slides.push(cur.join('\n')); cur = []; continue; }
      cur.push(line);
    }
    slides.push(cur.join('\n'));
    return slides.map(function (s) { return s.trim(); }).filter(function (s) { return s.length; });
  }

  /* ---- state -------------------------------------------------------------- */

  var deck, progressBar, counter;
  var sections = [];                  // <section.slide> per slide
  var rawSlides = [];
  var rendered = [];                  // bool per slide
  var current = 0;

  // Slide transitions — the 5 Keynote classics. Each spec returns the incoming
  // slide's start state and the outgoing slide's end state (per direction d:
  // +1 = forward / next, -1 = backward / prev).
  var TRANSITIONS = [
    { key: 'dissolve', label: 'Fondu' },
    { key: 'push',     label: 'Poussée' },
    { key: 'movein',   label: 'Entrée' },
    { key: 'scale',    label: 'Échelle' },
    { key: 'flip',     label: 'Retournement 3D' }
  ];
  var SPECS = {
    dissolve: { dur: 450, ease: 'ease',
      enter: function () { return { t: '', o: 0 }; },
      leave: function () { return { t: '', o: 0 }; } },
    push: { dur: 520, ease: 'cubic-bezier(.4,0,.2,1)',
      enter: function (d) { return { t: 'translateX(' + (d * 100) + '%)', o: 1 }; },
      leave: function (d) { return { t: 'translateX(' + (-d * 100) + '%)', o: 1 }; } },
    movein: { dur: 480, ease: 'cubic-bezier(.4,0,.2,1)', incomingOnTop: true,
      enter: function (d) { return { t: 'translateX(' + (d * 100) + '%)', o: 1 }; },
      leave: function () { return { t: '', o: 1 }; } },
    scale: { dur: 480, ease: 'cubic-bezier(.4,0,.2,1)',
      enter: function () { return { t: 'scale(.82)', o: 0 }; },
      leave: function () { return { t: 'scale(1.14)', o: 0 }; } },
    flip: { dur: 640, ease: 'cubic-bezier(.45,0,.25,1)', threeD: true,
      enter: function (d) { return { t: 'rotateY(' + (d * 90) + 'deg)', o: 0 }; },
      leave: function (d) { return { t: 'rotateY(' + (-d * 90) + 'deg)', o: 0 }; } }
  };
  var transition = 'dissolve';
  var animating = false, animTimer = null;

  function el(id) { return document.getElementById(id); }

  /* ---- auto-fit ----------------------------------------------------------- */

  // Scale the fixed design canvas to fill the screen (grow AND shrink), so each
  // slide uses all available room like a real presentation. Content is only
  // scaled DOWN when it would overflow the canvas. Map slides are full-bleed and
  // never transform-scaled (it would break the interactive Leaflet map).
  // Enlarge a single primary image so it fills the canvas's remaining height,
  // keeping aspect ratio (so small sources are scaled up, like dragging an image
  // to fill a PowerPoint slide). Skipped when there are several images.
  function fitImage(section, inner) {
    var imgs = inner.querySelectorAll('img');
    if (imgs.length !== 1) return;
    var img = imgs[0];
    img.style.height = '';
    img.style.width = '';
    if (!img.complete || !img.naturalWidth) {
      img.addEventListener('load', function () { fitSlide(section); }, { once: true });
      return;
    }
    var aspect = img.naturalWidth / img.naturalHeight;
    var availH = CH - PAD_V * 2;
    var availW = CW - PAD_H * 2;
    // Measure the surrounding content (title, caption) with the image collapsed.
    img.style.height = '0px';
    var otherH = inner.scrollHeight;
    var leftover = availH - otherH - 24;                 // breathing room
    var targetH = Math.min(leftover, availW / aspect, 600);
    if (targetH < 120) targetH = Math.min(availW / aspect, 600); // tiny leftover → ignore
    img.style.height = Math.round(targetH) + 'px';
    img.style.width = 'auto';
  }

  function fitSlide(section) {
    if (!section) return;
    var canvas = section.querySelector('.slide-canvas');
    var inner = section.querySelector('.slide-inner');
    if (!canvas || !inner) return;

    if (inner.querySelector('.okia-map')) {
      section.classList.add('slide-map');
      canvas.style.width = '';
      canvas.style.height = '';
      canvas.style.transform = '';
      inner.style.transform = '';
      var mapEl = inner.querySelector('.okia-map');
      if (mapEl && mapEl._leafletMap) {
        setTimeout(function () { try { mapEl._leafletMap.invalidateSize(); } catch (e) {} }, 60);
      }
      return;
    }

    section.classList.remove('slide-map');
    inner.style.transform = '';
    canvas.style.transform = '';

    // Adapt the canvas width to the viewport's aspect ratio so it fills exactly
    // (no letterboxing on 4:3 iPad or 16:10 Mac); height stays the 720 reference.
    var vw = section.clientWidth, vh = section.clientHeight;
    if (vw <= 0 || vh <= 0) return;
    CW = Math.max(640, Math.round(CH * vw / vh));
    canvas.style.width = CW + 'px';
    canvas.style.height = CH + 'px';

    // 0. Grow a lone image to fill the canvas's leftover height (PowerPoint-style).
    fitImage(section, inner);

    // 1. Shrink content if it overflows the design canvas (never enlarge here).
    var availW = CW - PAD_H * 2, availH = CH - PAD_V * 2;
    var h = inner.scrollHeight, w = inner.scrollWidth;
    if (h > 0 && w > 0) {
      var shrink = Math.min(1, availH / h, availW / w);
      if (shrink < 0.999) inner.style.transform = 'scale(' + shrink.toFixed(4) + ')';
    }

    // 2. Scale the whole canvas to fill the viewport (this is the "fill" step).
    var s = vh / CH;   // == vw/CW by construction → fills exactly
    canvas.style.transform = 'scale(' + s.toFixed(4) + ')';
  }

  /* ---- rendering ---------------------------------------------------------- */

  function renderSlide(index) {
    if (rendered[index]) return Promise.resolve();
    rendered[index] = true;
    var inner = sections[index].querySelector('.slide-inner');
    return window.OKIA.renderFragment(inner, rawSlides[index])
      .then(function () { fitSlide(sections[index]); })
      .catch(function () { fitSlide(sections[index]); });
  }

  function updateChrome() {
    var total = sections.length || 1;
    progressBar.style.width = ((current + 1) / total * 100).toFixed(2) + '%';
    counter.textContent = (current + 1) + ' / ' + total;
    el('navPrev').disabled = (current === 0);
    el('navNext').disabled = (current === sections.length - 1);
  }

  function clearAnim(elm) {
    elm.style.transition = '';
    elm.style.transform = '';
    elm.style.opacity = '';
    elm.style.zIndex = '';
  }

  // End any in-flight animation immediately, leaving only `keepEl` visible.
  function finishPending(keepEl) {
    if (animTimer) { clearTimeout(animTimer); animTimer = null; }
    sections.forEach(function (s) {
      if (s !== keepEl) { s.classList.remove('active'); clearAnim(s); }
    });
    animating = false;
  }

  function show(index) {
    if (index < 0 || index >= sections.length) return;
    if (index === current) { fitSlide(sections[current]); return; }
    var dir = index > current ? 1 : -1;
    var fromEl = sections[current], toEl = sections[index];
    current = index;
    updateChrome();

    // Ensure the incoming slide is rendered & fitted before/just as it appears.
    renderSlide(index).then(function () { fitSlide(toEl); });
    fitSlide(toEl);
    var ahead = index + dir;
    if (ahead >= 0 && ahead < sections.length) renderSlide(ahead);

    runTransition(fromEl, toEl, dir);
  }

  function runTransition(fromEl, toEl, dir) {
    finishPending(fromEl);                       // settle any previous animation
    var spec = SPECS[transition] || SPECS.dissolve;
    var dur = spec.dur;
    animating = true;

    deck.classList.toggle('deck-3d', !!spec.threeD);

    // Both slides visible during the transition; incoming on top when needed.
    toEl.classList.add('active');
    toEl.style.zIndex = spec.incomingOnTop ? '3' : '2';
    fromEl.style.zIndex = '1';

    // Initial states (no animation yet).
    toEl.style.transition = 'none';
    fromEl.style.transition = 'none';
    var e = spec.enter(dir);
    toEl.style.transform = e.t; toEl.style.opacity = e.o;
    fromEl.style.transform = ''; fromEl.style.opacity = 1;

    // Force reflow so the start state is committed before we animate.
    void toEl.offsetWidth;

    var tr = 'transform ' + dur + 'ms ' + spec.ease + ', opacity ' + dur + 'ms ' + spec.ease;
    toEl.style.transition = tr;
    fromEl.style.transition = tr;
    toEl.style.transform = ''; toEl.style.opacity = 1;
    var l = spec.leave(dir);
    fromEl.style.transform = l.t; fromEl.style.opacity = l.o;

    animTimer = setTimeout(function () {
      animTimer = null;
      fromEl.classList.remove('active');
      clearAnim(fromEl);
      clearAnim(toEl);
      deck.classList.remove('deck-3d');
      animating = false;
    }, dur + 40);
  }

  function next() { show(current + 1); }
  function prev() { show(current - 1); }
  function exit() { post('presentExit'); }

  /* ---- transition choice -------------------------------------------------- */

  function setTransition(key) {
    if (!SPECS[key]) return;
    transition = key;
    try { localStorage.setItem('okia.transition', key); } catch (e) {}
    syncMenu();
  }

  function syncMenu() {
    var menu = el('presentMenu');
    if (!menu) return;
    Array.prototype.forEach.call(menu.querySelectorAll('.present-menu-item'), function (b) {
      b.classList.toggle('selected', b.getAttribute('data-key') === transition);
    });
  }

  function buildMenu() {
    var menu = el('presentMenu');
    if (!menu) return;
    menu.innerHTML = '<div class="present-menu-title">Transition</div>';
    TRANSITIONS.forEach(function (t) {
      var b = document.createElement('button');
      b.className = 'present-menu-item';
      b.setAttribute('data-key', t.key);
      b.textContent = t.label;
      b.onclick = function (ev) { ev.stopPropagation(); setTransition(t.key); closeMenu(); };
      menu.appendChild(b);
    });
    syncMenu();
  }

  function openMenu()  { var m = el('presentMenu'); if (m) { m.hidden = false; syncMenu(); } }
  function closeMenu() { var m = el('presentMenu'); if (m) m.hidden = true; }
  function toggleMenu(ev) {
    if (ev) ev.stopPropagation();
    var m = el('presentMenu');
    if (m) { if (m.hidden) openMenu(); else closeMenu(); }
  }

  /* ---- input -------------------------------------------------------------- */
  // Hardware-keyboard navigation is driven natively (UIKeyCommand) and routed
  // through next()/prev()/exit(); see PresentationWebView. Touch swipe below.

  // Horizontal swipe on touch devices (iPhone/iPad without a keyboard).
  var touchX = null, touchY = null;
  function onTouchStart(e) {
    if (e.touches.length !== 1) { touchX = null; return; }
    touchX = e.touches[0].clientX; touchY = e.touches[0].clientY;
  }
  function onTouchEnd(e) {
    if (touchX === null) return;
    var t = e.changedTouches[0];
    var dx = t.clientX - touchX, dy = t.clientY - touchY;
    touchX = null;
    if (Math.abs(dx) > 50 && Math.abs(dx) > Math.abs(dy) * 1.5) {
      if (dx < 0) next(); else prev();
    }
  }

  /* ---- lifecycle ---------------------------------------------------------- */

  function build() {
    deck.innerHTML = '';
    sections = []; rendered = [];
    rawSlides.forEach(function (_, i) {
      var section = document.createElement('section');
      section.className = 'slide';
      var canvas = document.createElement('div');
      canvas.className = 'slide-canvas';
      var inner = document.createElement('div');
      inner.className = 'slide-inner markdown-body';
      canvas.appendChild(inner);
      section.appendChild(canvas);
      deck.appendChild(section);
      sections.push(section);
      rendered.push(false);
    });
  }

  var resizeTimer = null;
  function onResize() {
    clearTimeout(resizeTimer);
    resizeTimer = setTimeout(function () { fitSlide(sections[current]); }, 120);
  }

  function start(md) {
    deck = el('deck');
    progressBar = el('progressBar');
    counter = el('counter');

    rawSlides = splitSlides(md || '');
    if (!rawSlides.length) rawSlides = [' '];
    current = 0;
    build();

    // Restore the saved transition choice.
    try {
      var saved = localStorage.getItem('okia.transition');
      if (saved && SPECS[saved]) transition = saved;
    } catch (e) {}
    buildMenu();

    sections[0].classList.add('active');
    updateChrome();
    renderSlide(0).then(function () { fitSlide(sections[0]); });
    if (sections.length > 1) renderSlide(1);

    el('navPrev').onclick = function (e) { e.stopPropagation(); prev(); };
    el('navNext').onclick = function (e) { e.stopPropagation(); next(); };
    el('presentEnd').onclick = function (e) { e.stopPropagation(); exit(); };
    var menuBtn = el('presentMenuBtn');
    if (menuBtn) menuBtn.onclick = toggleMenu;
    // Tap anywhere else closes the transition menu.
    document.addEventListener('click', closeMenu);

    window.addEventListener('resize', onResize);
    window.addEventListener('orientationchange', onResize);
    deck.addEventListener('touchstart', onTouchStart, { passive: true });
    deck.addEventListener('touchend', onTouchEnd, { passive: true });

    try { window.focus(); } catch (e) {}
    post('presentStarted', { count: sections.length });
  }

  window.OKIA_PRESENT = { start: start, next: next, prev: prev, exit: exit,
                          setTransition: setTransition };
  post('presentReady', {});
})();
