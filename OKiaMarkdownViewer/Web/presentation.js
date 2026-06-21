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

  // Fixed design canvas (16:9). Slides are laid out here, then the whole canvas
  // is uniformly scaled to fill the screen — so every slide uses all the room.
  var CW = 1280, CH = 720, PAD_H = 72, PAD_V = 48;

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
    var s = Math.min(section.clientWidth / CW, section.clientHeight / CH);
    if (s > 0 && isFinite(s)) canvas.style.transform = 'scale(' + s.toFixed(4) + ')';
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

  function show(index) {
    if (index < 0 || index >= sections.length || index === current) {
      // still refit (e.g. resize) the active slide
      if (index === current) fitSlide(sections[current]);
      return;
    }
    sections[current].classList.remove('active');
    current = index;
    var section = sections[current];
    section.classList.add('active');
    updateChrome();
    renderSlide(current).then(function () { fitSlide(section); });
    // Warm the neighbour so the next transition is instant.
    if (current + 1 < sections.length) renderSlide(current + 1);
  }

  function next() { show(current + 1); }
  function prev() { show(current - 1); }
  function exit() { post('presentExit'); }

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

    sections[0].classList.add('active');
    updateChrome();
    renderSlide(0).then(function () { fitSlide(sections[0]); });
    if (sections.length > 1) renderSlide(1);

    el('navPrev').onclick = function (e) { e.stopPropagation(); prev(); };
    el('navNext').onclick = function (e) { e.stopPropagation(); next(); };
    el('presentEnd').onclick = function (e) { e.stopPropagation(); exit(); };

    window.addEventListener('resize', onResize);
    window.addEventListener('orientationchange', onResize);
    deck.addEventListener('touchstart', onTouchStart, { passive: true });
    deck.addEventListener('touchend', onTouchEnd, { passive: true });

    try { window.focus(); } catch (e) {}
    post('presentStarted', { count: sections.length });
  }

  window.OKIA_PRESENT = { start: start, next: next, prev: prev, exit: exit };
  post('presentReady', {});
})();
