/*
  md Viewer 1.4 — option Analytic : l'article d'une page web, tel que la page l'affiche.

  Un seul script, deux usages :
  - dans Safari, au partage « Analyser dans md Viewer » : l'extension de partage le donne à Safari
    (NSExtensionJavaScriptPreprocessingFile), qui l'exécute dans la page déjà chargée — une page
    d'abonné ou un bandeau déjà accepté passent donc tels quels ;
  - dans l'app, quand on ne reçoit qu'une adresse : la page est chargée hors écran, puis ce script
    y est exécuté.

  Il rend les métadonnées (titre, média, auteur, date, image, logo, langue) et le corps de l'article,
  bloc par bloc, en texte simple. Rien d'autre ne sort de la page.
*/
(function (racineGlobale) {
  function meta(noms) {
    for (var i = 0; i < noms.length; i++) {
      var el = document.querySelector('meta[property="' + noms[i] + '"], meta[name="' + noms[i] + '"]');
      if (el && el.content && el.content.trim()) return el.content.trim();
    }
    return '';
  }

  function absolue(u) {
    if (!u) return '';
    try { return new URL(u, document.baseURI).href; } catch (e) { return ''; }
  }

  // Les données structurées de l'article (schema.org), quand la page en porte.
  function jsonLD() {
    var r = {};
    Array.prototype.forEach.call(document.querySelectorAll('script[type="application/ld+json"]'), function (s) {
      try {
        var d = JSON.parse(s.textContent), liste = [].concat(d['@graph'] || d);
        liste.forEach(function (o) {
          var t = [].concat(o['@type'] || []).join(' ');
          if (!/Article|Posting|Report|Blog/i.test(t)) return;
          r.titre = r.titre || o.headline;
          r.date = r.date || o.datePublished;
          var a = [].concat(o.author || [])[0];
          r.auteur = r.auteur || (a && (a.name || a)) || '';
          r.media = r.media || (o.publisher && o.publisher.name) || '';
          var img = [].concat(o.image || [])[0];
          r.image = r.image || (img && (img.url || img)) || '';
        });
      } catch (e) {}
    });
    return r;
  }

  // Ce qui n'est pas l'article : navigation, partage, publicités, articles liés, commentaires.
  var DECOR = /(^|[\s_-])(nav|menu|footer|header|share|social|related|recommend|newsletter|subscribe|promo|advert|ads?|sponsor|comment|sidebar|breadcrumb|cookie|consent|paywall|signup|outbrain|taboola)([\s_-]|$)/i;

  function estDecor(el) {
    for (var n = el; n && n !== document.body; n = n.parentElement) {
      var tag = n.tagName;
      if (tag === 'NAV' || tag === 'ASIDE' || tag === 'FOOTER' || tag === 'FORM' || tag === 'BUTTON') return true;
      if (tag === 'HEADER' && !n.querySelector('h1 ~ p')) return true;
      var nom = (n.className && n.className.baseVal === undefined ? n.className : '') + ' ' + (n.id || '');
      if (DECOR.test(nom)) return true;
      if (n.getAttribute && (n.getAttribute('aria-hidden') === 'true' || n.hidden)) return true;
    }
    return false;
  }

  // Le conteneur de l'article : celui qui porte le plus de texte en paragraphes.
  function conteneur() {
    var cands = Array.prototype.slice.call(document.querySelectorAll(
      '[itemprop="articleBody"], article, main, [role="main"], .article-body, .article__body, .post-content, .entry-content, .story-body, #article, .content'));
    if (!cands.length) cands = [document.body];
    var meilleur = document.body, score = 0;
    cands.forEach(function (c) {
      var s = 0;
      Array.prototype.forEach.call(c.querySelectorAll('p'), function (p) {
        if (!estDecor(p)) s += (p.innerText || '').trim().length;
      });
      if (s > score) { score = s; meilleur = c; }
    });
    return meilleur;
  }

  function texte(el) { return (el.innerText || el.textContent || '').replace(/\s+/g, ' ').trim(); }

  function extraire() {
    var ld = jsonLD();
    var c = conteneur();
    var blocs = [], total = 0, vus = {};
    Array.prototype.forEach.call(c.querySelectorAll('h2, h3, h4, p, li, blockquote, figure img, picture img'), function (el) {
      if (total > 60000 || estDecor(el)) return;
      if (el.tagName === 'IMG') {
        var src = absolue(el.currentSrc || el.getAttribute('src') || el.getAttribute('data-src'));
        // Les petites images (icônes, pictos) ne sont pas des illustrations.
        if (src && !vus[src] && (el.naturalWidth || el.width || 0) >= 300) {
          vus[src] = 1;
          blocs.push({ t: 'img', x: src });
        }
        return;
      }
      // Un paragraphe dans une citation, un élément de liste dans une liste déjà prise : une seule fois.
      if (el.tagName !== 'BLOCKQUOTE' && el.closest('blockquote') && el.closest('blockquote') !== el) return;
      var x = texte(el);
      if (!x || vus[x]) return;
      if (el.tagName === 'P' && x.length < 25 && !/[.!?:»"]$/.test(x)) return;
      // Un élément de liste court qui n'est qu'un lien : une rubrique, un mot-clé, pas du texte.
      if (el.tagName === 'LI' && x.length < 40) {
        var liens = Array.prototype.map.call(el.querySelectorAll('a'), texte).join(' ');
        if (liens && liens.length >= x.length - 2) return;
      }
      vus[x] = 1;
      total += x.length;
      var t = /^H/.test(el.tagName) ? 'h' : el.tagName === 'LI' ? 'li' : el.tagName === 'BLOCKQUOTE' ? 'q' : 'p';
      blocs.push({ t: t, x: x });
    });

    var icone = '';
    Array.prototype.forEach.call(document.querySelectorAll('link[rel~="icon"], link[rel="apple-touch-icon"]'), function (l) {
      var tailles = parseInt((l.getAttribute('sizes') || '0').split('x')[0], 10) || 0;
      if (!icone || tailles >= 64) icone = absolue(l.getAttribute('href'));
    });

    var h1 = document.querySelector('h1');
    return {
      url: location.href,
      titre: ld.titre || meta(['og:title', 'twitter:title']) || (h1 ? texte(h1) : '') || document.title,
      media: meta(['og:site_name', 'application-name']) || ld.media || location.hostname.replace(/^www\./, ''),
      auteur: meta(['author', 'article:author']) || ld.auteur || '',
      date: meta(['article:published_time', 'og:article:published_time', 'date', 'dc.date']) || ld.date ||
            ((document.querySelector('time[datetime]') || {}).getAttribute ? document.querySelector('time[datetime]').getAttribute('datetime') : '') || '',
      image: absolue(meta(['og:image', 'og:image:url', 'twitter:image']) || ld.image),
      logo: icone,
      langue: (document.documentElement.lang || '').slice(0, 2).toLowerCase(),
      description: meta(['og:description', 'description']),
      blocs: blocs
    };
  }

  // Dans l'app : appelé par la vue web hors écran.
  racineGlobale.okiaExtrairePage = extraire;

  // Dans Safari : le protocole des extensions de partage.
  racineGlobale.ExtensionPreprocessingJS = {
    run: function (args) {
      var r;
      try { r = extraire(); } catch (e) { r = { url: location.href, titre: document.title, blocs: [], erreur: String(e) }; }
      args.completionFunction({ page: JSON.stringify(r) });
    },
    finalize: function () {}
  };
})(this);

// Safari attend que la dernière expression du fichier soit l'objet de l'extension.
var ExtensionPreprocessingJS = this.ExtensionPreprocessingJS;
