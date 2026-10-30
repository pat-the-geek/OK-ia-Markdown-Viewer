/* =========================================================================
   md Viewer 1.4 — option Analytic : les annotations.

   Ancrées au TEXTE, jamais à l'écran : la page se recompose (taille du texte, thème, rotation,
   livre, Duo) et un trait posé sur l'écran ne retomberait plus au bon endroit.
   - Surligner, souligner : une plage de texte, retrouvée par sa citation exacte et ce qui
     l'entoure (le « TextQuoteSelector » du W3C), dessinée par les surlignages natifs de WebKit
     (CSS Custom Highlights) — rien n'est inséré dans le texte, la recherche et la traduction ne
     voient rien.
   - Écrire : l'image du tracé, accrochée au bloc (paragraphe, élément de liste, titre…) sous
     lequel elle a été tracée, en proportion de sa largeur — en pourcentages, que le navigateur
     recalcule seul : la page de l'écran, celle du livre et la feuille du PDF n'ont pas la même
     largeur.
     Un diagramme, une image ou une carte n'ont pas de texte où s'accrocher : la note s'y ancre
     par son rang dans la page (le 3e diagramme, la 2e image, l'adresse de l'image en plus), et
     sa place se mesure sur le dessin lui-même (Patrick, 29/10/2026 : « peut-on annoter les
     diagrammes et images ? » — le trait disparaissait).

   Le fichier .md n'est jamais modifié : Swift garde les annotations et les repose ici. Fichier à
   part de render.js, que fornews copie mot pour mot.
   ========================================================================= */
