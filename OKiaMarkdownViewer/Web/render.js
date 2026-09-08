/* ===========================================================================
   OK-ia Markdown Viewer — rendering pipeline
   Reproduces the ok-ia.ch viewer: frontmatter → mermaid → callouts → wiki-links
   → NER → marked.parse → mermaid normalize/run/recolor. Images are never probed
   before painting: they load lazily and drop themselves if they fail.
   Exposes window.OKIA.render(markdown, filename).
   =========================================================================== */
(function () {
  'use strict';

  var NOIR = '#111111';

  // App language, injected by the host app (window.OKIA_LANG): fr | en | de | es | it.
  var LANGS = ['fr', 'en', 'de', 'es', 'it'];
  var LANG = LANGS.indexOf(window.OKIA_LANG) >= 0 ? window.OKIA_LANG : 'fr';

  // The French text is the key, so French needs no entry of its own — and an untranslated
  // string degrades to readable French rather than to an identifier.
  var STRINGS = {
    'Lire l\'article': { en: 'Read the article', de: 'Den Artikel lesen',
                         es: 'Leer el artículo', it: 'Leggi l\'articolo' },
    'Erreur de rendu':  { en: 'Rendering error', de: 'Rendering-Fehler',
                          es: 'Error de renderizado', it: 'Errore di rendering' },
    'Document volumineux, rendu en cours…':
      { en: 'Large document, rendering…', de: 'Umfangreiches Dokument, wird gerendert…',
        es: 'Documento voluminoso, procesando…', it: 'Documento voluminoso, rendering in corso…' },
    'Carte indisponible hors connexion':
      { en: 'Map unavailable offline', de: 'Karte offline nicht verfügbar',
        es: 'Mapa no disponible sin conexión', it: 'Mappa non disponibile offline' },
    'Chargement de la carte…':
      { en: 'Loading the map…', de: 'Karte wird geladen…',
        es: 'Cargando el mapa…', it: 'Caricamento della mappa…' }
  };
  function TXT(fr) {
    var entry = STRINGS[fr];
    return (LANG === 'fr' || !entry || !entry[LANG]) ? fr : entry[LANG];
  }

  // Date formatting locale per language (Swiss variants where the app has one).
  var DATE_LOCALE = { fr: 'fr-CH', en: 'en-GB', de: 'de-CH', es: 'es-ES', it: 'it-CH' };

  /* ---- native bridge ----------------------------------------------------- */
  function post(name, payload) {
    try {
      if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers[name]) {
        window.webkit.messageHandlers[name].postMessage(payload);
      }
    } catch (e) { /* running outside WKWebView (e.g. browser preview) */ }
  }

  /* ---- HTML escaping ----------------------------------------------------- */
  function escapeHtml(s) {
    return String(s)
      .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;').replace(/'/g, '&#39;');
  }
  function escapeRegExp(s) { return s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'); }

  /* =========================================================================
     1. FRONTMATTER
     ========================================================================= */
  function parseFrontmatter(md) {
    var meta = {};
    var m = md.match(/^﻿?---\r?\n([\s\S]*?)\r?\n---\r?\n?/);
    if (!m) return { meta: meta, body: md };
    var lines = m[1].split(/\r?\n/);
    lines.forEach(function (line) {
      var kv = line.match(/^([A-Za-z0-9_\-]+)\s*:\s*(.*)$/);
      if (!kv) return;
      var key = kv[1].toLowerCase();
      var val = kv[2].trim().replace(/^["']/, '').replace(/["']$/, '');
      meta[key] = val;
    });
    return { meta: meta, body: md.slice(m[0].length) };
  }

  function pick(meta) {
    for (var i = 1; i < arguments.length; i++) {
      if (meta[arguments[i]]) return meta[arguments[i]];
    }
    return null;
  }

  function cleanFilename(name) {
    if (!name) return null;
    return name.replace(/\.[^.]+$/, '').replace(/[_-]+/g, ' ').trim();
  }

  function formatDate(raw) {
    if (!raw) return null;
    var d = null;
    var iso = raw.match(/^(\d{4})-(\d{2})-(\d{2})/);
    var ch = raw.match(/^(\d{1,2})[.\/](\d{1,2})[.\/](\d{4})/);
    if (iso) d = new Date(parseInt(iso[1]), parseInt(iso[2]) - 1, parseInt(iso[3]));
    else if (ch) d = new Date(parseInt(ch[3]), parseInt(ch[2]) - 1, parseInt(ch[1]));
    if (!d || isNaN(d.getTime())) return raw;
    try {
      return new Intl.DateTimeFormat(DATE_LOCALE[LANG],
                                     { day: 'numeric', month: 'long', year: 'numeric' }).format(d);
    } catch (e) { return raw; }
  }

  function firstH1(body) {
    var m = body.match(/^#\s+(.+?)\s*$/m);
    return m ? m[1].trim() : null;
  }

  function buildHeader(meta, body, filename) {
    var title = pick(meta, 'title', 'titre') || firstH1(body) || cleanFilename(filename) || 'Document';
    var source = pick(meta, 'source');
    var dateStr = formatDate(pick(meta, 'date', 'date_publication'));
    var lecture = pick(meta, 'temps_lecture');
    var url = pick(meta, 'url');
    var author = pick(meta, 'auteur', 'author');

    var parts = [];
    if (source) parts.push('<span class="meta-source">' + escapeHtml(source) + '</span>');
    if (author) parts.push('<span class="meta-author">' + escapeHtml(author) + '</span>');
    if (dateStr) parts.push('<span class="meta-date">' + escapeHtml(dateStr) + '</span>');
    if (lecture) parts.push('<span class="meta-read">' + escapeHtml(lecture) + '</span>');
    if (url) parts.push('<a href="' + escapeHtml(url) + '" target="_blank" rel="noopener">' +
                        TXT('Lire l\'article') + ' ↗</a>');

    var metaBar = parts.length
      ? '<div class="okia-meta">' + parts.join('<span class="sep">·</span>') + '</div>'
      : '';

    var headerHtml = '<h1 class="okia-title">' + escapeHtml(title) + '</h1>' + metaBar;
    return { title: title, headerHtml: headerHtml };
  }

  /* =========================================================================
     2. MERMAID BLOCKS  ```mermaid ... ```  ->  <pre class="mermaid">
     ========================================================================= */
  function transformMermaid(md) {
    return md.replace(/```mermaid[ \t]*\r?\n([\s\S]*?)```/g, function (_, code) {
      return '\n<pre class="mermaid">' + escapeHtml(code.replace(/\s+$/, '')) + '</pre>\n';
    });
  }

  /* =========================================================================
     2b. OBSIDIAN LEAFLET MAPS  ```leaflet ... ```  ->  <div class="okia-map">
         Parses the Obsidian Leaflet plugin block into a config object, which is
         base64-encoded onto the placeholder and consumed after marked.parse.
     ========================================================================= */
  function b64encode(str) {
    try { return btoa(unescape(encodeURIComponent(str))); } catch (e) { return ''; }
  }
  function b64decode(str) {
    try { return decodeURIComponent(escape(atob(str))); } catch (e) { return ''; }
  }

  // Pull the two coordinates + an optional [[link]] / free-text label out of a marker line.
  function parseMarkerLine(value) {
    var link = null;
    var wl = value.match(/\[\[([^\]|]+)(?:\|([^\]]+))?\]\]/);
    if (wl) { link = { target: wl[1].trim(), label: (wl[2] || wl[1]).trim() }; }
    var cleaned = value.replace(/\[\[[^\]]*\]\]/g, '').replace(/[\[\]]/g, ' ');
    var nums = cleaned.match(/-?\d+(?:\.\d+)?/g);
    if (!nums || nums.length < 2) return null;
    var lat = parseFloat(nums[0]), lng = parseFloat(nums[1]);
    if (!isFinite(lat) || !isFinite(lng)) return null;
    // Any trailing free text (after the coords, not a wiki-link) becomes the label.
    var rest = cleaned.replace(nums[0], '').replace(nums[1], '')
                      .replace(/^[\s,]+|[\s,]+$/g, '').trim();
    var label = link ? link.label : (rest || null);
    return { lat: lat, lng: lng, label: label, link: link ? link.target : null };
  }

  function parseLeafletBlock(code) {
    var cfg = { markers: [], lat: null, lng: null, zoom: null,
                minZoom: 0, maxZoom: 19, height: '420px', defaultTiles: null };
    code.split(/\r?\n/).forEach(function (raw) {
      var line = raw.trim();
      if (!line) return;
      var kv = line.match(/^([A-Za-z_]+)\s*:\s*(.*)$/);
      if (!kv) return;
      var key = kv[1].toLowerCase(), val = kv[2].trim();
      switch (key) {
        case 'lat':      cfg.lat = parseFloat(val); break;
        case 'long':     cfg.lng = parseFloat(val); break;
        case 'minzoom':  cfg.minZoom = parseInt(val, 10); break;
        case 'maxzoom':  cfg.maxZoom = parseInt(val, 10); break;
        case 'defaultzoom':
        case 'zoom':     cfg.zoom = parseFloat(val); break;
        case 'height':   cfg.height = /^\d+$/.test(val) ? val + 'px' : val; break;
        case 'tileserver':
        case 'tiles':    cfg.defaultTiles = val; break;
        case 'marker':
        case 'markers': {
          var m = parseMarkerLine(val);
          if (m) cfg.markers.push(m);
          break;
        }
        default: break;
      }
    });
    return cfg;
  }

  function transformLeaflet(md) {
    return md.replace(/```leaflet[ \t]*\r?\n([\s\S]*?)```/g, function (_, code) {
      var cfg = parseLeafletBlock(code);
      return '\n<div class="okia-map" data-okia-map="' +
             b64encode(JSON.stringify(cfg)) + '"></div>\n';
    });
  }

  /* =========================================================================
     3. OBSIDIAN CALLOUTS  > [!type] Title
     ========================================================================= */
  var CALLOUTS = {
    note:    { color: '#4a9eff', icon: '📝' }, info:    { color: '#4a9eff', icon: 'ℹ️' },
    todo:    { color: '#4a9eff', icon: '☑️' },
    tip:     { color: '#34c98e', icon: '💡' }, hint:    { color: '#34c98e', icon: '💡' },
    success: { color: '#34c98e', icon: '✅' }, check:   { color: '#34c98e', icon: '✅' },
    done:    { color: '#34c98e', icon: '✅' },
    important:{ color: '#e8971e', icon: '🔔' }, warning:{ color: '#e8971e', icon: '⚠️' },
    caution: { color: '#e8971e', icon: '⚠️' },
    failure: { color: '#ef5350', icon: '❌' }, danger:  { color: '#ef5350', icon: '🚫' },
    error:   { color: '#ef5350', icon: '⛔' }, bug:     { color: '#ef5350', icon: '🐛' },
    question:{ color: '#b39ddb', icon: '❓' }, help:    { color: '#b39ddb', icon: '❓' },
    faq:     { color: '#b39ddb', icon: '❓' },
    example: { color: '#8e6bbf', icon: '📋' },
    quote:   { color: '#9e9e9e', icon: '💬' }, cite:    { color: '#9e9e9e', icon: '💬' },
    abstract:{ color: '#7ecef4', icon: '📄' }, summary: { color: '#7ecef4', icon: '📄' },
    tldr:    { color: '#7ecef4', icon: '📄' }
  };

  function transformCallouts(md) {
    var lines = md.split(/\r?\n/);
    var out = [];
    for (var i = 0; i < lines.length; i++) {
      var head = lines[i].match(/^>\s*\[!(\w+)\][+-]?\s*(.*)$/);
      if (!head) { out.push(lines[i]); continue; }
      var type = head[1].toLowerCase();
      var def = CALLOUTS[type] || { color: '#E8972E', icon: '📌' };
      var titleText = head[2].trim() || (type.charAt(0).toUpperCase() + type.slice(1));
      var content = [];
      var j = i + 1;
      while (j < lines.length && /^>/.test(lines[j])) {
        content.push(lines[j].replace(/^>\s?/, ''));
        j++;
      }
      var innerHtml = marked.parse(content.join('\n'), { breaks: true, gfm: true });
      out.push(
        '<div class="callout callout-' + type + '" style="--callout-color:' + def.color + '">' +
          '<div class="callout-title"><span class="callout-icon">' + def.icon + '</span>' +
          escapeHtml(titleText) + '</div>' +
          '<div class="callout-content">' + innerHtml + '</div>' +
        '</div>'
      );
      i = j - 1;
    }
    return out.join('\n');
  }

  /* =========================================================================
     4. WIKI-LINKS  [[Name]] / [[Name|Alias]]
     ========================================================================= */
  function transformWikiLinks(md) {
    return md.replace(/\[\[([^\]|]+)(?:\|([^\]]+))?\]\]/g, function (_, name, alias) {
      var label = (alias || name).trim();
      return '<span class="wiki-link" data-wiki="' + escapeHtml(name.trim()) + '">' +
             escapeHtml(label) + '</span>';
    });
  }

  /* =========================================================================
     5. BROKEN IMAGES (offline-tolerant)
     ========================================================================= */
  // Images used to be probed BEFORE anything was painted: every remote URL was downloaded
  // in full (new Image() fetches the file, it is not a HEAD) just to learn which ones were
  // dead, and `container.innerHTML` waited on all of them. Measured on a 858-article
  // briefing with 815 remote images: 468 ms to parse and paint the whole document, but
  // 2 449 ms once the probe ran — and that was against a local server with no latency.
  // Over a real network it is what turned a large report into an indefinitely blank screen.
  //
  // Now nothing is probed. The browser fetches each image when it scrolls into view, and
  // reports failures itself; the two helpers below carry what the probe used to provide.

  // `loading="lazy"` has to be in the markup BEFORE it reaches the DOM — the browser starts
  // fetching the instant the element exists, so setting the attribute afterwards is too late
  // to save the request.
  function withLazyImages(html) {
    return html.replace(/<img\b/gi, '<img loading="lazy" decoding="async"');
  }

  // A caption is the paragraph right after an image when it holds nothing but emphasis —
  // the shape `![](…)` + `*Légende*` produces, and what the old probe stripped alongside a
  // dead image.
  function isCaptionParagraph(node) {
    if (!node || node.tagName !== 'P' || node.children.length !== 1) return false;
    var only = node.children[0];
    return (only.tagName === 'EM' || only.tagName === 'I') &&
           node.textContent.trim() === only.textContent.trim();
  }

  function dropBrokenImage(img) {
    var host = img.parentNode;
    // `![](…)` alone on its line becomes a <p> holding just the image: drop the paragraph
    // and its caption, so no empty gap is left behind.
    if (host && host.tagName === 'P' && host.textContent.trim() === '' &&
        host.querySelectorAll('img').length === 1) {
      var caption = host.nextElementSibling;
      if (isCaptionParagraph(caption)) caption.parentNode.removeChild(caption);
      host.parentNode.removeChild(host);
    } else {
      img.parentNode.removeChild(img);   // inline in a paragraph: drop just the image
    }
  }

  function watchImages(container) {
    var imgs = container.querySelectorAll('img');
    for (var i = 0; i < imgs.length; i++) {
      var img = imgs[i];
      if (img.getAttribute('data-okia-watched') === '1') continue;
      img.setAttribute('data-okia-watched', '1');
      img.addEventListener('error', function () { dropBrokenImage(this); });
      // A cached failure can land before the listener is attached: `complete` with no
      // intrinsic width means the fetch already finished and produced nothing.
      if (img.complete && img.naturalWidth === 0 && img.getAttribute('loading') !== 'lazy') {
        dropBrokenImage(img);
      }
    }
  }


  /* =========================================================================
     6. NER  — parse `## Entités` section, build color map + legend.
     Highlighting is applied to text nodes after marked.parse (DOM-safe).
     ========================================================================= */
  var NER_PALETTE = [[232,151,46],[59,130,246],[139,92,246],[16,185,129],
                     [239,68,68],[245,158,11],[236,72,153],[20,184,166]];

  // Titre de la section d'entités dans les cinq langues d'export de fornews.ai
  // (fr/en/de/es/it), singulier ou pluriel. Le titre est d'abord dépouillé de ses
  // accents, donc « Entités », « Entites », « Entità » et « Entitäten » se ramènent
  // tous à une forme ASCII. La liste reste fermée : « Sources » n'est pas reconnu.
  var ENTITY_HEADING_RE =
    /^(?:entit(?:es?|y|ies|a|at(?:en)?|aet(?:en)?)|entidad(?:es)?)$/;

  function isEntityHeading(title) {
    var ascii = title.trim().toLowerCase();
    // NFD + suppression des diacritiques : é→e, ä→a, à→a…
    if (ascii.normalize) ascii = ascii.normalize('NFD').replace(/[\u0300-\u036f]/g, '');
    return ENTITY_HEADING_RE.test(ascii);
  }

  function extractEntities(body) {
    var lines = body.split(/\r?\n/);
    var inSection = false, subtype = null, colorIdx = 0;
    var subtypes = {};            // subtype -> rgb
    var entities = {};            // entityName -> rgb
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i];
      var h2 = line.match(/^##\s+(.+?)\s*$/);
      if (h2) {
        inSection = isEntityHeading(h2[1]);
        subtype = null;
        if (!inSection && /^(##\s)/.test(line)) { /* left the section */ }
        continue;
      }
      if (!inSection) continue;
      var h3 = line.match(/^###\s+(.+?)\s*$/);
      if (h3) {
        subtype = h3[1].trim();
        if (!(subtype in subtypes)) {
          subtypes[subtype] = NER_PALETTE[colorIdx % NER_PALETTE.length];
          colorIdx++;
        }
        continue;
      }
      var ent = line.match(/\[\[([^\]|]+)(?:\|[^\]]+)?\]\]/);
      if (ent && subtype) {
        var name = ent[1].trim();
        if (name) entities[name] = subtypes[subtype];
      }
    }
    return { subtypes: subtypes, entities: entities };
  }

  function buildLegend(subtypes) {
    var keys = Object.keys(subtypes);
    if (!keys.length) return '';
    var chips = keys.map(function (k) {
      var rgb = subtypes[k].join(',');
      return '<span class="ner-chip" style="--ner-rgb:' + rgb + '">' +
             '<span class="ner-dot"></span>' + escapeHtml(k) + '</span>';
    });
    return '<div class="ner-legend">' + chips.join('') + '</div>';
  }

  function highlightEntities(container, entities, subtypes) {
    var names = Object.keys(entities);
    if (names.length) {
      names.sort(function (a, b) { return b.length - a.length; });
      var pattern = new RegExp('(' + names.map(escapeRegExp).join('|') + ')', 'g');
      var SKIP = { CODE: 1, PRE: 1, A: 1, MARK: 1, SCRIPT: 1, STYLE: 1, H1: 1, H2: 1, H3: 1 };
      var walker = document.createTreeWalker(container, NodeFilter.SHOW_TEXT, null);
      var todo = [], node;
      while ((node = walker.nextNode())) {
        if (node.parentNode && SKIP[node.parentNode.nodeName]) continue;
        if (node.parentNode && node.parentNode.classList &&
            node.parentNode.classList.contains('callout-title')) continue;
        if (pattern.test(node.nodeValue)) { pattern.lastIndex = 0; todo.push(node); }
      }
      todo.forEach(function (textNode) {
        var frag = document.createDocumentFragment();
        var text = textNode.nodeValue, last = 0, mm;
        pattern.lastIndex = 0;
        while ((mm = pattern.exec(text)) !== null) {
          if (mm.index > last) frag.appendChild(document.createTextNode(text.slice(last, mm.index)));
          var mark = document.createElement('mark');
          mark.className = 'ner-tag';
          mark.style.setProperty('--ner-rgb', entities[mm[1]].join(','));
          mark.textContent = mm[1];
          frag.appendChild(mark);
          last = mm.index + mm[1].length;
        }
        if (last < text.length) frag.appendChild(document.createTextNode(text.slice(last)));
        textNode.parentNode.replaceChild(frag, textNode);
      });
    }
    // Color the entity sub-headings (Organisations / Personnes / …)
    container.querySelectorAll('h3').forEach(function (h) {
      var key = h.textContent.trim();
      if (subtypes[key]) h.style.color = 'rgb(' + subtypes[key].join(',') + ')';
    });
  }

  /* =========================================================================
     MERMAID rendering
     ========================================================================= */
  function attachZoom(pre, title) {
    pre.setAttribute('data-rendered', '1');
    pre.addEventListener('click', function () {
      var svg = pre.querySelector('svg');
      if (!svg) return;
      post('diagramTapped', { svg: svg.outerHTML, title: title || '' });
    });
  }

  /* Make content images tappable → open full-screen in a native zoom view.
     Linked images keep their link; broken/hidden ones are skipped. */
  function attachImageZoom(container) {
    var imgs = Array.prototype.slice.call(container.querySelectorAll('img'));
    imgs.forEach(function (img) {
      if (img.closest('a')) return;                 // an image that is itself a link
      if (img.getAttribute('data-okia-zoom') === '1') return;
      img.setAttribute('data-okia-zoom', '1');
      img.classList.add('okia-zoomable');
      img.addEventListener('click', function () {
        if (img.style.display === 'none') return;
        post('imageTapped', { src: img.currentSrc || img.src });
      });
    });
  }

  /* Final contrast guard: after the OK-ia theme/recolor runs, force every node
     and cluster label to contrast with ITS OWN rendered fill. This fixes cases
     where a styled subgraph's white text bled onto child nodes that have a white
     fill (white-on-white → invisible). Uses the actual painted colour, so it is
     correct regardless of how the palette was remapped. */
  function okiaParseColor(str) {
    if (!str) return null;
    str = String(str).trim();
    if (str === 'none' || str === 'transparent') return { r: 255, g: 255, b: 255, a: 0 };
    if (str.charAt(0) === '#') {
      var h = str.slice(1);
      if (h.length === 3) h = h.split('').map(function (c) { return c + c; }).join('');
      if (h.length < 6) return null;
      return { r: parseInt(h.slice(0, 2), 16), g: parseInt(h.slice(2, 4), 16),
               b: parseInt(h.slice(4, 6), 16), a: 1 };
    }
    var m = str.match(/rgba?\(([^)]+)\)/i);
    if (m) {
      var p = m[1].split(',').map(function (s) { return parseFloat(s); });
      return { r: p[0], g: p[1], b: p[2], a: p.length > 3 ? p[3] : 1 };
    }
    return null;
  }

  function okiaContrastFor(fillStr) {
    var c = okiaParseColor(fillStr);
    if (!c) return null;
    // Transparent fill → sits on the light diagram background → dark text.
    var lum = (c.a === 0) ? 1 : (0.299 * c.r + 0.587 * c.g + 0.114 * c.b) / 255;
    return lum < 0.5 ? '#FAFAF8' : NOIR;
  }

  function okiaPaintLabel(scope, color) {
    scope.querySelectorAll('text, tspan').forEach(function (t) {
      t.style.setProperty('fill', color, 'important');
    });
    scope.querySelectorAll('foreignObject span, foreignObject p, foreignObject div, foreignObject label')
      .forEach(function (t) { t.style.setProperty('color', color, 'important'); });
  }

  function enforceMermaidContrast(root) {
    // Nodes: each label contrasts with its own shape fill.
    root.querySelectorAll('.node').forEach(function (node) {
      var shape = node.querySelector('rect, polygon, circle, ellipse, path');
      if (!shape) return;
      var fill = (window.getComputedStyle(shape).fill) || shape.getAttribute('fill');
      var color = okiaContrastFor(fill);
      if (!color) return;
      var label = node.querySelector('.label') || node.querySelector('foreignObject') || node;
      okiaPaintLabel(label, color);
    });
    // Clusters: only the cluster's OWN title (never its child nodes).
    root.querySelectorAll('.cluster').forEach(function (cl) {
      var shape = cl.querySelector(':scope > rect, :scope > polygon, :scope > path');
      if (!shape) return;
      var fill = (window.getComputedStyle(shape).fill) || shape.getAttribute('fill');
      var color = okiaContrastFor(fill);
      if (!color) return;
      var label = cl.querySelector('.cluster-label');
      if (label) okiaPaintLabel(label, color);
    });
  }

  /* Some Mermaid diagrams (notably xychart-beta) draw their bottom axis labels
     a hair past the SVG viewBox, so the labels get clipped. Grow the viewBox to
     enclose the full content (with a small margin). Only ever expands — diagrams
     already within their viewBox are untouched. */
  function unclipMermaidSvg(svg) {
    try {
      if (!svg.viewBox || !svg.viewBox.baseVal || !svg.viewBox.baseVal.width) return;
      var vb = svg.viewBox.baseVal;
      var bb = svg.getBBox();
      if (!bb || !isFinite(bb.width) || bb.width <= 0) return;
      var pad = 6;
      var x1 = Math.min(vb.x, bb.x - pad);
      var y1 = Math.min(vb.y, bb.y - pad);
      var x2 = Math.max(vb.x + vb.width, bb.x + bb.width + pad);
      var y2 = Math.max(vb.y + vb.height, bb.y + bb.height + pad);
      if (x1 < vb.x - 0.5 || y1 < vb.y - 0.5 ||
          x2 > vb.x + vb.width + 0.5 || y2 > vb.y + vb.height + 0.5) {
        svg.setAttribute('viewBox', x1 + ' ' + y1 + ' ' + (x2 - x1) + ' ' + (y2 - y1));
      }
    } catch (e) {}
  }

  /* Charts (xychart/pie/quadrant/gantt) use filled areas that turn invisible
     under the dark-theme invert filter; flag them so the slideshow puts them on
     a light card instead of inverting. */
  /* xychart-beta renders bars/line as pale tints (≈#FFF4DD) that are nearly
     invisible on the light plot, and mermaid's base theme ignores the configured
     plotColorPalette. Recolor each plot series to a saturated OK-ia colour by its
     plot index (bars + line markers). No-op on non-xychart diagrams. */
  function recolorXychart(svg) {
    var PALETTE = ['#E8972E', '#1A3A5C', '#2D5A1B', '#8B0000', '#9A9A90', '#F0A840'];
    function idx(g) {
      var m = (g.getAttribute('class') || '').match(/(?:bar|line)-plot-(\d+)/);
      return m ? parseInt(m[1], 10) : 0;
    }
    svg.querySelectorAll('g[class*="bar-plot-"]').forEach(function (g) {
      var c = PALETTE[idx(g) % PALETTE.length];
      g.querySelectorAll('rect').forEach(function (r) {
        r.style.setProperty('fill', c, 'important');
        r.style.setProperty('stroke', c, 'important');
      });
    });
    svg.querySelectorAll('g[class*="line-plot-"]').forEach(function (g) {
      var c = PALETTE[idx(g) % PALETTE.length];
      g.querySelectorAll('path').forEach(function (p) {
        p.style.setProperty('stroke', c, 'important');
        p.style.setProperty('stroke-width', '3px', 'important');
      });
      g.querySelectorAll('circle').forEach(function (ci) {
        ci.style.setProperty('fill', c, 'important');
      });
    });
  }

  function mermaidKeepsLight(src) {
    var m = (src || '').replace(/^\s*%%[^\n]*\r?\n/, '').match(/^\s*([A-Za-z-]+)/);
    var t = m ? m[1].toLowerCase() : '';
    return /^(xychart|pie|quadrantchart|gantt)/.test(t);
  }

  function renderMermaid(container, title) {
    var blocks = Array.prototype.slice.call(container.querySelectorAll('pre.mermaid'));
    if (!blocks.length) return Promise.resolve();

    // Keep original source for recoloring; normalize palette before run.
    blocks.forEach(function (pre) {
      var src = pre.textContent;
      pre.setAttribute('data-okia-src', src);
      var normalized = window.normalizeMermaidPalette ? window.normalizeMermaidPalette(src) : src;
      pre.textContent = normalized;
    });

    try { mermaid.initialize(window.OKIA_MERMAID_CONFIG); } catch (e) {}

    return mermaid.run({ nodes: blocks }).then(function () {
      blocks.forEach(function (pre) {
        var src = pre.getAttribute('data-okia-src');
        if (window.applyMermaidTextColors) {
          try { window.applyMermaidTextColors(pre, src); } catch (e) {}
        }
        pre.classList.toggle('mermaid-keeplight', mermaidKeepsLight(src));
        try { enforceMermaidContrast(pre); } catch (e) {}
        var svgEl = pre.querySelector('svg');
        if (svgEl) { recolorXychart(svgEl); unclipMermaidSvg(svgEl); attachZoom(pre, title); }
      });
    }).catch(function (err) {
      blocks.forEach(function (pre) {
        if (!pre.querySelector('svg')) {
          pre.classList.add('mermaid-error');
          pre.textContent = 'Erreur de rendu Mermaid : ' + (err && err.message ? err.message : err);
        }
      });
    });
  }

  /* =========================================================================
     LEAFLET rendering — instantiate one interactive map per .okia-map div.
     The backgrounds are OpenFreeMap's vector styles (positron / dark), drawn by MapLibre
     inside a Leaflet layer; a raster OpenStreetMap base layer is offered too. Everything
     above the background — markers, popups, the layers control, the fullscreen button that
     expands the map to the viewport — is plain Leaflet and does not know the difference.
     ========================================================================= */
  function leafletMarkerIcon() {
    return L.icon({
      iconUrl:       'vendor/images/marker-icon.png',
      iconRetinaUrl: 'vendor/images/marker-icon-2x.png',
      shadowUrl:     'vendor/images/marker-shadow.png',
      iconSize:    [25, 41], iconAnchor: [12, 41],
      popupAnchor: [1, -34], shadowSize: [41, 41]
    });
  }

  function makeFullscreenControl(mapEl) {
    var Ctl = L.Control.extend({
      options: { position: 'topleft' },
      onAdd: function (map) {
        var box = L.DomUtil.create('div', 'leaflet-bar leaflet-control okia-fs-control');
        var a = L.DomUtil.create('a', '', box);
        a.href = '#';
        a.title = 'Plein écran';
        a.setAttribute('role', 'button');
        a.innerHTML = '⛶';
        L.DomEvent.disableClickPropagation(box);
        L.DomEvent.on(a, 'click', function (e) {
          L.DomEvent.preventDefault(e);
          var full = mapEl.classList.toggle('okia-map-fullscreen');
          document.body.classList.toggle('okia-map-has-fullscreen', full);
          a.innerHTML = full ? '✕' : '⛶';
          a.title = full ? 'Quitter le plein écran' : 'Plein écran';
          // Let the layout settle, then tell Leaflet its size changed.
          setTimeout(function () { map.invalidateSize(); }, 60);
        });
        return box;
      }
    });
    return new Ctl();
  }

  // A map whose tiles never arrive is a mute grey rectangle — the reader cannot tell an
  // empty area from a broken app. Offline, the marker labels are the part that still carries
  // meaning, so they are shown as a list rather than thrown away with the map.
  function leafletOfflineFallback(el, cfg) {
    var labels = (cfg.markers || [])
      .map(function (mk) { return mk.label; })
      .filter(function (label) { return !!label; });
    var list = labels.length
      ? '<ul>' + labels.map(function (label) { return '<li>' + escapeHtml(label) + '</li>'; }).join('') + '</ul>'
      : '';
    el.innerHTML = '<div class="okia-map-offline">' +
      '<span class="okia-map-offline-title">' + escapeHtml(TXT('Carte indisponible hors connexion')) + '</span>' +
      list + '</div>';
    el.setAttribute('data-offline', '1');
  }

  // Un fond vectoriel ne peint rien tant qu'il n'a pas tout reçu — style, index des tuiles,
  // sprites, polices, tuiles — puis apparaît d'un coup. Sur un lien lent, cela fait plusieurs
  // secondes de cadre gris que rien n'explique ; un fond raster, lui, se remplit tuile à tuile
  // et se raconte tout seul. D'où cette mention, retirée à la première image dessinée.
  function mapLoadingNote(el) {
    var note = document.createElement('div');
    note.className = 'okia-map-loading';
    note.textContent = TXT('Chargement de la carte…');
    el.appendChild(note);
    return function () { if (note.parentNode) note.parentNode.removeChild(note); };
  }

  function renderLeafletMaps(container) {
    if (typeof L === 'undefined') return;
    var maps = Array.prototype.slice.call(container.querySelectorAll('.okia-map'));
    maps.forEach(function (el) {
      if (el.getAttribute('data-rendered') === '1') return;
      var cfg;
      try { cfg = JSON.parse(b64decode(el.getAttribute('data-okia-map') || '')); }
      catch (e) { cfg = null; }
      if (!cfg) return;
      el.setAttribute('data-rendered', '1');
      el.style.height = cfg.height || '420px';

      // Known offline (fornews.ai ships an airplane-mode case): say so instead of building
      // a map that can only show grey.
      if (typeof navigator !== 'undefined' && navigator.onLine === false) {
        leafletOfflineFallback(el, cfg);
        return;
      }

      var map = L.map(el, {
        // Floor at 1: MapLibre runs one zoom level below Leaflet (its tiles are 512 px), so
        // a Leaflet zoom of 0 asks the GL map for -1 and the background stops drawing. A
        // document map at zoom 0 is a 256 px world thumbnail anyway.
        minZoom: Math.max(1, cfg.minZoom || 1),
        maxZoom: cfg.maxZoom || 19,
        scrollWheelZoom: true
      });
      el._leafletMap = map;   // expose for the slideshow to re-measure on fit/resize

      // The backgrounds come from OpenFreeMap: the very "positron" and "dark" styles CARTO
      // withdrew behind an API key, rebuilt from OpenStreetMap data and served without key,
      // quota or account. Vector tiles, so MapLibre draws them — into one WebGL canvas that
      // the maplibre-gl-leaflet binding parks in Leaflet's tile pane. The rest of this
      // function never learns that the ground under its markers is not a grid of <img>.
      var ofmCredit = '<a href="https://openfreemap.org/">OpenFreeMap</a> · ' +
        '© <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>';
      var osmCredit = '© <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>';

      // OpenFreeMap's styles print every place twice — "Dongola القندى" — by concatenating
      // the latin and non-latin forms of its name. In a report that is noise: the reader gets
      // one name, in the script the rest of the page is written in.
      function latinLabels(gl) {
        try {
          var style = gl.getStyle();
          if (!style || !style.layers) return;
          style.layers.forEach(function (layer) {
            var field = layer.layout && layer.layout['text-field'];
            if (!field || JSON.stringify(field).indexOf('name:nonlatin') < 0) return;
            gl.setLayoutProperty(layer.id, 'text-field',
              ['coalesce', ['get', 'name:latin'], ['get', 'name']]);
          });
        } catch (e) {}
      }

      function vectorStyle(name) {
        return L.maplibreGL({
          style: 'https://tiles.openfreemap.org/styles/' + name,
          // The style's own sources declare no attribution, and the binding reads them to
          // build the credit — so hand it the wording instead of letting it find none.
          attributionControl: { customAttribution: ofmCredit },
          // WebGL clears its drawing buffer once the frame is composited; without this the
          // export reads back an empty rectangle — markers and credit over nothing, which is
          // exactly what the first PDF came out as. MapLibre 5 moved the flag inside
          // canvasContextAttributes, and silently ignores it at the top level.
          canvasContextAttributes: { preserveDrawingBuffer: true }
        });
      }

      // `crossOrigin` is what lets a raster background be rasterised later: without it WebKit
      // taints the canvas as soon as a remote tile is drawn on it, and toDataURL() throws.
      // Verified in a real WKWebView on iOS, from a file:// page.
      //
      // A `tileserver:` of one's own is almost always OSM-derived; crediting the background
      // this map is not showing would be worse than crediting the data most of them carry.
      var attribution = osmCredit;
      var osm = L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
        { maxZoom: 19, crossOrigin: 'anonymous', attribution: osmCredit });

      // WebGL is not a given — an old device, a simulator without a GPU, a build where the
      // vendored MapLibre did not load. MapLibre only fails when the layer is added, which
      // would take the whole map down with it, so the question is asked before that: no
      // WebGL, no vector styles, and the raster OpenStreetMap layer carries the map alone.
      var canVector = typeof L.maplibreGL === 'function' && (function () {
        try {
          var probe = document.createElement('canvas');
          return !!(probe.getContext('webgl2') || probe.getContext('webgl'));
        } catch (e) { return false; }
      })();
      var light = canVector ? vectorStyle('positron') : null;
      var dark = canVector ? vectorStyle('dark') : null;

      var prefersDark = window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches;
      var custom = !!cfg.defaultTiles;
      function customLayer(withCORS) {
        var opts = { maxZoom: 20, attribution: attribution };
        if (withCORS) opts.crossOrigin = 'anonymous';
        return L.tileLayer(cfg.defaultTiles, opts);
      }
      var base = custom ? customLayer(true)
                       : (canVector ? (prefersDark ? dark : light) : osm);

      // Whether this map's tiles can be drawn on a canvas — read at export time to choose
      // between a real image and the marker list.
      el.setAttribute('data-tiles-exportable', '1');

      var tileErrors = 0, anyTileLoaded = false, corsWithdrawn = false;
      var clearLoadingNote = mapLoadingNote(el);

      function drawnAtLast() { anyTileLoaded = true; clearLoadingNote(); }

      // The map is gone for good: say so with the marker labels, which still mean something.
      function giveUp() {
        map.remove();
        el._leafletMap = null;
        el._okiaGL = null;
        leafletOfflineFallback(el, cfg);
      }

      // A vector background has no tile events to count. MapLibre reports `load` once the
      // style is up and the first frame is drawn, and `error` per failed request — including
      // the one that matters, the style itself. A lone failure before that can be transient,
      // so the first one only arms a delay; what decides is whether anything has loaded when
      // it expires.
      function watchVector(layer) {
        var gl = layer.getMaplibreMap();
        if (!gl) return;
        el._okiaGL = gl;    // read at export time to know when the frame is complete
        // « load » n'est pas fiable comme seul signal : selon la fenêtre et le moment,
        // MapLibre peut dessiner sans jamais l'émettre — vérifié en le prenant sur le fait.
        // « idle » complète, et la question décisive — la carte a-t-elle de quoi s'afficher ?
        // — se pose directement au moteur, avant tout basculement.
        gl.on('load', function () { drawnAtLast(); latinLabels(gl); });
        gl.on('idle', function () { drawnAtLast(); latinLabels(gl); });
        gl.on('error', function () {
          if (anyTileLoaded || corsWithdrawn) return;
          if (tileErrors++) return;               // already armed
          setTimeout(function () {
            if (!anyTileLoaded && el._okiaGL === gl) giveUp();
          }, 3000);
        });
      }

      function watchTiles(layer) {
        if (typeof layer.getMaplibreMap === 'function') { watchVector(layer); return; }
        // A raster background can be a group, a custom one a lone layer; the events live on
        // the tile layers, the removal below on the whole background.
        var parts = typeof layer.getLayers === 'function' ? layer.getLayers() : [layer];
        parts.forEach(function (part) {
          part.on('tileload', drawnAtLast);
          part.on('tileerror', function () {
            tileErrors++;

            // A `tileserver:` that sends no CORS header does not merely block the export: with
            // crossOrigin set, the request is refused outright and the map shows nothing. The
            // display always wins — withdraw the option, keep the map, and give up rasterising
            // this one. Two failures rather than one: a lone tile fails at the edge of the world.
            if (custom && !corsWithdrawn && !anyTileLoaded && tileErrors >= 2) {
              corsWithdrawn = true;
              tileErrors = 0;
              el.setAttribute('data-tiles-exportable', '0');
              map.removeLayer(layer);
              var plain = customLayer(false);
              watchTiles(plain);
              plain.addTo(map);
              return;
            }

            // navigator.onLine only reports a link, not reachability: a captive portal or a dead
            // tile CDN still ends in a grey rectangle. A single failed tile means nothing;
            // several with not one loaded is a verdict.
            if (anyTileLoaded || tileErrors < 4) return;
            giveUp();
          });
        });   // parts.forEach
      }

      // Passé ce délai sans une seule image, impossible de savoir si le fond vectoriel finit
      // par arriver ou ne viendra jamais — et le lecteur, lui, n'a qu'un cadre gris. Le fond
      // raster se remplit tuile à tuile : il montre au moins que quelque chose avance. Ne
      // s'applique qu'au fond initial : un fond choisi à la main dans le sélecteur reste
      // celui qu'on a demandé, lent ou pas.
      function fallBackToRasterIfNothingDrawn(layer) {
        setTimeout(function () {
          if (anyTileLoaded || !el._leafletMap || !map.hasLayer(layer)) return;
          // Le style est chargé et ses tuiles sont là : la carte s'affiche, ou s'affichera
          // dans l'instant. La remplacer serait défaire un travail qui a abouti.
          var gl = el._okiaGL;
          try { if (gl && gl.isStyleLoaded() && gl.areTilesLoaded()) return; } catch (e) {}
          map.removeLayer(layer);
          el._okiaGL = null;
          tileErrors = 0;
          watchTiles(osm);
          osm.addTo(map);
        }, 6000);
      }

      watchTiles(base);
      base.addTo(map);
      if (!cfg.defaultTiles && canVector) fallBackToRasterIfNothingDrawn(base);

      if (!cfg.defaultTiles && canVector) {
        L.control.layers({ 'Clair': light, 'Sombre': dark, 'OpenStreetMap': osm },
                         null, { position: 'topright' }).addTo(map);
        // Each background builds its own GL map when it is added, and drops it when it is
        // removed: the export needs the one that is on screen now, not the one built first.
        map.on('baselayerchange', function (e) {
          el._okiaGL = null;
          tileErrors = 0;
          watchTiles(e.layer);
        });
      }

      var icon = leafletMarkerIcon();
      var pts = [];
      // Gardés pour la traduction : un libellé de marqueur vit dans une bulle qui ne
      // s'ouvre qu'au clic, donc il se réécrit sans que la carte bouge d'un pixel.
      el._okiaMarqueurs = [];
      (cfg.markers || []).forEach(function (mk) {
        var marker = L.marker([mk.lat, mk.lng], { icon: icon }).addTo(map);
        if (mk.label) {
          marker.bindPopup('<strong>' + escapeHtml(mk.label) + '</strong>');
          el._okiaMarqueurs.push({ marker: marker, label: mk.label });
        }
        if (mk.link) {
          marker.on('click', function () { post('wikiTapped', { target: mk.link }); });
        }
        pts.push([mk.lat, mk.lng]);
      });

      // View: explicit center/zoom wins; otherwise fit to the markers; else world.
      if (cfg.lat != null && cfg.lng != null && isFinite(cfg.lat) && isFinite(cfg.lng)) {
        map.setView([cfg.lat, cfg.lng], cfg.zoom != null ? cfg.zoom : 5);
      } else if (pts.length === 1) {
        map.setView(pts[0], cfg.zoom != null ? cfg.zoom : 6);
      } else if (pts.length > 1) {
        map.fitBounds(pts, { padding: [40, 40] });
        if (cfg.zoom != null) map.setZoom(cfg.zoom);
      } else {
        map.setView([20, 0], cfg.zoom != null ? cfg.zoom : 2);
      }

      map.addControl(makeFullscreenControl(el));
      setTimeout(function () { map.invalidateSize(); }, 80);
    });
  }

  /* =========================================================================
     POST-PROCESS helpers
     ========================================================================= */
  function dedupeTitle(container, title) {
    var h1s = container.querySelectorAll('h1');
    for (var i = 0; i < h1s.length; i++) {
      if (h1s[i].classList.contains('okia-title')) continue;
      if (h1s[i].textContent.trim().toLowerCase() === title.trim().toLowerCase()) {
        h1s[i].remove();
      }
    }
  }

  // A second image right after the first, in a document that has only those two, is the
  // redundant credit/banner this was written for — the shape of a single article. It used to
  // fire on ANY document with two or more images, which on a briefing of 858 articles simply
  // deleted the second article's photo. Two conditions now hold it back: the document must
  // have exactly two images, and no heading may separate them — a heading means they belong
  // to different sections, so neither is a duplicate of the other.
  function hideRedundantSecondImage(container) {
    var imgs = container.querySelectorAll('.markdown-body img, #content img');
    if (imgs.length !== 2) return;
    var headings = container.querySelectorAll('h1, h2, h3, h4, h5, h6');
    for (var i = 0; i < headings.length; i++) {
      var afterFirst = imgs[0].compareDocumentPosition(headings[i]) & Node.DOCUMENT_POSITION_FOLLOWING;
      var beforeSecond = headings[i].compareDocumentPosition(imgs[1]) & Node.DOCUMENT_POSITION_FOLLOWING;
      if (afterFirst && beforeSecond) return;
    }
    imgs[1].style.display = 'none';
  }

  /* =========================================================================
     ORCHESTRATION
     ========================================================================= */
  // Parsing is linear in document size — measured on this pipeline: ~210 ms per million
  // characters (desktop Safari), 284 ms at 1.4 M and 2 871 ms at 13.5 M. Past this mark the
  // wait is long enough that an empty screen reads as a crash, so it gets a word first.
  // Below it, announcing anything would only add a flash.
  var BIG_DOCUMENT_CHARS = 2000000;

  function render(md, filename) {
    var container = document.getElementById('content');
    if (typeof md === 'string' && md.length > BIG_DOCUMENT_CHARS && container) {
      container.innerHTML = '<div class="okia-rendering">' +
        escapeHtml(TXT('Document volumineux, rendu en cours…')) + '</div>';
      // Yield so the browser can paint the notice before the parse seizes the main thread.
      // setTimeout, never requestAnimationFrame: rAF does not fire while the view is hidden,
      // and a document opened behind a sheet or in a backgrounded app would then never render
      // at all — the very blank screen this is meant to prevent.
      return new Promise(function (resolve, reject) {
        setTimeout(function () { renderDocument(md, filename).then(resolve, reject); }, 16);
      });
    }
    return renderDocument(md, filename);
  }

  function renderDocument(md, filename) {
    var container = document.getElementById('content');
    try {
      var fm = parseFrontmatter(md);
      var meta = fm.meta;
      var body = fm.body;

      var header = buildHeader(meta, body, filename);
      var ner = extractEntities(body);
      var legend = buildLegend(ner.subtypes);

      // 2 → 2b → 3 → 4 (string transforms before parse)
      body = transformMermaid(body);
      body = transformLeaflet(body);

      body = transformCallouts(body);                             // 3
      body = transformWikiLinks(body);                            // 4

      var html = withLazyImages(marked.parse(body, { breaks: true, gfm: true }));
      container.innerHTML = header.headerHtml + legend + html;

      dedupeTitle(container, header.title);                       // remove duplicate H1
      highlightEntities(container, ner.entities, ner.subtypes);   // 6 (DOM-safe)
      hideRedundantSecondImage(container);
      watchImages(container);                                     // 5 drop images that fail
      attachImageZoom(container);                                 // tap image → full-screen
      clearSearch();
      applyFontScale();                                           // keep chosen size across renders
      buildTOC(container);                                        // headings -> ids + TOC
      renderLeafletMaps(container);                               // 2b interactive maps

      post('docMeta', { title: header.title });

      return renderMermaid(container, header.title).then(function () {
        post('rendered', { title: header.title });
      });
    } catch (err) {
      container.innerHTML = '<div class="callout callout-error" style="--callout-color:#ef5350">' +
        '<div class="callout-title"><span class="callout-icon">⛔</span>' +
        TXT('Erreur de rendu') + '</div>' +
        '<div class="callout-content"><pre>' + escapeHtml(String(err && err.stack || err)) +
        '</pre></div></div>';
      post('renderError', { message: String(err && err.message || err) });
      return Promise.reject(err);
    }
  }

  /* =========================================================================
     RENDER FRAGMENT — run the full transform pipeline (mermaid · leaflet ·
     callouts · wiki-links · images) into an arbitrary container. Used by the
     slideshow to render one slide at a time, identical to the reader.
     ========================================================================= */
  function renderFragment(container, md) {
    var body = transformMermaid(md);
    body = transformLeaflet(body);
    body = transformCallouts(body);
    body = transformWikiLinks(body);
    container.innerHTML = withLazyImages(marked.parse(body, { breaks: true, gfm: true }));
    renderLeafletMaps(container);
    watchImages(container);
    attachImageZoom(container);
    return renderMermaid(container, '');
  }

  /* =========================================================================
     FONT SIZE — scale the whole document by adjusting the root font size.
     Most typography is expressed in rem, so it scales proportionally.
     ========================================================================= */
  var BASE_FONT_PX = 17;          // must match :root font-size in style.css
  var currentFontScale = 1;

  function applyFontScale() {
    document.documentElement.style.fontSize = (BASE_FONT_PX * currentFontScale).toFixed(2) + 'px';
  }

  function setFontScale(scale) {
    if (typeof scale === 'number' && isFinite(scale) && scale > 0) {
      currentFontScale = Math.max(0.6, Math.min(2.2, scale));
      applyFontScale();
    }
    return currentFontScale;
  }

  /* =========================================================================
     TABLE OF CONTENTS — assign ids to headings, post the outline to native
     ========================================================================= */
  function slugify(text) {
    return text.toLowerCase()
      .normalize('NFD').replace(/[̀-ͯ]/g, '')
      .replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '') || 'section';
  }

  function buildTOC(container) {
    var heads = container.querySelectorAll('h1, h2, h3, h4, h5, h6');
    var items = [], used = {};
    heads.forEach(function (h) {
      if (h.offsetParent === null && h.getClientRects().length === 0) { /* hidden */ }
      var base = 'h-' + slugify(h.textContent);
      var slug = base;
      while (used[slug]) { used[base] = (used[base] || 1) + 1; slug = base + '-' + used[base]; }
      used[slug] = 1;
      h.id = slug;
      items.push({ id: slug, level: parseInt(h.tagName.slice(1), 10), text: h.textContent.trim() });
    });
    post('toc', { items: items });
  }

  function scrollToHeading(id) {
    var el = document.getElementById(id);
    if (el) el.scrollIntoView({ behavior: 'smooth', block: 'start' });
  }

  /* =========================================================================
     IN-DOCUMENT SEARCH — highlight matches, navigate between them
     ========================================================================= */
  var searchState = { hits: [], idx: -1 };

  function clearSearch() {
    var container = document.getElementById('content');
    if (!container) return;
    container.querySelectorAll('mark.search-hit').forEach(function (m) {
      var parent = m.parentNode;
      parent.replaceChild(document.createTextNode(m.textContent), m);
      parent.normalize();
    });
    searchState = { hits: [], idx: -1 };
  }

  function isSearchable(node) {
    var p = node.parentNode;
    while (p && p !== document.body) {
      var n = p.nodeName;
      if (n === 'SCRIPT' || n === 'STYLE' || n === 'SVG' || n === 'svg') return false;
      if (p.classList && p.classList.contains('mermaid')) return false;
      p = p.parentNode;
    }
    return true;
  }

  function search(query) {
    clearSearch();
    var container = document.getElementById('content');
    if (!container || !query) return { count: 0, index: 0 };
    var needle = query.toLowerCase();
    var walker = document.createTreeWalker(container, NodeFilter.SHOW_TEXT, null);
    var targets = [], node;
    while ((node = walker.nextNode())) {
      if (node.nodeValue.toLowerCase().indexOf(needle) !== -1 && isSearchable(node)) targets.push(node);
    }
    targets.forEach(function (textNode) {
      var text = textNode.nodeValue, low = text.toLowerCase();
      var frag = document.createDocumentFragment(), last = 0, i;
      while ((i = low.indexOf(needle, last)) !== -1) {
        if (i > last) frag.appendChild(document.createTextNode(text.slice(last, i)));
        var mark = document.createElement('mark');
        mark.className = 'search-hit';
        mark.textContent = text.slice(i, i + needle.length);
        frag.appendChild(mark);
        last = i + needle.length;
      }
      if (last < text.length) frag.appendChild(document.createTextNode(text.slice(last)));
      textNode.parentNode.replaceChild(frag, textNode);
    });
    searchState.hits = Array.prototype.slice.call(container.querySelectorAll('mark.search-hit'));
    if (searchState.hits.length) { setCurrent(0); }
    return { count: searchState.hits.length, index: searchState.hits.length ? 1 : 0 };
  }

  function setCurrent(idx) {
    if (!searchState.hits.length) return 0;
    searchState.hits.forEach(function (h) { h.classList.remove('search-current'); });
    searchState.idx = (idx + searchState.hits.length) % searchState.hits.length;
    var cur = searchState.hits[searchState.idx];
    cur.classList.add('search-current');
    cur.scrollIntoView({ behavior: 'smooth', block: 'center' });
    return searchState.idx + 1;
  }

  function searchNext() { return { count: searchState.hits.length, index: setCurrent(searchState.idx + 1) }; }
  function searchPrev() { return { count: searchState.hits.length, index: setCurrent(searchState.idx - 1) }; }

  /* =========================================================================
     EXPORT MODEL — walk a rendered container into an ordered list of blocks
     (headings, paragraphs, quotes, lists, tables, images) for Word/PowerPoint
     export. Mermaid diagrams are rasterised to PNG; remote images are passed by
     URL (downloaded natively); maps become a labelled marker list.
     ========================================================================= */

  function pushRun(out, text, fmt) {
    if (!text) return;
    var last = out[out.length - 1];
    if (last && !!last.bold === !!fmt.bold && !!last.italic === !!fmt.italic && !!last.code === !!fmt.code) {
      last.text += text;
    } else {
      out.push({ text: text, bold: !!fmt.bold, italic: !!fmt.italic, code: !!fmt.code });
    }
  }

  function collectRuns(node, fmt, out) {
    fmt = fmt || {};
    for (var i = 0; i < node.childNodes.length; i++) {
      var c = node.childNodes[i];
      if (c.nodeType === 3) { pushRun(out, c.nodeValue.replace(/\s+/g, ' '), fmt); continue; }
      if (c.nodeType !== 1) continue;
      var tag = c.tagName;
      if (tag === 'IMG' || tag === 'BR') { if (tag === 'BR') pushRun(out, '\n', fmt); continue; }
      var f = { bold: fmt.bold, italic: fmt.italic, code: fmt.code };
      if (tag === 'STRONG' || tag === 'B') f.bold = true;
      if (tag === 'EM' || tag === 'I') f.italic = true;
      if (tag === 'CODE' && node.tagName !== 'PRE') f.code = true;
      collectRuns(c, f, out);
    }
  }
  function runsOf(el) { var o = []; collectRuns(el, {}, o); return o.filter(function (r) { return r.text.trim().length || r.text === '\n'; }); }

  function svgToPng(svg) {
    return new Promise(function (resolve) {
      try {
        var box = svg.getBoundingClientRect();
        var scale = 2;
        var w = Math.max(1, Math.round(box.width)), h = Math.max(1, Math.round(box.height));
        var clone = svg.cloneNode(true);
        clone.setAttribute('width', w); clone.setAttribute('height', h);
        var xml = new XMLSerializer().serializeToString(clone);
        var url = 'data:image/svg+xml;base64,' + b64encode(xml);
        var img = new Image();
        img.onload = function () {
          var cv = document.createElement('canvas');
          cv.width = w * scale; cv.height = h * scale;
          var ctx = cv.getContext('2d');
          ctx.fillStyle = '#FAFAF8'; ctx.fillRect(0, 0, cv.width, cv.height);
          ctx.drawImage(img, 0, 0, cv.width, cv.height);
          try {
            var data = cv.toDataURL('image/png').split(',')[1];
            resolve({ png: data, w: w * scale, h: h * scale });
          } catch (e) { resolve(null); }
        };
        img.onerror = function () { resolve(null); };
        img.src = url;
      } catch (e) { resolve(null); }
    });
  }

  // Wait for the tiles a map has already asked for. Rasterising before they land produces a
  // half-drawn map, which is worse than the marker list it replaces.
  function tilesSettled(el, timeoutMs) {
    return new Promise(function (resolve) {
      var deadline = Date.now() + (timeoutMs || 5000);
      (function poll() {
        // A vector background answers for itself: loaded() is true once the style is up and
        // every visible tile has been drawn into the frame we are about to copy.
        if (el._okiaGL) {
          if (el._okiaGL.loaded() || Date.now() > deadline) return resolve();
          return setTimeout(poll, 150);
        }
        var tiles = el.querySelectorAll('img.leaflet-tile');
        var pending = 0;
        for (var i = 0; i < tiles.length; i++) if (!tiles[i].complete) pending++;
        if ((tiles.length > 0 && pending === 0) || Date.now() > deadline) return resolve();
        setTimeout(poll, 150);
      })();
    });
  }

  // A teardrop pin in the OK-ia orange, tip at (x, y). Drawn rather than blitted — see the
  // note in mapToImage about local images tainting a file:// canvas.
  function drawPin(ctx, x, y, scale) {
    var r = 7 * scale, cy = y - 18 * scale;
    ctx.beginPath();
    ctx.moveTo(x, y);
    ctx.quadraticCurveTo(x - r * 1.45, cy + r * 0.7, x - r, cy);
    ctx.arc(x, cy, r, Math.PI, 0, false);
    ctx.quadraticCurveTo(x + r * 1.45, cy + r * 0.7, x, y);
    ctx.closePath();
    ctx.fillStyle = '#E8972E';
    ctx.fill();
    ctx.lineWidth = 1.5 * scale;
    ctx.strokeStyle = '#FFFFFF';
    ctx.stroke();
    ctx.beginPath();
    ctx.arc(x, cy, r * 0.42, 0, Math.PI * 2);
    ctx.fillStyle = '#FFFFFF';
    ctx.fill();
  }

  // Draw the map that is on screen onto a canvas: its tiles, then its markers, then the
  // attribution the tile licences require.
  //
  // Positions come from getBoundingClientRect() rather than from Leaflet's CSS transforms.
  // Reading `transform: translate3d(…)` by hand means reimplementing the stack of nested
  // panes, the zoom animation and fractional zoom; a rectangle already carries all of it, and
  // stays correct in the off-screen container the .pptx export renders slides into.
  //
  // Returns null whenever anything is off — offline map, tiles withdrawn from CORS, nothing
  // loaded, tainted canvas. The caller then keeps the marker list, which always works.
  function mapToImage(el) {
    if (el.getAttribute('data-offline') === '1') return Promise.resolve(null);
    if (el.getAttribute('data-tiles-exportable') === '0') return Promise.resolve(null);

    return tilesSettled(el).then(function () {
      // A vector background that still has not finished drawing — an off-screen container
      // where nothing composites, a style that never arrived — would copy as an empty
      // rectangle under the pins. The marker list is the better answer.
      if (el._okiaGL && !el._okiaGL.loaded()) return null;
      try {
        var scale = 2;
        var box = el.getBoundingClientRect();
        var w = Math.max(1, Math.round(box.width)), h = Math.max(1, Math.round(box.height));
        var cv = document.createElement('canvas');
        cv.width = w * scale; cv.height = h * scale;
        var ctx = cv.getContext('2d');
        ctx.fillStyle = '#FAFAF8';
        ctx.fillRect(0, 0, cv.width, cv.height);

        function paint(node) {
          var r = node.getBoundingClientRect();
          if (!r.width || !r.height) return false;
          ctx.drawImage(node, (r.left - box.left) * scale, (r.top - box.top) * scale,
                              r.width * scale, r.height * scale);
          return true;
        }

        // Two shapes of background, one rectangle each way: MapLibre hands over a single
        // WebGL canvas, a raster layer a ring of tiles that reaches past the frame. Either
        // way the export canvas clips what falls outside.
        var drawn = 0;
        var glCanvas = el.querySelector('.leaflet-gl-layer canvas');
        if (glCanvas && paint(glCanvas)) drawn++;
        var tiles = el.querySelectorAll('img.leaflet-tile');
        for (var i = 0; i < tiles.length; i++) {
          if (tiles[i].complete && tiles[i].naturalWidth) { if (paint(tiles[i])) drawn++; }
        }
        if (!drawn) return null;

        // The marker pins are DRAWN, not copied from their <img>. Counter-intuitive but
        // verified on iOS: a page served from file:// gets an opaque origin per file, so
        // drawing the bundled marker-icon.png taints the canvas — while the remote map
        // imagery, fetched with CORS, does not. The local image is the unsafe one here.
        var marks = el.querySelectorAll('img.leaflet-marker-icon');
        for (var j = 0; j < marks.length; j++) {
          var mr = marks[j].getBoundingClientRect();
          if (!mr.width) continue;
          // iconAnchor is the tip of the pin: bottom centre of the icon box.
          drawPin(ctx, (mr.left + mr.width / 2 - box.left) * scale,
                       (mr.bottom - box.top) * scale, scale);
        }

        // OpenStreetMap's licence requires attribution wherever the map is shown — a Word
        // document included. Leaflet already composed the wording; reuse it verbatim.
        var attr = el.querySelector('.leaflet-control-attribution');
        var credit = attr ? attr.textContent.trim().replace(/\s+/g, ' ') : '';
        if (credit) {
          var pad = 4 * scale, size = 10 * scale;
          ctx.font = size + 'px -apple-system, BlinkMacSystemFont, sans-serif';
          var tw = ctx.measureText(credit).width, th = size + pad;
          ctx.fillStyle = 'rgba(255,255,255,0.78)';
          ctx.fillRect(cv.width - tw - pad * 2, cv.height - th, tw + pad * 2, th);
          ctx.fillStyle = '#4a4a44';
          ctx.textBaseline = 'bottom';
          ctx.fillText(credit, cv.width - tw - pad, cv.height - pad / 2);
        }

        // JPEG, not PNG: a map is photographic. Measured on one map at this size —
        // PNG 343 KB against JPEG q0.85 95 KB, for no difference the eye can find.
        // Diagrams keep PNG, which is the right codec for line art.
        return { jpeg: cv.toDataURL('image/jpeg', 0.85).split(',')[1], w: cv.width, h: cv.height };
      } catch (e) {
        return null;   // canvas taint or anything unforeseen → the marker list stands
      }
    });
  }

  // Leaflet computes its tile grid for the width it was built at and does not reflow when
  // the print layout hands it another one: on A4 the map printed as a part-covered box,
  // tiles on the left, white on the right. So each map is frozen to the image mapToImage()
  // already knows how to produce, that image is what prints, and the live map is restored
  // afterwards. A map that cannot be rasterised keeps printing as-is — partial beats absent.
  // `break-after: avoid` on a heading is not honoured by WebKit's paginator — the heading
  // stayed at the foot of the page while its diagram moved to the next one. Wrapping the
  // heading together with the block it introduces works, because `break-inside: avoid` on a
  // container IS honoured. Undone by unfreezeMaps().
  function keepHeadingsWithContent() {
    var heads = Array.prototype.slice.call(
      document.querySelectorAll('#content h1, #content h2, #content h3, #content h4'));
    heads.forEach(function (h) {
      var next = h.nextElementSibling;
      if (!next || h.parentNode.classList.contains('okia-keep')) return;
      var wrap = document.createElement('div');
      wrap.className = 'okia-keep';
      h.parentNode.insertBefore(wrap, h);
      wrap.appendChild(h);
      wrap.appendChild(next);
    });
  }

  function unwrapHeadings() {
    Array.prototype.slice.call(document.querySelectorAll('.okia-keep')).forEach(function (wrap) {
      while (wrap.firstChild) wrap.parentNode.insertBefore(wrap.firstChild, wrap);
      wrap.parentNode.removeChild(wrap);
    });
  }

  // Une image en loading="lazy" n'est chargée qu'à l'approche de l'écran — c'est ce qui
  // rend l'affichage immédiat. Mais l'impression rend le document d'un coup : celles qu'on
  // n'a jamais atteintes en scrollant n'ont aucune donnée et laissent un blanc sous leur
  // légende. Avant de dessiner le PDF, on les force donc à se charger, et on attend.
  function loadAllImagesForPrint(timeoutMs) {
    var imgs = Array.prototype.slice.call(document.querySelectorAll('#content img'));
    var pending = imgs.filter(function (img) { return !img.complete || !img.naturalWidth; });
    if (!pending.length) return Promise.resolve(0);

    pending.forEach(function (img) {
      img.setAttribute('data-okia-lazy', img.getAttribute('loading') || '');
      img.setAttribute('loading', 'eager');
      var src = img.getAttribute('src');
      if (src) img.setAttribute('src', src);   // relance ce que le paresseux avait différé
    });

    var tous = Promise.all(pending.map(function (img) {
      return new Promise(function (res) {
        if (img.complete) return res();
        img.addEventListener('load', function () { res(); }, { once: true });
        img.addEventListener('error', function () { res(); }, { once: true });
      });
    }));
    // Un réseau lent ne doit pas retenir l'export indéfiniment : ce qui manque manquera.
    var delai = new Promise(function (res) { setTimeout(res, timeoutMs || 12000); });
    return Promise.race([tous, delai]).then(function () { return pending.length; });
  }

  function restoreLazyImages() {
    Array.prototype.slice.call(document.querySelectorAll('#content img[data-okia-lazy]'))
      .forEach(function (img) {
        var avant = img.getAttribute('data-okia-lazy');
        if (avant) img.setAttribute('loading', avant); else img.removeAttribute('loading');
        img.removeAttribute('data-okia-lazy');
      });
  }

  function freezeMapsForPrint() {
    keepHeadingsWithContent();
    var maps = Array.prototype.slice.call(document.querySelectorAll('.okia-map'));
    return Promise.all(maps.map(function (el) {
      return mapToImage(el).then(function (res) {
        if (!res) return;
        var img = document.createElement('img');
        img.className = 'okia-map-print';
        img.src = 'data:image/jpeg;base64,' + res.jpeg;
        el.parentNode.insertBefore(img, el.nextSibling);
        // The image must be DECODED before the map is hidden: an <img> that has not been
        // decoded yet lays out at zero height, and the paginator would leave a blank where
        // the map should be — which is exactly the defect this replaces.
        var ready = img.decode ? img.decode().catch(function () {}) : Promise.resolve();
        return ready.then(function () { el.classList.add('okia-map-frozen'); });
      });
    })).then(function () {
      return loadAllImagesForPrint();
    }).then(function () {
      return document.querySelectorAll('.okia-map-print').length;
    });
  }

  // Le moteur d'impression d'iOS ignore break-inside/break-after: avoid (mesuré). Il
  // honore en revanche le saut de page explicite : l'export produit donc un premier PDF,
  // repère les titres restés seuls en bas de page, les marque ici, et recommence.
  // Les titres du document, avec leur id. L'export s'en sert pour reconnaître un titre
  // resté seul en bas d'une page. Lu à la demande plutôt que reçu par message : un export
  // ne doit pas dépendre d'un sommaire arrivé, ou non, plus tôt.
  function headings() {
    return Array.prototype.slice.call(
      document.querySelectorAll('#content h1, #content h2, #content h3, #content h4'))
      .filter(function (h) { return h.id; })
      .map(function (h) { return { id: h.id, text: h.textContent.trim() }; });
  }

  function markBreakBefore(ids) {
    var content = document.getElementById('content');
    (ids || []).forEach(function (id) {
      var el = document.getElementById(id);
      if (!el) return;
      // Le saut doit porter sur l'enfant DIRECT de #content : demandé sur un élément
      // imbriqué (dans le conteneur .okia-keep par exemple), il est ignoré.
      while (el.parentNode && el.parentNode !== content) el = el.parentNode;
      el.classList.add('okia-break-before');
    });
    return document.querySelectorAll('.okia-break-before').length;
  }

  function clearBreakBefore() {
    Array.prototype.slice.call(document.querySelectorAll('.okia-break-before'))
      .forEach(function (el) { el.classList.remove('okia-break-before'); });
  }

  function unfreezeMaps() {
    unwrapHeadings();
    clearBreakBefore();
    restoreLazyImages();
    var imgs = Array.prototype.slice.call(document.querySelectorAll('.okia-map-print'));
    imgs.forEach(function (img) { img.parentNode.removeChild(img); });
    Array.prototype.slice.call(document.querySelectorAll('.okia-map-frozen'))
      .forEach(function (el) { el.classList.remove('okia-map-frozen'); });
    return imgs.length;
  }

  function mapMarkers(el) {
    try {
      var cfg = JSON.parse(b64decode(el.getAttribute('data-okia-map') || ''));
      return (cfg.markers || []).map(function (m) { return m.label || m.link || (m.lat + ',' + m.lng); });
    } catch (e) { return []; }
  }

  function tableModel(table) {
    var rows = [];
    table.querySelectorAll('tr').forEach(function (tr) {
      var cells = [];
      tr.querySelectorAll('th,td').forEach(function (cell) { cells.push(runsOf(cell)); });
      if (cells.length) rows.push(cells);
    });
    return rows;
  }

  // Returns a Promise of an array of block objects.
  function exportModel(container) {
    var tasks = [];     // async image tasks
    var blocks = [];
    var kids = Array.prototype.slice.call(container.children);

    kids.forEach(function (el) {
      var tag = el.tagName;
      if (el.classList && el.classList.contains('okia-meta')) return;
      if (el.classList && el.classList.contains('ner-legend')) return;
      if (el.classList && el.classList.contains('okia-title')) return;   // passed as doc title
      if (/^H[1-6]$/.test(tag)) {
        blocks.push({ t: 'heading', level: parseInt(tag[1], 10), runs: runsOf(el) });
      } else if (tag === 'P') {
        var img = el.querySelector('img');
        if (img) {
          blocks.push({ t: 'image', src: img.currentSrc || img.src, w: img.naturalWidth, h: img.naturalHeight, caption: [] });
        } else {
          var r = runsOf(el); if (r.length) blocks.push({ t: 'paragraph', runs: r });
        }
      } else if (tag === 'UL' || tag === 'OL') {
        var items = [];
        Array.prototype.slice.call(el.children).forEach(function (li) { if (li.tagName === 'LI') items.push(runsOf(li)); });
        if (items.length) blocks.push({ t: 'list', ordered: tag === 'OL', items: items });
      } else if (tag === 'BLOCKQUOTE') {
        blocks.push({ t: 'quote', runs: runsOf(el) });
      } else if (tag === 'TABLE') {
        blocks.push({ t: 'table', rows: tableModel(el) });
      } else if (tag === 'IMG') {
        blocks.push({ t: 'image', src: el.currentSrc || el.src, w: el.naturalWidth, h: el.naturalHeight, caption: [] });
      } else if (tag === 'PRE' && el.classList.contains('mermaid')) {
        var svg = el.querySelector('svg');
        if (svg) {
          var block = { t: 'image', png: null, w: 0, h: 0, caption: [] };
          blocks.push(block);
          tasks.push(svgToPng(svg).then(function (res) { if (res) { block.png = res.png; block.w = res.w; block.h = res.h; } }));
        }
      } else if (el.classList && el.classList.contains('okia-map')) {
        // Start as the marker list — the form that always works — and upgrade to a real
        // image only if the rasterisation actually succeeds.
        var mapBlock = { t: 'map', markers: mapMarkers(el) };
        blocks.push(mapBlock);
        tasks.push(mapToImage(el).then(function (res) {
          if (!res) return;
          var names = mapBlock.markers || [];
          mapBlock.t = 'image';
          mapBlock.jpeg = res.jpeg;
          mapBlock.w = res.w;
          mapBlock.h = res.h;
          // The place names carry information the picture does not spell out; keep them as
          // the caption rather than losing them with the marker list.
          mapBlock.caption = names.length
            ? [{ text: '🗺 ' + names.join(' · '), italic: true }]
            : [];
        }));
      } else if (el.classList && el.classList.contains('callout')) {
        var titleEl = el.querySelector('.callout-title');
        var contentEl = el.querySelector('.callout-content');
        var runs = [];
        if (titleEl) { var tr = runsOf(titleEl); tr.forEach(function (x) { x.bold = true; }); runs = runs.concat(tr); runs.push({ text: ' — ', bold: false }); }
        if (contentEl) runs = runs.concat(runsOf(contentEl));
        if (runs.length) blocks.push({ t: 'quote', runs: runs });
      }
    });

    return Promise.all(tasks).then(function () {
      // drop images that failed to rasterise and have no src
      return blocks.filter(function (b) { return b.t !== 'image' || b.png || b.jpeg || b.src; });
    });
  }

  // Render into #content WITHOUT the document header (title + meta bar), then bring the last
  // question into view. Used by the document chat: the sheet already carries the title, so an
  // H1 would waste the top of every conversation, and after each new turn the reader wants to
  // land on the exchange that just appeared rather than back at the beginning.
  function renderPlain(md) {
    var container = document.getElementById('content');
    if (!container) return Promise.resolve();
    clearSearch();
    return renderFragment(container, md).then(function () {
      applyFontScale();
      var questions = container.querySelectorAll('.callout-question');
      if (questions.length > 1) {
        questions[questions.length - 1].scrollIntoView({ block: 'start' });
      }
      post('rendered', {});
    });
  }

  /* =========================================================================
     TRADUCTION — collecte des blocs et réécriture en place.

     Le principe tient en une phrase : on ne reconstruit jamais de HTML. Chaque
     nœud de texte du document est un morceau numéroté ; la traduction revient
     morceau par morceau et se réécrit à sa place exacte. L'arbre n'est pas
     touché, donc rien de ce qui vit dedans ne se perd — ni le gras, ni les
     liens, ni les images, ni les diagrammes.

     Le détour par une chaîne Markdown, lui, ne survivrait pas : mesuré au banc
     (`tools/TranslationBench`), traduire le texte brut retourne la cible d'un
     [[wiki-lien]] en allemand, renomme un identifiant entre accents graves,
     change la casse de `flowchart TD` et mange l'indentation. C'est l'arbre
     qu'il faut traduire, pas la chaîne.

     Ce qui se lit mais ne se traduit pas est signalé `protege` et transmis
     quand même : le modèle a besoin de la phrase entière pour bien traduire ce
     qui l'entoure, et il rend ces morceaux intacts.
     ========================================================================= */

  // Conteneurs dont le texte n'est pas de la prose. Le code et les diagrammes parlent
  // une langue qui n'est celle de personne.
  function trZoneExclue(el) {
    while (el && el.nodeName !== 'BODY') {
      var n = el.nodeName;
      if (n === 'PRE' || n === 'SCRIPT' || n === 'STYLE' || n === 'SVG' || n === 'svg') return true;
      if (el.classList && (el.classList.contains('mermaid') ||
                           el.classList.contains('okia-map') ||
                           el.classList.contains('ner-legend'))) return true;
      el = el.parentNode;
    }
    return false;
  }

  // Ce qui se lit sans se traduire. Une cible de wiki-lien traduite casse le coffre,
  // un nom d'entité traduit casse la coloration, une URL traduite casse le lien.
  var TR_URL_RE = /^\s*(?:https?:\/\/|www\.|mailto:)\S+\s*$/i;

  function trProtege(node) {
    var p = node.parentNode;
    if (!p) return true;
    var n = p.nodeName;
    if (n === 'CODE' || n === 'KBD' || n === 'SAMP' || n === 'VAR') return true;
    if (p.classList && (p.classList.contains('wiki-link') ||
                        p.classList.contains('ner-tag'))) return true;
    return TR_URL_RE.test(node.nodeValue);
  }

  // Le bloc d'un nœud : son plus proche ancêtre qui se lit d'un seul tenant. C'est
  // l'unité de traduction — une phrase coupée en deux requêtes se traduit deux fois
  // moins bien — et l'unité d'animation.
  var TR_BLOC_RE = /^(P|LI|H1|H2|H3|H4|H5|H6|TD|TH|DT|DD|FIGCAPTION|CAPTION|BLOCKQUOTE|DIV)$/;

  function trBlocDe(node, racine) {
    var el = node.parentNode;
    while (el && el !== racine) {
      if (el.nodeType === 1 && TR_BLOC_RE.test(el.nodeName)) return el;
      el = el.parentNode;
    }
    return racine;
  }

  /* Les retours à la ligne de rédaction, et pourquoi il faut les effacer avant de traduire.

     `breaks: true` rend chaque retour à la ligne du fichier source par un <br>. Or dans un
     Markdown écrit à la main, une phrase court souvent sur deux ou trois lignes : ces <br>
     ne portent aucun sens, ils viennent de la largeur de l'éditeur.

     Le modèle, lui, voit alors trois morceaux au lieu d'une phrase, et il traduit chacun
     pour lui-même. « wie es das | Gemeindegesetz vorschreibt » revenait en « conformément
     à l'article 3 la | de loi communale » : deux moitiés qui ne se rejoignent pas. Ce
     n'est pas un problème de mise en page — c'est la traduction elle-même qui est fausse.

     On efface donc ces coupures et l'on recolle les nœuds AVANT la collecte : le modèle
     reçoit la phrase entière. Le retour à l'original les remet, avec le <br> d'origine à
     l'endroit exact où il était.

     Un <br> voulu — une adresse, une strophe — n'est pas touché : ses lignes sont courtes
     et se terminent proprement. C'est une règle grossière, mais elle ne se trompe que
     dans un sens : au pire elle laisse une coupure, elle n'en invente jamais. */
  var TR_LIGNE_REDACTION = 60;   // en deçà, la ligne est probablement voulue
  var TR_FINS_DE_PHRASE = '.!?:;…»)]}';

  function trBrDeRedaction(bloc) {
    var res = [], courant = '';
    var enfants = Array.prototype.slice.call(bloc.childNodes);
    for (var i = 0; i < enfants.length; i++) {
      var n = enfants[i];
      if (n.nodeType === 1 && n.nodeName === 'BR') {
        var t = courant.replace(/\s+$/, '');
        if (t.length >= TR_LIGNE_REDACTION &&
            TR_FINS_DE_PHRASE.indexOf(t.slice(-1)) === -1) {
          res.push(n);
        }
        courant = '';
      } else {
        courant += (n.textContent || '');
      }
    }
    return res;
  }

  /* Efface les coupures de rédaction et recolle les nœuds de texte qu'elles séparaient.
     Rend de quoi tout remettre en place. */
  function trAplanir(bloc) {
    var brs = trBrDeRedaction(bloc);
    if (!brs.length) return null;
    var ops = [];
    // Du dernier au premier : fusionner en avançant décalerait les suivants.
    for (var i = brs.length - 1; i >= 0; i--) {
      var br = brs[i];
      var avant = br.previousSibling, apres = br.nextSibling;
      if (!avant || avant.nodeType !== 3 || !apres || apres.nodeType !== 3) continue;
      var coupure = avant.nodeValue.length;
      bloc.removeChild(br);
      avant.nodeValue = avant.nodeValue + ' ' + apres.nodeValue;
      bloc.removeChild(apres);
      ops.push({ noeud: avant, coupure: coupure, br: br });
    }
    return ops.length ? ops : null;
  }

  /* Remet les coupures là où elles étaient. Appliqué après avoir rendu les textes
     d'origine, il redonne le bloc au caractère près. */
  function trDeplier(ops) {
    if (!ops) return;
    for (var i = 0; i < ops.length; i++) {
      var op = ops[i], n = op.noeud;
      if (!n.parentNode) continue;
      var texte = n.nodeValue;
      if (texte.length < op.coupure) continue;
      var suite = texte.slice(op.coupure + 1);   // l'espace posé à la fusion
      n.nodeValue = texte.slice(0, op.coupure);
      var neuf = document.createTextNode(suite);
      n.parentNode.insertBefore(neuf, n.nextSibling);
      n.parentNode.insertBefore(op.br, neuf);
    }
  }

  var trEtat = { blocs: [], actif: false, derniereAnimation: 0, racine: null };

  /* Les deux sens de la traduction, texte à texte. Les nœuds mémorisés suffisent tant
     que personne n'y touche — mais une recherche remplace les nœuds trouvés par un
     <mark> et des nœuds neufs, et nos références deviennent des orphelins. Écrire dedans
     ne fait rien de visible, et le bloc se retrouve moitié dans une langue, moitié dans
     l'autre. Ces tables sont le filet : elles ne dépendent d'aucun nœud. */
  var trTables = { versTraduit: {}, versOriginal: {} };

  /* Cadence minimale entre deux fondus. Elle ne freine que l'animation, jamais la
     disponibilité du texte : un bloc qui arrive trop vite après le précédent est écrit
     immédiatement, simplement sans fondu. Rien n'attend un décompte cosmétique.

     En pratique le modèle rend un bloc par seconde environ — mesuré au banc, 171
     caractères par seconde — donc ce garde-fou ne sert que pour une rafale de blocs
     courts : une ligne de tableau, une suite de titres. */
  var TR_CADENCE_MS = 50;

  /* Numérote les blocs et rend la liste de ce qu'il y a à traduire, dans l'ordre du
     document. `haut` sert à ordonner la vague depuis le premier bloc visible, et
     `signes` à mesurer l'avancement en caractères plutôt qu'en blocs — un titre et un
     paragraphe de trente lignes ne pèsent pas pareil. */
  function trCollecter(racine, garderTables) {
    // Le lecteur travaille sur #content ; le diaporama sur la diapositive courante, et
    // l'export sur un conteneur hors écran. Le mécanisme est le même, seule la racine
    // change.
    var container = racine || document.getElementById('content');
    if (!garderTables) trTables = { versTraduit: {}, versOriginal: {} };
    trEtat = { blocs: [], actif: false, derniereAnimation: 0, racine: container };
    if (!container) return [];

    // Une traduction en place doit être défaite AVANT de recollecter, sinon les textes
    // traduits deviendraient les « originaux » et l'original vrai serait perdu — le
    // retour en arrière ne rendrait plus rien.
    if (trEtat.actif) trRestaurer();

    // Une recherche en cours a remplacé des nœuds de texte par des <mark> : nos
    // références seraient périmées avant d'avoir servi. (Le diaporama n'a pas de
    // recherche ; l'appel est sans effet là-bas.)
    clearSearch();
    container.querySelectorAll('[data-okia-tr]').forEach(function (el) {
      el.removeAttribute('data-okia-tr');
      el.removeAttribute('data-okia-tr-fait');
    });

    // Les coupures de rédaction s'effacent AVANT la collecte : le modèle doit recevoir
    // des phrases entières, pas des tronçons de ligne.
    var aplanis = [];
    container.querySelectorAll('p, li, td, th, dd, figcaption, blockquote').forEach(function (el) {
      var ops = trAplanir(el);
      if (ops) aplanis.push({ el: el, ops: ops });
    });

    var walker = document.createTreeWalker(container, NodeFilter.SHOW_TEXT, null);
    var bruts = [], node;
    while ((node = walker.nextNode())) {
      if (!node.nodeValue || !/\S/.test(node.nodeValue)) continue;
      if (trZoneExclue(node.parentNode)) continue;
      var bloc = trBlocDe(node, container);
      var rang = bloc.__okiaTrRang;
      if (rang === undefined) {
        rang = bruts.length;
        bloc.__okiaTrRang = rang;
        bruts.push({ el: bloc, noeuds: [], protege: [], originaux: [] });
      }
      bruts[rang].noeuds.push(node);
      bruts[rang].protege.push(trProtege(node));
      bruts[rang].originaux.push(node.nodeValue);
    }
    bruts.forEach(function (b) { delete b.el.__okiaTrRang; });

    // Un bloc entièrement protégé — une ligne de code, un nom d'entité seul — n'a rien
    // à faire dans la file : il coûterait une requête pour se rendre inchangé.
    trEtat.blocs = bruts.filter(function (b) { return b.protege.indexOf(false) !== -1; });
    trEtat.aplanis = aplanis;

    return trEtat.blocs.map(function (b, i) {
      b.el.setAttribute('data-okia-tr', String(i));
      // L'ordre d'origine, pour pouvoir le rendre : chaque enfant et le voisin devant
      // lequel il se tenait.
      b.ordre = Array.prototype.slice.call(b.el.childNodes).map(function (n) {
        return { noeud: n, suivant: n.nextSibling };
      });
      var rect = b.el.getBoundingClientRect();
      var parts = [];
      for (var j = 0; j < b.noeuds.length; j++) {
        parts.push({ i: j, texte: b.originaux[j], protege: b.protege[j] });
      }
      return {
        id: i,
        haut: Math.round(rect.top + (window.scrollY || 0)),
        signes: b.originaux.join('').length,
        parts: parts
      };
    });
  }

  /* L'unité d'un nœud : son plus haut ancêtre encore à l'intérieur du bloc. Pour un mot
     en gras c'est le <strong>, pour un libellé de lien c'est le <a>. C'est ce qu'on
     déplace — jamais ce qu'on recrée. */
  function trUnite(noeud, bloc) {
    var el = noeud;
    while (el.parentNode && el.parentNode !== bloc) el = el.parentNode;
    return el.parentNode === bloc ? el : null;
  }

  /* Les <br> découpent le bloc en segments qui se lisent séparément : `breaks: true`
     rend chaque retour à la ligne du Markdown, et deux phrases ainsi séparées ne doivent
     jamais échanger leurs morceaux. On réordonne à l'intérieur d'un segment, pas au
     travers. */
  function trSegments(bloc) {
    var segments = [], courant = [];
    var enfants = Array.prototype.slice.call(bloc.childNodes);
    for (var i = 0; i < enfants.length; i++) {
      if (enfants[i].nodeType === 1 && enfants[i].nodeName === 'BR') {
        segments.push(courant); courant = [];
      } else {
        courant.push(enfants[i]);
      }
    }
    segments.push(courant);
    return segments;
  }

  /* Remet les unités dans l'ordre du texte traduit.

     C'est la pièce qui manquait, et elle ne se voyait qu'à l'écran : « Tout est publié
     sur [le site communal]. » devient « Alles wird auf der Gemeindeseite veröffentlicht. »
     — l'allemand rejette le participe à la fin. Les morceaux reviennent chacun juste, mais
     l'ordre des nœuds du DOM est celui du français : replacer chaque morceau chez lui
     rendait « Alles wird auf veröffentlicht der Gemeindeseite. » Chaque mot correct, la
     phrase fausse.

     On ne recrée rien : le <a> et le <strong> sont les mêmes objets, ils changent de
     place. Un segment qui contient autre chose que du texte collecté — une image, une
     puce dessinée — n'est pas réordonné : mieux vaut un ordre d'origine lisible qu'un
     déplacement qui emporterait ce qu'on ne sait pas lire. */
  function trReordonner(b, sequence) {
    var bloc = b.el;
    var uniteDe = [];
    for (var j = 0; j < b.noeuds.length; j++) uniteDe[j] = trUnite(b.noeuds[j], bloc);

    trSegments(bloc).forEach(function (segment) {
      // Les nœuds blancs entre deux éléments ne portent pas de sens : ils ne bloquent pas.
      var utiles = segment.filter(function (n) {
        return !(n.nodeType === 3 && !/\S/.test(n.nodeValue));
      });
      if (utiles.length < 2) return;

      // Chaque unité du segment doit être connue, sinon on ne touche à rien.
      var connues = utiles.every(function (u) { return uniteDe.indexOf(u) !== -1; });
      if (!connues) return;

      var voulu = [];
      for (var k = 0; k < sequence.length; k++) {
        var u = uniteDe[sequence[k].i];
        if (u && utiles.indexOf(u) !== -1 && voulu.indexOf(u) === -1) voulu.push(u);
      }
      if (voulu.length !== utiles.length) return;

      var identique = voulu.every(function (u, i) { return u === utiles[i]; });
      if (identique) return;

      // Réinsérer avant ce qui suit le segment : le <br> reste où il est.
      var ancre = utiles[utiles.length - 1].nextSibling;
      voulu.forEach(function (u) { bloc.insertBefore(u, ancre); });
    });
  }

  /* Le calque de transition, à l'échelle du bloc.

     Trois temps : cloner le bloc et poser le clone exactement par-dessus ; écrire la
     traduction dans le bloc réel, sous le clone, que le lecteur ne voit donc pas
     changer ; animer la hauteur vers sa nouvelle valeur et effacer le clone en fondu.
     Le changement de longueur est absorbé par une transition au lieu d'un saut.

     `aria-hidden` sur le clone, sans quoi un lecteur d'écran lirait tout en double. */
  function trAnimer(bloc, ecrire) {
    // Un lecteur qui a demandé moins d'animations n'en veut pas non plus ici.
    var sobre = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
    if (sobre || !bloc.getBoundingClientRect) { ecrire(); return; }

    var rect = bloc.getBoundingClientRect();
    var hauteurAvant = rect.height;

    var clone = bloc.cloneNode(true);
    clone.className = (clone.className ? clone.className + ' ' : '') + 'okia-tr-clone';
    clone.setAttribute('aria-hidden', 'true');
    clone.removeAttribute('id');
    clone.removeAttribute('data-okia-tr');
    clone.style.left = (bloc.offsetLeft) + 'px';
    clone.style.top = (bloc.offsetTop) + 'px';
    clone.style.width = rect.width + 'px';
    clone.style.height = hauteurAvant + 'px';
    var hote = bloc.offsetParent || bloc.parentNode;
    hote.appendChild(clone);

    ecrire();

    // Mesurer la nouvelle hauteur sans la montrer : on fige l'ancienne, on lit la
    // nouvelle, puis on laisse la transition faire le chemin.
    bloc.setAttribute('data-okia-tr-anime', '1');
    bloc.style.height = hauteurAvant + 'px';
    var hauteurApres = bloc.scrollHeight;
    // Forcer un reflow, sinon le navigateur groupe les deux hauteurs et rien ne bouge.
    void bloc.offsetHeight;
    bloc.style.height = hauteurApres + 'px';
    clone.classList.add('okia-tr-clone-parti');

    window.setTimeout(function () {
      bloc.style.height = '';
      bloc.removeAttribute('data-okia-tr-anime');
      if (clone.parentNode) clone.parentNode.removeChild(clone);
    }, 240);
  }

  /* Réécrit un bloc. `sequence` arrive dans l'ordre du texte traduit, pas dans celui du
     document. Les morceaux protégés y figurent — c'est ainsi qu'on sait où ils ont
     atterri — mais leur texte n'est jamais réécrit : ils sont revenus intacts ou ils sont
     revenus faux, et dans les deux cas l'original est la bonne valeur. */
  function trAppliquer(id, sequence, reordonner, anime) {
    var b = trEtat.blocs[id];
    if (!b || !sequence) return false;
    var ecrire = function () {
      for (var k = 0; k < sequence.length; k++) {
        var j = sequence[k].i;
        if (typeof j !== 'number' || j < 0 || j >= b.noeuds.length) continue;
        if (b.protege[j]) continue;
        b.noeuds[j].nodeValue = String(sequence[k].texte);
      }
      // `reordonner` vaut faux quand un nœud a reçu du texte à deux endroits de la
      // phrase : le DOM ne sait pas le représenter, et l'ordre du français reste alors
      // le moins mauvais — entier, quoique dans la syntaxe de départ.
      if (reordonner !== false) trReordonner(b, sequence);
    };
    var r = b.el.getBoundingClientRect();
    var visible = r.bottom > 0 && r.top < (window.innerHeight || 0);

    if (anime === false || !visible) {
      // Hors de l'écran, l'animation ne dit rien à personne — et au-dessus, elle ferait
      // pire : un bloc qui grandit là pousse tout le reste et le lecteur perd sa ligne.
      // La reprise silencieuse de ce qui précède l'écran est exactement ce cas. On écrit
      // d'un coup et on rend au lecteur les pixels que le texte vient de lui prendre.
      var hautAvant = b.el.getBoundingClientRect().height;
      ecrire();
      var auDessus = b.el.getBoundingClientRect().bottom <= 0;
      var delta = b.el.getBoundingClientRect().height - hautAvant;
      if (auDessus && Math.abs(delta) > 0.5) window.scrollBy(0, delta);
    } else if (Date.now() - trEtat.derniereAnimation < TR_CADENCE_MS) {
      ecrire();
    } else {
      trEtat.derniereAnimation = Date.now();
      trAnimer(b.el, ecrire);
    }
    // Mémorisé pour la bascule : revenir à la traduction ne doit rien recalculer, la
    // traduction a déjà coûté ses secondes.
    b.traduit = { sequence: sequence, reordonner: reordonner !== false };
    for (var m = 0; m < sequence.length; m++) {
      var idx = sequence[m].i;
      if (typeof idx !== 'number' || idx < 0 || idx >= b.originaux.length) continue;
      if (b.protege[idx]) continue;
      trTables.versTraduit[b.originaux[idx]] = String(sequence[m].texte);
      trTables.versOriginal[String(sequence[m].texte)] = b.originaux[idx];
    }
    b.el.setAttribute('data-okia-tr-fait', '1');
    trEtat.actif = true;
    return true;
  }

  /* Bascule entre l'original et la traduction. C'est la contrepartie d'une traduction
     automatique annoncée : l'original reste à un geste, et le geste est instantané —
     les deux versions sont là, rien n'est refait. */
  function trBasculer(traduit) {
    // Les nœuds ont-ils survécu depuis la collecte ? Une recherche en remplace, et
    // écrire dans un orphelin ne fait rien de visible — le bloc resterait à moitié
    // traduit. Dans ce cas on passe par les tables, qui ne dépendent d'aucun nœud.
    if (!trNoeudsIntacts()) {
      var container = trEtat.racine || document.getElementById('content');
      // `clearSearch` refusionne les nœuds qu'elle avait coupés : les textes redeviennent
      // entiers, donc reconnaissables dans la table.
      clearSearch();
      trReecrireParTable(container,
                         traduit ? trTables.versTraduit : trTables.versOriginal,
                         !!traduit);
      trEtat.actif = !!traduit;
      return trEtat.actif;
    }
    if (traduit) {
      // Les coupures de rédaction sont revenues avec l'original : il faut les effacer de
      // nouveau, sinon les nœuds mémorisés ne portent plus que la première moitié de leur
      // texte et la traduction s'écrirait dans un fragment. Refusionner rend aux
      // références leur validité, puisque la fusion se fait dans le nœud de gauche.
      if (!trEtat.aplanis || !trEtat.aplanis.length) {
        var repris = [];
        trEtat.blocs.forEach(function (b) {
          var ops = trAplanir(b.el);
          if (ops) repris.push({ el: b.el, ops: ops });
        });
        trEtat.aplanis = repris;
      }
      trEtat.blocs.forEach(function (b, i) {
        if (b.traduit) trAppliquer(i, b.traduit.sequence, b.traduit.reordonner, false);
      });
      trEtat.actif = true;
    } else if (trEtat.actif) {
      trRestaurer();
    }
    return trEtat.actif;
  }

  /* Réécrit par la table, sans recollecter. Recollecter remplacerait `trEtat` et
     jetterait ce que chaque bloc sait de sa propre traduction — la bascule suivante
     n'aurait plus rien à reposer. On se contente donc de parcourir les nœuds vivants. */
  function trReecrireParTable(container, table, marquer) {
    if (!container || !table) return 0;
    var walker = document.createTreeWalker(container, NodeFilter.SHOW_TEXT, null);
    var cibles = [], node;
    while ((node = walker.nextNode())) {
      if (!node.nodeValue || !/\S/.test(node.nodeValue)) continue;
      if (trZoneExclue(node.parentNode)) continue;
      if (Object.prototype.hasOwnProperty.call(table, node.nodeValue)) cibles.push(node);
    }
    cibles.forEach(function (n) {
      n.nodeValue = table[n.nodeValue];
      // La marque suit le texte : un bloc revenu à l'original n'est plus « traduit », et
      // c'est elle que le style et les tests regardent.
      var bloc = n.parentNode;
      while (bloc && bloc !== container && !(bloc.getAttribute && bloc.getAttribute('data-okia-tr'))) {
        bloc = bloc.parentNode;
      }
      if (bloc && bloc.setAttribute) {
        if (marquer) bloc.setAttribute('data-okia-tr-fait', '1');
        else bloc.removeAttribute('data-okia-tr-fait');
      }
    });
    return cibles.length;
  }

  /* Vrai tant que chaque nœud collecté est encore dans le document. */
  function trNoeudsIntacts() {
    for (var i = 0; i < trEtat.blocs.length; i++) {
      var noeuds = trEtat.blocs[i].noeuds;
      for (var j = 0; j < noeuds.length; j++) {
        if (!noeuds[j].isConnected) return false;
      }
    }
    return true;
  }

  /* L'original reste à un geste : c'est la contrepartie d'une traduction automatique
     annoncée. Rien n'est recalculé, les textes d'origine n'ont jamais quitté la page. */
  function trRestaurer() {
    if (!trNoeudsIntacts()) return trBasculer(false) ? 0 : trEtat.blocs.length;
    trEtat.blocs.forEach(function (b) {
      for (var j = 0; j < b.noeuds.length; j++) b.noeuds[j].nodeValue = b.originaux[j];
      // Les unités ont pu changer de place pour suivre la syntaxe de la langue d'arrivée :
      // rendre le texte sans rendre l'ordre laisserait un original en désordre.
      if (b.ordre) {
        for (var k = 0; k < b.ordre.length; k++) {
          b.el.insertBefore(b.ordre[k].noeud, b.ordre[k].suivant);
        }
      }
      b.el.removeAttribute('data-okia-tr-fait');
    });
    // Les textes d'origine sont revenus ; les coupures de rédaction peuvent reprendre
    // leur place, et le bloc redevient ce qu'il était au caractère près.
    (trEtat.aplanis || []).forEach(function (a) { trDeplier(a.ops); });
    trEtat.aplanis = [];
    // `b.traduit` survit : c'est ce qui permet de revenir à la traduction sans la refaire.
    trEtat.actif = false;
    return trEtat.blocs.length;
  }

  /* Où en est le lecteur : de quoi ordonner la vague depuis le premier bloc visible
     plutôt que depuis le début du fichier. */
  function trVue() {
    return {
      defilement: Math.round(window.scrollY || 0),
      hauteur: Math.round(window.innerHeight || 0),
      actif: trEtat.actif,
      blocs: trEtat.blocs.length,
      coupures: (function () {
        var c = document.getElementById('content');
        return c ? c.querySelectorAll('br').length : 0;
      })(),
      aplanis: (trEtat.aplanis || []).length
    };
  }

  /* =========================================================================
     TRADUCTION — les libellés qui ne sont pas dans le texte : Mermaid et cartes.

     Le README prévient : ces deux-là se dessinent en différé, et leurs libellés
     doivent être traduits avant le rendu, sinon il faut redessiner — « et une carte
     qui se redessine, cela se voit ». Chacun s'en tire autrement.

     Une carte ne se redessine pas du tout : le libellé d'un marqueur vit dans une
     bulle qui ne s'ouvre qu'au clic. On réécrit la bulle, la carte ne bouge pas.

     Un diagramme, lui, doit être redessiné — mais c'est un SVG statique, pas une
     carte vivante : le fondu du bloc couvre le remplacement. On traduit les seuls
     libellés, jamais la syntaxe : `flowchart TD` reste `flowchart TD`, et le banc a
     montré qu'une traduction du texte brut le retournait en « Flowchart TD ».
     ========================================================================= */

  /* Les libellés d'une source Mermaid : ce qui est entre crochets, accolades,
     parenthèses ou barres verticales. Le reste — mots-clés, identifiants de nœuds,
     flèches — n'est pas de la langue. */
  var TR_MERMAID_RE = /(\[|\{\{|\{|\(\(|\(|\|)([^\[\]\{\}\(\)\|\n]{2,})(\]|\}\}|\}|\)\)|\)|\|)/g;

  function trLibellesMermaid(src) {
    var libelles = [];
    src.replace(TR_MERMAID_RE, function (tout, ouvre, texte, ferme) {
      var net = texte.trim();
      // Ce qui est entre délimiteurs EST un libellé : les identifiants de nœuds se
      // tiennent devant le crochet, jamais dedans. Écarter ici ce qui « ressemble à un
      // identifiant » coûtait les libellés d'un seul mot — « Oui », « Non » — qui sont
      // précisément ceux des branches d'un organigramme.
      if (net && /[A-Za-zÀ-ÿ]/.test(net)) libelles.push(net);
      return tout;
    });
    return libelles;
  }

  function trRemplacerLibelles(src, table) {
    return src.replace(TR_MERMAID_RE, function (tout, ouvre, texte, ferme) {
      var net = texte.trim();
      if (Object.prototype.hasOwnProperty.call(table, net)) {
        return ouvre + table[net] + ferme;
      }
      return tout;
    });
  }

  /* Rend la liste de ce qui reste à traduire hors du texte courant : un tableau
     d'entrées { genre, cle, texte }. Swift les traite comme des blocs ordinaires. */
  function trCollecterExtras(racine) {
    var container = racine || document.getElementById('content');
    if (!container) return [];
    var extras = [];

    container.querySelectorAll('pre.mermaid').forEach(function (pre, i) {
      var src = pre.getAttribute('data-okia-src') || '';
      var vus = {};
      trLibellesMermaid(src).forEach(function (texte) {
        if (vus[texte]) return;
        vus[texte] = true;
        extras.push({ genre: 'mermaid', cle: 'm' + i, texte: texte });
      });
    });

    container.querySelectorAll('.okia-map').forEach(function (el, i) {
      (el._okiaMarqueurs || []).forEach(function (m, j) {
        extras.push({ genre: 'carte', cle: 'c' + i + '.' + j, texte: m.label });
      });
    });

    return extras;
  }

  /* Réécrit les libellés traduits. `table` associe le texte d'origine à sa traduction. */
  function trAppliquerExtras(table, racine) {
    var container = racine || document.getElementById('content');
    if (!container) return Promise.resolve(0);
    var faits = 0;

    container.querySelectorAll('.okia-map').forEach(function (el) {
      (el._okiaMarqueurs || []).forEach(function (m) {
        var trad = table[m.label];
        if (!trad) return;
        m.marker.setPopupContent('<strong>' + escapeHtml(trad) + '</strong>');
        faits++;
      });
    });

    var diagrammes = [];
    container.querySelectorAll('pre.mermaid').forEach(function (pre) {
      var src = pre.getAttribute('data-okia-src') || '';
      var nouveau = trRemplacerLibelles(src, table);
      if (nouveau === src) return;
      if (!pre.hasAttribute('data-okia-src-fr')) pre.setAttribute('data-okia-src-fr', src);
      pre.setAttribute('data-okia-src', nouveau);
      pre.removeAttribute('data-processed');
      pre.textContent = nouveau;
      diagrammes.push(pre);
      faits++;
    });

    if (!diagrammes.length) return Promise.resolve(faits);
    // Un seul redessin, pour tous les diagrammes à la fois.
    return renderMermaid(container, '').then(function () { return faits; });
  }

  /* Rend aux diagrammes leur source d'origine — pendant du retour à l'original. */
  function trRestaurerExtras(tableInverse, racine) {
    var container = racine || document.getElementById('content');
    if (!container) return Promise.resolve(0);

    container.querySelectorAll('.okia-map').forEach(function (el) {
      (el._okiaMarqueurs || []).forEach(function (m) {
        m.marker.setPopupContent('<strong>' + escapeHtml(m.label) + '</strong>');
      });
    });

    var diagrammes = [];
    container.querySelectorAll('pre.mermaid[data-okia-src-fr]').forEach(function (pre) {
      var origine = pre.getAttribute('data-okia-src-fr');
      pre.setAttribute('data-okia-src', origine);
      pre.removeAttribute('data-processed');
      pre.textContent = origine;
      diagrammes.push(pre);
    });
    if (!diagrammes.length) return Promise.resolve(0);
    return renderMermaid(container, '').then(function () { return diagrammes.length; });
  }

  /* Applique une table « texte d'origine → traduction » à un conteneur, sans modèle et
     sans aller-retour. C'est ce qui permet à l'export PowerPoint de porter la traduction :
     il rend chaque diapositive hors écran, et l'on y repose ce qui a déjà été traduit. */
  function trAppliquerMemoire(racine, table) {
    // `true` : ne pas vider les tables de bascule, dont on se sert précisément ici.
    var blocs = trCollecter(racine, true);
    var faits = 0;
    blocs.forEach(function (b) {
      var sequence = [];
      var connu = false;
      b.parts.forEach(function (part) {
        var trad = (!part.protege && Object.prototype.hasOwnProperty.call(table, part.texte))
          ? table[part.texte] : part.texte;
        if (trad !== part.texte) connu = true;
        sequence.push({ i: part.i, texte: trad });
      });
      if (!connu) return;
      trAppliquer(b.id, sequence, false, false);
      faits++;
    });
    return faits;
  }

  /* Le titre tel qu'il s'affiche à cet instant. La barre du lecteur montre le titre du
     document : quand le document passe en allemand, elle le suit. Le coffre et les
     Récents, eux, ne bougent pas — ils indexent des fichiers, pas des affichages. */
  function trTitre() {
    var h1 = document.querySelector('#content h1.okia-title') ||
             document.querySelector('#content h1');
    return h1 ? h1.textContent.trim() : '';
  }

  /* Un export circule sans son bandeau : la mention doit voyager avec le document.
     Insérée seulement le temps de l'export — comme les cartes gelées pour l'impression —
     puis retirée, pour ne pas doubler à l'écran le bandeau qui le dit déjà. */
  function trMentionExport(texte) {
    trRetirerMention();
    if (!texte) return false;
    var titre = document.querySelector('#content h1.okia-title');
    if (!titre) return false;
    var note = document.createElement('div');
    note.className = 'okia-tr-mention';
    note.textContent = texte;
    titre.parentNode.insertBefore(note, titre.nextSibling);
    return true;
  }

  function trRetirerMention() {
    var notes = document.querySelectorAll('.okia-tr-mention');
    for (var i = 0; i < notes.length; i++) {
      if (notes[i].parentNode) notes[i].parentNode.removeChild(notes[i]);
    }
  }

  window.OKIA = {
    render: render,
    renderPlain: renderPlain,
    freezeMapsForPrint: freezeMapsForPrint,
    unfreezeMaps: unfreezeMaps,
    markBreakBefore: markBreakBefore,
    headings: headings,
    renderFragment: renderFragment,
    exportModel: exportModel,
    setFontScale: setFontScale,
    scrollToHeading: scrollToHeading,
    search: search,
    searchNext: searchNext,
    searchPrev: searchPrev,
    clearSearch: clearSearch,
    translation: {
      collect: trCollecter,
      apply: trAppliquer,
      restore: trRestaurer,
      toggle: trBasculer,
      view: trVue,
      title: trTitre,
      exportNote: trMentionExport,
      clearExportNote: trRetirerMention,
      applyMemory: trAppliquerMemoire,
      collectExtras: trCollecterExtras,
      applyExtras: trAppliquerExtras,
      restoreExtras: trRestaurerExtras
    }
  };
  post('ready', {});
})();
