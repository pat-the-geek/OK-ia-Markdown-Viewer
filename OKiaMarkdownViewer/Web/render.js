/* ===========================================================================
   OK-ia Markdown Viewer — rendering pipeline
   Reproduces the ok-ia.ch viewer: frontmatter → mermaid → callouts → wiki-links
   → broken-image cleanup → NER → marked.parse → mermaid normalize/run/recolor.
   Exposes window.OKIA.render(markdown, filename).
   =========================================================================== */
(function () {
  'use strict';

  var NOIR = '#111111';

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
      return new Intl.DateTimeFormat('fr-CH', { day: 'numeric', month: 'long', year: 'numeric' }).format(d);
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
    if (url) parts.push('<a href="' + escapeHtml(url) + '" target="_blank" rel="noopener">Lire l\'article ↗</a>');

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
  function testImage(url) {
    return new Promise(function (resolve) {
      if (!/^https?:\/\//i.test(url)) { resolve(true); return; } // local/relative: keep
      var img = new Image();
      var done = false;
      var t = setTimeout(function () { if (!done) { done = true; resolve(false); } }, 5000);
      img.onload = function () { if (!done) { done = true; clearTimeout(t); resolve(true); } };
      img.onerror = function () { if (!done) { done = true; clearTimeout(t); resolve(false); } };
      img.src = url;
    });
  }

  function removeBrokenImages(md) {
    if (typeof navigator !== 'undefined' && navigator.onLine === false) return Promise.resolve(md);
    var re = /!\[[^\]]*\]\(([^)\s]+)[^)]*\)/g;
    var urls = [], m;
    while ((m = re.exec(md)) !== null) urls.push(m[1]);
    urls = urls.filter(function (u) { return /^https?:\/\//i.test(u); });
    if (!urls.length) return Promise.resolve(md);

    var unique = Array.from(new Set(urls));
    return Promise.all(unique.map(testImage)).then(function (results) {
      var broken = {};
      unique.forEach(function (u, idx) { if (!results[idx]) broken[u] = true; });
      if (!Object.keys(broken).length) return md;
      var lines = md.split(/\r?\n/);
      var kept = [];
      for (var i = 0; i < lines.length; i++) {
        var im = lines[i].match(/^\s*!\[[^\]]*\]\(([^)\s]+)[^)]*\)\s*$/);
        if (im && broken[im[1]]) {
          // drop the image AND a following italic caption line, if any
          if (i + 1 < lines.length && /^\s*[*_].+[*_]\s*$/.test(lines[i + 1])) i++;
          continue;
        }
        // inline broken image inside a paragraph: strip just the image token
        kept.push(lines[i].replace(/!\[[^\]]*\]\(([^)\s]+)[^)]*\)/g, function (full, u) {
          return broken[u] ? '' : full;
        }));
      }
      return kept.join('\n');
    });
  }

  /* =========================================================================
     6. NER  — parse `## Entités` section, build color map + legend.
     Highlighting is applied to text nodes after marked.parse (DOM-safe).
     ========================================================================= */
  var NER_PALETTE = [[232,151,46],[59,130,246],[139,92,246],[16,185,129],
                     [239,68,68],[245,158,11],[236,72,153],[20,184,166]];

  function extractEntities(body) {
    var lines = body.split(/\r?\n/);
    var inSection = false, subtype = null, colorIdx = 0;
    var subtypes = {};            // subtype -> rgb
    var entities = {};            // entityName -> rgb
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i];
      var h2 = line.match(/^##\s+(.+?)\s*$/);
      if (h2) {
        inSection = /^entit[ée]s$/i.test(h2[1].trim());
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
     Tiles come from CARTO (light/dark) so the look matches the screenshot; an
     OpenStreetMap base layer is offered too. A fullscreen control expands the
     map to fill the viewport so it can be panned/zoomed in portrait or landscape.
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

      var map = L.map(el, {
        minZoom: cfg.minZoom || 0,
        maxZoom: cfg.maxZoom || 19,
        scrollWheelZoom: true
      });
      el._leafletMap = map;   // expose for the slideshow to re-measure on fit/resize

      var attribution = '© <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> · © <a href="https://carto.com/attributions">CARTO</a>';
      var light = L.tileLayer('https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png',
        { subdomains: 'abcd', maxZoom: 20, attribution: attribution });
      var dark = L.tileLayer('https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
        { subdomains: 'abcd', maxZoom: 20, attribution: attribution });
      var osm = L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
        { maxZoom: 19, attribution: '© <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>' });

      var prefersDark = window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches;
      var base = prefersDark ? dark : light;
      if (cfg.defaultTiles) base = L.tileLayer(cfg.defaultTiles, { maxZoom: 20, attribution: attribution });
      base.addTo(map);

      if (!cfg.defaultTiles) {
        L.control.layers({ 'Clair': light, 'Sombre': dark, 'OpenStreetMap': osm },
                         null, { position: 'topright' }).addTo(map);
      }

      var icon = leafletMarkerIcon();
      var pts = [];
      (cfg.markers || []).forEach(function (mk) {
        var marker = L.marker([mk.lat, mk.lng], { icon: icon }).addTo(map);
        if (mk.label) {
          marker.bindPopup('<strong>' + escapeHtml(mk.label) + '</strong>');
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

  function hideRedundantSecondImage(container) {
    var imgs = container.querySelectorAll('.markdown-body img, #content img');
    if (imgs.length >= 2) {
      // optional: a 2nd image is often a redundant credit/banner
      imgs[1].style.display = 'none';
    }
  }

  /* =========================================================================
     ORCHESTRATION
     ========================================================================= */
  function render(md, filename) {
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

      return removeBrokenImages(body).then(function (cleaned) {     // 5
        body = transformCallouts(cleaned);                          // 3
        body = transformWikiLinks(body);                            // 4

        var html = marked.parse(body, { breaks: true, gfm: true }); // marked
        container.innerHTML = header.headerHtml + legend + html;

        dedupeTitle(container, header.title);                       // remove duplicate H1
        highlightEntities(container, ner.entities, ner.subtypes);   // 6 (DOM-safe)
        hideRedundantSecondImage(container);
        attachImageZoom(container);                                 // tap image → full-screen
        clearSearch();
        applyFontScale();                                           // keep chosen size across renders
        buildTOC(container);                                        // headings -> ids + TOC
        renderLeafletMaps(container);                               // 2b interactive maps

        post('docMeta', { title: header.title });

        return renderMermaid(container, header.title).then(function () {
          post('rendered', { title: header.title });
        });
      });
    } catch (err) {
      container.innerHTML = '<div class="callout callout-error" style="--callout-color:#ef5350">' +
        '<div class="callout-title"><span class="callout-icon">⛔</span>Erreur de rendu</div>' +
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
    return removeBrokenImages(body).then(function (cleaned) {
      body = transformCallouts(cleaned);
      body = transformWikiLinks(body);
      container.innerHTML = marked.parse(body, { breaks: true, gfm: true });
      renderLeafletMaps(container);
      attachImageZoom(container);
      return renderMermaid(container, '');
    });
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
        blocks.push({ t: 'map', markers: mapMarkers(el) });
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
      return blocks.filter(function (b) { return b.t !== 'image' || b.png || b.src; });
    });
  }

  window.OKIA = {
    render: render,
    renderFragment: renderFragment,
    exportModel: exportModel,
    setFontScale: setFontScale,
    scrollToHeading: scrollToHeading,
    search: search,
    searchNext: searchNext,
    searchPrev: searchPrev,
    clearSearch: clearSearch
  };
  post('ready', {});
})();