(function () {
  'use strict';

  var CONTEXTE = 32;           // caractères de part et d'autre de la citation
  var BLOCS = 'p, li, h1, h2, h3, h4, h5, h6, blockquote, pre, td, th, figure, .callout, .okia-map, img:not(.okia-encre)';
  var annotations = [];        // l'état courant, tel que Swift l'a posé
  var occupe = false;          // nos propres retouches ne relancent pas l'observateur

  // La page du lecteur (et du livre) : #content. Le diaporama : #deck, toutes ses diapositives —
  // une diapositive reprend le texte du document, les annotations s'y retrouvent.
  function contenu() { return document.getElementById('content') || document.getElementById('deck'); }
  // Là où chercher le bloc le plus proche d'un tracé : dans le diaporama, la diapositive affichée
  // seulement (les autres sont cachées, à zéro).
  function zone() {
    var d = document.getElementById('deck');
    return d ? (d.querySelector('.slide.active') || d) : contenu();
  }

  function post(nom, charge) {
    try { window.webkit.messageHandlers[nom].postMessage(charge); } catch (e) { /* navigateur */ }
  }

  /* ---- Le texte de la page, nœud par nœud -------------------------------------------- */

  function noeudsTexte(racine) {
    var liste = [], w = document.createTreeWalker(racine, NodeFilter.SHOW_TEXT, {
      acceptNode: function (n) {
        var p = n.parentNode;
        while (p && p !== racine) {
          var nom = p.nodeName;
          if (nom === 'SCRIPT' || nom === 'STYLE' || nom === 'svg' || nom === 'SVG') return NodeFilter.FILTER_REJECT;
          if (p.classList && (p.classList.contains('mermaid') || p.classList.contains('okia-map'))) return NodeFilter.FILTER_REJECT;
          p = p.parentNode;
        }
        return NodeFilter.FILTER_ACCEPT;
      }
    });
    var n, pos = 0;
    while ((n = w.nextNode())) { liste.push({ n: n, debut: pos }); pos += n.nodeValue.length; }
    return { noeuds: liste, texte: liste.map(function (x) { return x.n.nodeValue; }).join('') };
  }

  function position(noeuds, noeud, decalage) {
    for (var i = 0; i < noeuds.length; i++) if (noeuds[i].n === noeud) return noeuds[i].debut + decalage;
    return -1;
  }

  function versRange(noeuds, debut, fin) {
    var r = document.createRange(), posee = false;
    for (var i = 0; i < noeuds.length; i++) {
      var x = noeuds[i], long = x.n.nodeValue.length;
      // Strict au départ : une citation qui commence pile à la fin d'un nœud commence au suivant —
      // sinon elle partait du saut de ligne posé entre deux paragraphes, hors de tout bloc.
      if (!posee && debut < x.debut + long) { r.setStart(x.n, Math.max(0, debut - x.debut)); posee = true; }
      if (posee && fin <= x.debut + long) { r.setEnd(x.n, Math.max(0, fin - x.debut)); return r; }
    }
    return null;
  }

  /* ---- Du point touché au caractère ---------------------------------------------------- */

  // Le caractère sous un point de la PAGE (coordonnées du document, pas de l'écran).
  function caretPage(x, y) {
    var cx = x - window.scrollX, cy = y - window.scrollY;
    var r = document.caretRangeFromPoint ? document.caretRangeFromPoint(cx, cy) : null;
    if (!r || !contenu().contains(r.startContainer)) return null;
    if (r.startContainer.nodeType !== Node.TEXT_NODE) return null;
    return r;
  }

  // Le trait de surligneur va de (x1, y1) à (x2, y2) : la plage de texte qu'il couvre, ancrée.
  function ancrerTexte(x1, y1, x2, y2) {
    var a = caretPage(x1, y1), b = caretPage(x2, y2);
    if (!a || !b) return null;
    var t = noeudsTexte(contenu());
    var i = position(t.noeuds, a.startContainer, a.startOffset);
    var j = position(t.noeuds, b.startContainer, b.startOffset);
    if (i < 0 || j < 0) return null;
    if (j < i) { var k = i; i = j; j = k; }
    // Des mots entiers : un trait commence rarement pile au début d'un mot.
    while (i > 0 && /[\p{L}\p{N}’']/u.test(t.texte[i - 1])) i--;
    while (j < t.texte.length && /[\p{L}\p{N}’']/u.test(t.texte[j])) j++;
    var exact = t.texte.slice(i, j);
    if (!exact.trim()) return null;
    return { exact: exact, prefix: t.texte.slice(Math.max(0, i - CONTEXTE), i),
             suffix: t.texte.slice(j, j + CONTEXTE) };
  }

  // Retrouver une citation : toutes ses occurrences, puis celle dont le contexte ressemble le plus.
  function resoudre(t, ancre) {
    var meilleure = -1, score = -1, from = 0, idx;
    while ((idx = t.texte.indexOf(ancre.exact, from)) !== -1) {
      var avant = t.texte.slice(Math.max(0, idx - ancre.prefix.length), idx);
      var apres = t.texte.slice(idx + ancre.exact.length, idx + ancre.exact.length + ancre.suffix.length);
      var s = communFin(avant, ancre.prefix) + communDebut(apres, ancre.suffix);
      if (s > score) { score = s; meilleure = idx; }
      from = idx + 1;
    }
    return meilleure < 0 ? null : versRange(t.noeuds, meilleure, meilleure + ancre.exact.length);
  }
  function communFin(a, b) { var n = 0; while (n < a.length && n < b.length && a[a.length - 1 - n] === b[b.length - 1 - n]) n++; return n; }
  function communDebut(a, b) { var n = 0; while (n < a.length && n < b.length && a[n] === b[n]) n++; return n; }

  /* ---- Le bloc sous un tracé ----------------------------------------------------------- */

  function blocSous(x, y) {
    var el = document.elementFromPoint(x - window.scrollX, y - window.scrollY);
    var bloc = el && el.closest ? el.closest(BLOCS) : null;
    if (bloc && contenu().contains(bloc)) return bloc;
    // Dans la marge ou entre deux blocs : celui dont la hauteur contient le point, sinon le plus proche.
    var tous = zone().querySelectorAll(BLOCS), proche = null, ecart = Infinity;
    for (var i = 0; i < tous.length; i++) {
      var r = tous[i].getBoundingClientRect(), haut = r.top + window.scrollY, bas = r.bottom + window.scrollY;
      var d = y < haut ? haut - y : (y > bas ? y - bas : 0);
      if (d < ecart) { ecart = d; proche = tous[i]; }
    }
    return proche;
  }

  // Le texte qui identifie un bloc : son début, et ce qui le précède dans la page.
  function ancreBloc(bloc) {
    var t = noeudsTexte(contenu()), propre = noeudsTexte(bloc).texte;
    var exact = propre.slice(0, 80);
    var premier = noeudsTexte(bloc).noeuds[0];
    var debut = premier ? position(t.noeuds, premier.n, 0) : -1;
    return { exact: exact, prefix: debut > 0 ? t.texte.slice(Math.max(0, debut - CONTEXTE), debut) : '',
             suffix: '', balise: bloc.nodeName };
  }

  // Un tracé (rectangle, coordonnées de la page) → son bloc et sa place, en largeurs de bloc.
  function ancrerEncre(x, y, l, h) {
    var m = mediaSous(x + l / 2, y + h / 2);
    if (m) return ancrerMedia(m, x, y, l);
    var bloc = blocSous(x + l / 2, y + h / 2);
    if (!bloc) return null;
    var r = bloc.getBoundingClientRect(), bx = r.left + window.scrollX, by = r.top + window.scrollY;
    var w = r.width || 1;
    var a = ancreBloc(bloc);
    a.fx = (x - bx) / w; a.fy = (y - by) / w; a.fl = l / w;
    return a;
  }

  /* ---- Les blocs sans texte : diagrammes, images, cartes ------------------------------- */

  // Le diagramme, la carte ou l'image sous un élément, ou null. Une tuile de la carte ou une
  // image dans un diagramme comptent pour leur cadre.
  function media(el) {
    var m = el.closest('.okia-map') || el.closest('pre.mermaid');
    if (m) return m;
    return el.nodeName === 'IMG' && !el.classList.contains('okia-encre') ? el : null;
  }
  function genre(m) {
    return m.classList.contains('okia-map') ? 'carte' : (m.nodeName === 'PRE' ? 'diagramme' : 'image');
  }
  // Le média sous un point de la page, par sa géométrie : le bouton d'agrandissement posé sur une
  // image, ou une note déjà là, ne le cachent pas.
  function mediaSous(x, y) {
    var cx = x - window.scrollX, cy = y - window.scrollY;
    var tous = zone().querySelectorAll('.okia-map, pre.mermaid, img:not(.okia-encre)');
    for (var i = 0; i < tous.length; i++) {
      var m = media(tous[i]), r = m.getBoundingClientRect();
      if (cx >= r.left && cx <= r.right && cy >= r.top && cy <= r.bottom) return m;
    }
    return null;
  }
  // Ceux d'un genre, dans l'ordre de la page.
  function medias(g) {
    var sel = g === 'carte' ? '.okia-map' : (g === 'diagramme' ? 'pre.mermaid' : 'img:not(.okia-encre)');
    return Array.prototype.filter.call(contenu().querySelectorAll(sel), function (m) {
      return g !== 'image' || !m.closest('.okia-map, pre.mermaid');
    });
  }
  // Le dessin lui-même, sur lequel la place d'une note se mesure : le diagramme est centré dans
  // son cadre, plus étroit que lui sur un grand écran.
  function dessin(m) { return (m.nodeName === 'PRE' && m.querySelector('svg')) || m; }
  // Où poser l'image de la note : une image n'a pas d'enfant, elle va dans son enveloppe
  // (render.js, à la taille de l'image) ou, à défaut, dans son parent.
  function hote(m) { return m.nodeName === 'IMG' ? m.parentElement : m; }
  // Une adresse d'image, raccourcie : une image importée est une URL data: de plusieurs centaines
  // de kilo-octets, dont la fin suffit à la reconnaître.
  function adresse(m) {
    var s = m.getAttribute('src') || '';
    return s.length > 200 ? s.slice(-120) : s;
  }

  function ancrerMedia(m, x, y, l) {
    var g = genre(m), rang = medias(g).indexOf(m);
    if (rang < 0) return null;
    // Le texte qui précède, pour l'export Word : il y retrouve l'image qui suit.
    var t = noeudsTexte(contenu()), pos = t.texte.length;
    for (var i = 0; i < t.noeuds.length; i++) {
      if (m.compareDocumentPosition(t.noeuds[i].n) & Node.DOCUMENT_POSITION_FOLLOWING) { pos = t.noeuds[i].debut; break; }
    }
    var r = dessin(m).getBoundingClientRect(), w = r.width || 1;
    // Une carte garde sa hauteur quand la page s'élargit : sa hauteur se mesure en hauteurs.
    var v = g === 'carte' ? (r.height || 1) : w;
    var a = { exact: '', prefix: t.texte.slice(Math.max(0, pos - CONTEXTE), pos), suffix: '',
              balise: m.nodeName, media: g, rang: rang,
              fx: (x - r.left - window.scrollX) / w, fy: (y - r.top - window.scrollY) / v, fl: l / w };
    if (g === 'image') a.src = adresse(m);
    // Sur une carte, la note tient à la géographie : son coin en latitude et longitude, sa largeur
    // au zoom du tracé. Elle suit la carte qu'on déplace ou qu'on zoome (Patrick, 30/10/2026 : « il
    // faut tenir compte du déplacement et du zoom »).
    var carte = g === 'carte' ? m._leafletMap : null;
    if (carte) {
      var ll = carte.containerPointToLatLng([x - window.scrollX - r.left - m.clientLeft,
                                             y - window.scrollY - r.top - m.clientTop]);
      a.lat = ll.lat; a.lng = ll.lng; a.zoom = carte.getZoom(); a.px = l;
    }
    return a;
  }

  // La note d'une carte, en pixels de la carte telle qu'elle est maintenant : la largeur double à
  // chaque cran de zoom. Ce qui sort du cadre, la carte le coupe.
  function placerSurCarte(img, m, a) {
    var carte = m._leafletMap, p = carte.latLngToContainerPoint([a.lat, a.lng]);
    img.style.left = p.x + 'px';
    img.style.setProperty('margin-top', p.y + 'px', 'important');
    img.style.width = (a.px * Math.pow(2, carte.getZoom() - a.zoom)) + 'px';
  }
  function surCarte(a) { return a.media === 'carte' && a.lat != null && a.zoom != null; }

  // Les notes d'une carte suivent ses mouvements. Pendant l'animation d'un zoom (bouton, double
  // toucher), Leaflet agrandit les tuiles d'un coup : la note se cache, et revient à la fin.
  function suivreCarte(m) {
    var carte = m._leafletMap;
    if (!carte || m._okiaNotesSuivies) return;
    m._okiaNotesSuivies = true;
    function replacer() {
      m.querySelectorAll(':scope > .okia-encre').forEach(function (img) {
        var a = annotations.find(function (x) { return x.id === img.getAttribute('data-id'); });
        if (a && surCarte(a.ancre)) placerSurCarte(img, m, a.ancre);
      });
    }
    function voir(oui) {
      m.querySelectorAll(':scope > .okia-encre').forEach(function (img) { img.style.visibility = oui ? '' : 'hidden'; });
    }
    carte.on('move zoom resize viewreset', replacer);
    carte.on('zoomanim', function () { voir(false); });
    carte.on('zoomend', function () { replacer(); voir(true); });
  }

  // Le média sous un point de la page, nommé par son genre et son rang (« carte:0 »), ou null sur
  // le texte : Swift sépare en notes distinctes des traits tracés d'affilée sur des médias
  // différents — réunis, la note prenait la place de leur centre, et une carte coupait le reste.
  function mediaNomme(x, y) {
    var m = mediaSous(x, y);
    if (!m) return null;
    var g = genre(m);
    return g + ':' + medias(g).indexOf(m);
  }

  function retrouverMedia(ancre) {
    var liste = medias(ancre.media), m = liste[ancre.rang];
    // Une image se reconnaît aussi à son adresse : une image ajoutée plus haut décale les rangs.
    if (ancre.src && (!m || adresse(m) !== ancre.src)) {
      m = liste.find(function (x) { return adresse(x) === ancre.src; }) || m;
    }
    return m || null;
  }

  // La note d'un média, en pourcentages de la largeur de son hôte : la place mesurée sur le
  // dessin, reportée dans l'hôte tel qu'il est maintenant.
  function placerSurMedia(img, m, hote, a) {
    // Les pourcentages d'une position absolue se prennent sur la boîte intérieure de l'hôte,
    // bordure exclue (le cadre d'un diagramme en a une).
    var r = hote.getBoundingClientRect(), d = dessin(m).getBoundingClientRect();
    var h = { left: r.left + hote.clientLeft, top: r.top + hote.clientTop, width: hote.clientWidth };
    if (h.width < 1 || d.width < 1) {   // une diapositive cachée : on reprend la place telle quelle
      img.style.left = (a.fx * 100) + '%';
      img.style.setProperty('margin-top', (a.fy * 100) + '%', 'important');
      img.style.width = (a.fl * 100) + '%';
      return;
    }
    img.style.left = ((d.left - h.left + a.fx * d.width) / h.width * 100) + '%';
    var v = a.media === 'carte' ? d.height : d.width;
    img.style.setProperty('margin-top', ((d.top - h.top + a.fy * v) / h.width * 100) + '%', 'important');
    img.style.width = (a.fl * d.width / h.width * 100) + '%';
  }

  function retrouverBloc(t, ancre) {
    if (!ancre.exact) return null;
    var r = resoudre(t, ancre);
    if (!r) return null;
    var el = r.startContainer.parentNode;
    var bloc = el.closest ? el.closest(ancre.balise ? ancre.balise.toLowerCase() : BLOCS) : null;
    return bloc || (el.closest ? el.closest(BLOCS) : null);
  }

  /* ---- Poser les annotations ----------------------------------------------------------- */

  function poser() {
    var c = contenu();
    if (!c || !window.CSS || !CSS.highlights) return;
    occupe = true;
    c.querySelectorAll('.okia-encre').forEach(function (img) { img.remove(); });
    var t = noeudsTexte(c);
    var groupes = {}, orphelines = [];
    annotations.forEach(function (a) {
      if (a.type === 'encre') {
        var m = a.ancre.media ? retrouverMedia(a.ancre) : null;
        var bloc = a.ancre.media ? (m && hote(m)) : retrouverBloc(t, a.ancre);
        if (!bloc) { orphelines.push(a.id); return; }
        if (getComputedStyle(bloc).position === 'static') bloc.style.position = 'relative';
        var img = document.createElement('img');
        img.className = 'okia-encre';
        img.alt = '';
        img.setAttribute('aria-hidden', 'true');
        img.setAttribute('data-id', a.id);
        img.src = 'data:image/png;base64,' + a.image;
        // En largeurs de bloc : `left` et `width` en % de la largeur du bloc ; la hauteur, par la
        // marge du haut, dont le pourcentage se prend lui aussi sur la largeur (un `top` en % se
        // prendrait sur la hauteur). Mesurée en pixels d'écran, la note sortait de sa place à
        // l'impression, sur une feuille plus étroite.
        img.style.top = '0';
        if (m && m._leafletMap && surCarte(a.ancre)) {
          placerSurCarte(img, m, a.ancre);
          suivreCarte(m);
        } else if (m) {
          placerSurMedia(img, m, bloc, a.ancre);
        } else {
          img.style.left = (a.ancre.fx * 100) + '%';
          img.style.setProperty('margin-top', (a.ancre.fy * 100) + '%', 'important');
          img.style.width = (a.ancre.fl * 100) + '%';
        }
        bloc.appendChild(img);
        return;
      }
      var r = resoudre(t, a.ancre);
      if (!r) { orphelines.push(a.id); return; }
      var cle = 'okia-' + a.type + '-' + a.couleur;
      (groupes[cle] = groupes[cle] || []).push(r);
    });
    // Effacer les anciens surlignages, poser les nouveaux, une couleur par nom.
    Array.from(CSS.highlights.keys()).forEach(function (k) { if (k.indexOf('okia-') === 0) CSS.highlights.delete(k); });
    Object.keys(groupes).forEach(function (cle) { CSS.highlights.set(cle, new Highlight(...groupes[cle])); });
    setTimeout(function () { occupe = false; }, 0);
    post('annotationsPosees', { orphelines: orphelines });
  }

  // Le surlignage ou la note sous un point (la gomme) : son identifiant, ou null.
  function sousLePoint(x, y) {
    var cx = x - window.scrollX, cy = y - window.scrollY;
    var img = Array.from(document.querySelectorAll('.okia-encre')).find(function (i) {
      var r = i.getBoundingClientRect();
      return cx >= r.left && cx <= r.right && cy >= r.top && cy <= r.bottom;
    });
    if (img) return img.getAttribute('data-id');
    var t = noeudsTexte(contenu());
    for (var i = 0; i < annotations.length; i++) {
      var a = annotations[i];
      if (a.type === 'encre') continue;
      var r = resoudre(t, a.ancre);
      if (!r) continue;
      var rects = r.getClientRects();
      for (var k = 0; k < rects.length; k++) {
        var q = rects[k];
        if (cx >= q.left - 4 && cx <= q.right + 4 && cy >= q.top - 4 && cy <= q.bottom + 4) return a.id;
      }
    }
    return null;
  }

  /* ---- L'impression ------------------------------------------------------------------- */

  // Le moteur d'impression (le PDF) ne peint pas les surlignages natifs : le temps de l'export,
  // chaque plage devient un vrai <mark>, retiré ensuite. Les plages sont toutes relevées AVANT de
  // toucher au texte, puis enveloppées nœud par nœud, de la fin vers le début : couper un nœud
  // décalerait les plages suivantes.
  function figer() {
    var c = contenu();
    if (!c) return;
    occupe = true;
    var t = noeudsTexte(c), morceaux = [];
    annotations.forEach(function (a) {
      if (a.type === 'encre') return;
      var r = resoudre(t, a.ancre);
      if (!r) return;
      var classe = 'okia-fige okia-' + a.type + '-' + a.couleur;
      t.noeuds.forEach(function (x) {
        if (!r.intersectsNode(x.n)) return;
        var debut = x.n === r.startContainer ? r.startOffset : 0;
        var fin = x.n === r.endContainer ? r.endOffset : x.n.nodeValue.length;
        if (fin > debut) morceaux.push({ n: x.n, debut: debut, fin: fin, classe: classe });
      });
    });
    morceaux.sort(function (a, b) { return a.n === b.n ? b.debut - a.debut : 0; });
    morceaux.forEach(function (m) {
      var long = m.n.nodeValue.length, fin = Math.min(m.fin, long);
      if (m.debut >= fin) return;
      if (fin < long) m.n.splitText(fin);
      var milieu = m.debut > 0 ? m.n.splitText(m.debut) : m.n;
      var mark = document.createElement('mark');
      mark.className = m.classe;
      milieu.parentNode.insertBefore(mark, milieu);
      mark.appendChild(milieu);
    });
  }

  // L'export Word ou PowerPoint lit les blocs de la page : l'image d'une note manuscrite, posée
  // dans son paragraphe, le faisait prendre pour une image, et son texte se perdait. Le temps de
  // l'export, les notes s'en vont ; `defiger()` les repose.
  function sansEncre() {
    var c = contenu();
    if (!c) return;
    occupe = true;
    c.querySelectorAll('.okia-encre').forEach(function (img) { img.remove(); });
  }

  function defiger() {
    var c = contenu();
    if (!c) return;
    c.querySelectorAll('mark.okia-fige').forEach(function (m) {
      var parent = m.parentNode;
      while (m.firstChild) parent.insertBefore(m.firstChild, m);
      parent.removeChild(m);
      parent.normalize();
    });
    // Les plages des surlignages natifs ont suivi les coupes et les recollages : on les repose.
    setTimeout(function () { occupe = false; poser(); }, 0);
  }

  // La page change sous nos annotations (recherche, traduction, nouveau rendu, thème) : on les
  // repose, une fois le calme revenu.
  var minuterie = null;
  var observateur = new MutationObserver(function () {
    if (occupe || !annotations.length) return;
    clearTimeout(minuterie);
    minuterie = setTimeout(poser, 250);
  });
  // La note d'un média se mesure sur son dessin, qui ne suit pas toujours la largeur de la page (un
  // diagramme garde sa taille sur un grand écran) : quand la page change de largeur (pliage du Duo,
  // rotation, fenêtre du Mac), on la repose.
  var largeur = 0;
  var redimension = window.ResizeObserver ? new ResizeObserver(function (e) {
    var w = Math.round(e[0].contentRect.width);
    if (w === largeur) return;
    largeur = w;
    if (occupe || !annotations.some(function (a) { return a.ancre && a.ancre.media; })) return;
    clearTimeout(minuterie);
    minuterie = setTimeout(poser, 250);
  }) : null;
  function observer() {
    var c = contenu();
    if (c) observateur.observe(c, { childList: true, subtree: true, characterData: true });
    if (c && redimension) redimension.observe(c);
  }
  observer();

  window.OKIA_ANNOT = {
    // annotations : [{ id, type: 'surligne'|'souligne'|'encre', couleur, ancre, image? }]
    appliquer: function (liste) { annotations = liste || []; poser(); },
    ancrerTexte: ancrerTexte,
    ancrerEncre: ancrerEncre,
    sousLePoint: sousLePoint,
    mediaNomme: mediaNomme,
    figer: figer,
    sansEncre: sansEncre,
    defiger: defiger
  };
})();
