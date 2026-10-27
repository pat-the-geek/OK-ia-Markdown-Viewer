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

   Le fichier .md n'est jamais modifié : Swift garde les annotations et les repose ici. Fichier à
   part de render.js, que fornews copie mot pour mot.
   ========================================================================= */
(function () {
  'use strict';

  var CONTEXTE = 32;           // caractères de part et d'autre de la citation
  var BLOCS = 'p, li, h1, h2, h3, h4, h5, h6, blockquote, pre, td, th, figure, .callout, .okia-map, img';
  var annotations = [];        // l'état courant, tel que Swift l'a posé
  var occupe = false;          // nos propres retouches ne relancent pas l'observateur

  function contenu() { return document.getElementById('content'); }

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
    var tous = contenu().querySelectorAll(BLOCS), proche = null, ecart = Infinity;
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
    var bloc = blocSous(x + l / 2, y + h / 2);
    if (!bloc) return null;
    var r = bloc.getBoundingClientRect(), bx = r.left + window.scrollX, by = r.top + window.scrollY;
    var w = r.width || 1;
    var a = ancreBloc(bloc);
    a.fx = (x - bx) / w; a.fy = (y - by) / w; a.fl = l / w;
    return a;
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
        var bloc = retrouverBloc(t, a.ancre);
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
        img.style.left = (a.ancre.fx * 100) + '%';
        img.style.top = '0';
        img.style.setProperty('margin-top', (a.ancre.fy * 100) + '%', 'important');
        img.style.width = (a.ancre.fl * 100) + '%';
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
  function observer() {
    var c = contenu();
    if (c) observateur.observe(c, { childList: true, subtree: true, characterData: true });
  }
  observer();

  window.OKIA_ANNOT = {
    // annotations : [{ id, type: 'surligne'|'souligne'|'encre', couleur, ancre, image? }]
    appliquer: function (liste) { annotations = liste || []; poser(); },
    ancrerTexte: ancrerTexte,
    ancrerEncre: ancrerEncre,
    sousLePoint: sousLePoint,
    figer: figer,
    defiger: defiger
  };
})();
