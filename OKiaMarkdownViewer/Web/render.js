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
        if (pre.querySelector('svg')) attachZoom(pre, title);
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

      // 2 → 3 → 4 (string transforms before parse)
      body = transformMermaid(body);

      return removeBrokenImages(body).then(function (cleaned) {     // 5
        body = transformCallouts(cleaned);                          // 3
        body = transformWikiLinks(body);                            // 4

        var html = marked.parse(body, { breaks: true, gfm: true }); // marked
        container.innerHTML = header.headerHtml + legend + html;

        dedupeTitle(container, header.title);                       // remove duplicate H1
        highlightEntities(container, ner.entities, ner.subtypes);   // 6 (DOM-safe)
        hideRedundantSecondImage(container);

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

  window.OKIA = { render: render };
  post('ready', {});
})();
