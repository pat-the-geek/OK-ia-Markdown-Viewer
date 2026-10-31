(function () {
  var NOIR='#111111', GRIS='#9A9A90', GRIS_CLAIR='#E8E6E0', BLANC='#FFFFFF',
      BLANC_CASSE='#FAFAF8', ORANGE='#E8972E', ORANGE_CLAIR='#F0A840', ORANGE_PALE='#FBEFD9';

  window.OKIA_MERMAID_CONFIG = {
    startOnLoad: false,
    theme: 'base',
    // SVG <text> labels instead of HTML <foreignObject> labels: foreignObject
    // measurement collapses to 0×0 inside the slideshow's flex/transform canvas
    // (labels become invisible). SVG text measures reliably everywhere.
    htmlLabels: false,
    flowchart: { htmlLabels: false },
    // Gantt: force an explicit pixel width. Without it, Mermaid derives the width
    // from the (narrow, pre-layout) container and computes 0 → viewBox "0 0 0 h",
    // making the whole chart invisible. useMaxWidth keeps it responsive on screen.
    gantt: { useMaxWidth: true, useWidth: 1000 },
    themeVariables: {
      fontFamily: "-apple-system, BlinkMacSystemFont, 'Segoe UI', Helvetica, Arial, sans-serif",
      fontSize: '15px',
      background: BLANC_CASSE,
      primaryColor: BLANC, primaryTextColor: NOIR, primaryBorderColor: ORANGE,
      mainBkg: BLANC, nodeBorder: ORANGE, nodeTextColor: NOIR, titleColor: NOIR,
      secondaryColor: GRIS_CLAIR, secondaryTextColor: NOIR, secondaryBorderColor: GRIS,
      tertiaryColor: BLANC_CASSE, tertiaryTextColor: NOIR, tertiaryBorderColor: GRIS,
      lineColor: ORANGE, edgeLabelBackground: BLANC_CASSE,
      clusterBkg: BLANC_CASSE, clusterBorder: GRIS,
      noteBkgColor: ORANGE_PALE, noteBorderColor: ORANGE, noteTextColor: NOIR,
      actorBkg: BLANC, actorBorder: ORANGE, actorTextColor: NOIR, actorLineColor: GRIS,
      signalColor: NOIR, signalTextColor: NOIR,
      labelBoxBkgColor: BLANC_CASSE, labelBoxBorderColor: GRIS, labelTextColor: NOIR,
      loopTextColor: NOIR, activationBkgColor: GRIS_CLAIR, activationBorderColor: GRIS,
      cScale0: ORANGE, cScaleLabel0: NOIR, cScale1: NOIR, cScaleLabel1: BLANC_CASSE,
      cScale2: GRIS, cScaleLabel2: NOIR, cScale3: ORANGE_CLAIR, cScaleLabel3: NOIR,
      cScale4: GRIS_CLAIR, cScaleLabel4: NOIR, cScale5: '#5A5A52', cScaleLabel5: BLANC_CASSE,
      cScale6: ORANGE, cScaleLabel6: NOIR, cScale7: NOIR, cScaleLabel7: BLANC_CASSE,
      pie1: ORANGE, pie2: NOIR, pie3: GRIS, pie4: ORANGE_CLAIR, pie5: GRIS_CLAIR, pie6: '#5A5A52',
      pieTitleTextColor: NOIR, pieSectionTextColor: NOIR, pieStrokeColor: BLANC_CASSE, pieOuterStrokeColor: GRIS
    }
  };

  var FILL_CYCLE=[ORANGE,NOIR,GRIS,ORANGE_CLAIR,GRIS_CLAIR,'#5A5A52'];
  var PALETTE_FILLS={};
  [ORANGE,NOIR,GRIS,GRIS_CLAIR,BLANC,BLANC_CASSE,ORANGE_CLAIR,'#5A5A52',
   '#ffffff','#fff','#333333','#000000','#000'].forEach(function(c){PALETTE_FILLS[c.toLowerCase()]=true;});

  function contrastText(hex){var h=hex.replace('#','');
    if(h.length===3)h=h.split('').map(function(c){return c+c;}).join('');
    if(h.length<6)return NOIR;
    var r=parseInt(h.slice(0,2),16),g=parseInt(h.slice(2,4),16),b=parseInt(h.slice(4,6),16);
    return (0.299*r+0.587*g+0.114*b)/255<0.5?BLANC_CASSE:NOIR;}

  window.normalizeMermaidPalette=function(src){
    if(!src|| (src.indexOf('fill:')===-1 && src.indexOf('stroke:')===-1))return src;
    var seen={},idx=0;
    function mapFill(hex){var low=hex.toLowerCase();
      if(PALETTE_FILLS[low])return hex;
      if(!(low in seen)){seen[low]=FILL_CYCLE[idx%FILL_CYCLE.length];idx++;}return seen[low];}
    return src.replace(/^[ \t]*(?:classDef|style)\b[^\n]*/gm,function(line){
      var fillM=line.match(/fill\s*:\s*(#[0-9a-fA-F]{3,8})/i);
      if(fillM){var finalFill=mapFill(fillM[1]);
        if(finalFill.toLowerCase()!==fillM[1].toLowerCase())
          line=line.replace(/fill\s*:\s*#[0-9a-fA-F]{3,8}/i,'fill:'+finalFill);
        var txt=contrastText(finalFill);
        if(/\bcolor\s*:/i.test(line))
          line=line.replace(/\bcolor\s*:\s*(?:#[0-9a-fA-F]{3,8}|white|black)/i,'color:'+txt);
        else line=line.replace(/(fill\s*:\s*#[0-9a-fA-F]{3,8})/i,'$1,color:'+txt);}
      line=line.replace(/stroke\s*:\s*(#[0-9a-fA-F]{3,8})/gi,function(m,hex){
        return PALETTE_FILLS[hex.toLowerCase()]?m:'stroke:'+GRIS;});
      return line;});};

  function darkBg(hexColor){var hex=hexColor.replace('#','');
    var h=hex.length===3?hex.split('').map(function(c){return c+c;}).join(''):hex;
    if(h.length!==6)return false;
    var r=parseInt(h.slice(0,2),16),g=parseInt(h.slice(2,4),16),b=parseInt(h.slice(4,6),16);
    return (0.299*r+0.587*g+0.114*b)/255<0.5;}

  function paintText(scope,textColor){
    scope.querySelectorAll('text, tspan').forEach(function(t){
      t.setAttribute('fill',textColor);t.style.setProperty('fill',textColor,'important');});
    scope.querySelectorAll('foreignObject span, foreignObject p, foreignObject div, foreignObject label')
      .forEach(function(t){t.style.setProperty('color',textColor,'important');});}

  /*
   * Quadrants : écarte les étiquettes qui se chevauchent. Mermaid pose toujours le nom d'un point
   * juste sous lui ; deux points proches superposent leurs noms. Chaque étiquette essaie, dans
   * l'ordre, dessous, dessus, à droite, à gauche puis les diagonales, et garde la première place
   * qui ne touche ni une autre étiquette, ni un point, ni le nom d'un quadrant, sans sortir du
   * cadre. Faute de place libre, la moins gênante : un texte sur un texte pèse plus qu'un texte
   * sur un point, et une étiquette ne sort jamais du dessin (elle y serait coupée). Repart toujours de la position du point :
   * on peut l'appeler plusieurs fois (changement de langue, diagramme d'abord masqué).
   */
  window.separerEtiquettesQuadrant = function (container) {
    var svgs = container.matches && container.matches('svg[aria-roledescription="quadrantChart"]')
      ? [container] : container.querySelectorAll('svg[aria-roledescription="quadrantChart"]');
    Array.prototype.forEach.call(svgs, function (svg) {
      var points = svg.querySelectorAll('g.data-point');
      if (!points.length) return;
      var ecart = 3;
      function boite(el, tx, ty) {
        var b = el.getBBox();
        return { x: b.x + tx, y: b.y + ty, w: b.width, h: b.height };
      }
      function touche(a, b) {
        return a.x < b.x + b.w + ecart && b.x < a.x + a.w + ecart &&
               a.y < b.y + b.h + ecart && b.y < a.y + a.h + ecart;
      }
      // Le cadre : l'union des quatre rectangles des quadrants.
      var cadre = null;
      svg.querySelectorAll('g.quadrants rect').forEach(function (r) {
        var b = r.getBBox();
        if (!cadre) { cadre = { x0: b.x, y0: b.y, x1: b.x + b.width, y1: b.y + b.height }; return; }
        cadre.x0 = Math.min(cadre.x0, b.x); cadre.y0 = Math.min(cadre.y0, b.y);
        cadre.x1 = Math.max(cadre.x1, b.x + b.width); cadre.y1 = Math.max(cadre.y1, b.y + b.height);
      });
      if (!cadre || cadre.x1 - cadre.x0 <= 0) return;   // pas encore mis en page (masqué)
      var vb = svg.viewBox && svg.viewBox.baseVal;
      var dessin = vb && vb.width ? { x0: vb.x, y0: vb.y, x1: vb.x + vb.width, y1: vb.y + vb.height } : cadre;
      function dehors(b, z) { return b.x < z.x0 || b.x + b.w > z.x1 || b.y < z.y0 || b.y + b.h > z.y1; }
      // Obstacles fixes : les noms des quadrants et tous les points.
      var obstacles = [];
      svg.querySelectorAll('g.quadrants text').forEach(function (t) {
        var m = /translate\(\s*([-\d.]+)[ ,]+([-\d.]+)/.exec(t.getAttribute('transform') || '');
        var o = boite(t, m ? +m[1] : 0, m ? +m[2] : 0); o.poids = 2; obstacles.push(o);
      });
      var etiquettes = [];
      Array.prototype.forEach.call(points, function (p) {
        var c = p.querySelector('circle'), t = p.querySelector('text');
        if (!c || !t) return;
        var cx = +c.getAttribute('cx'), cy = +c.getAttribute('cy'), r = +c.getAttribute('r') || 5;
        obstacles.push({ x: cx - r, y: cy - r, w: 2 * r, h: 2 * r, poids: 1, cx: cx, cy: cy });
        etiquettes.push({ t: t, cx: cx, cy: cy, r: r });
      });
      var places = [];
      etiquettes.forEach(function (e) {
        var d = e.r + 2;
        var essais = [
          [0, d, 'middle', 'hanging'], [0, -d, 'middle', 'auto'],
          [d + 2, 0, 'start', 'middle'], [-d - 2, 0, 'end', 'middle'],
          [d, d, 'start', 'hanging'], [-d, d, 'end', 'hanging'],
          [d, -d, 'start', 'auto'], [-d, -d, 'end', 'auto']
        ];
        var meilleur = null;
        for (var i = 0; i < essais.length; i++) {
          var s = essais[i], tx = e.cx + s[0], ty = e.cy + s[1];
          e.t.setAttribute('text-anchor', s[2]);
          e.t.setAttribute('dominant-baseline', s[3]);
          var b = boite(e.t, tx, ty);
          if (!b.w) return;                                // pas mesurable : on laisse Mermaid
          var gene = 0;
          obstacles.concat(places).forEach(function (o) {
            if (o.w && touche(b, o) && !(o.cx === e.cx && o.cy === e.cy)) gene += o.poids;
          });
          if (dehors(b, dessin)) gene += 100;
          else if (dehors(b, cadre)) gene += 0.5;
          if (!meilleur || gene < meilleur.gene) meilleur = { gene: gene, s: s, tx: tx, ty: ty, b: b };
          if (gene === 0) break;
        }
        e.t.setAttribute('text-anchor', meilleur.s[2]);
        e.t.setAttribute('dominant-baseline', meilleur.s[3]);
        e.t.setAttribute('transform', 'translate(' + meilleur.tx + ', ' + meilleur.ty + ') rotate(0)');
        meilleur.b.poids = 2;
        places.push(meilleur.b);
      });
    });
  };

  window.applyMermaidTextColors=function(container,source){
    try{window.separerEtiquettesQuadrant(container);}catch(e){}
    if(!source)return;var m;
    var classDefRegex=/^\s*classDef\s+(\S+)\s+([^\n]+)/gm;
    while((m=classDefRegex.exec(source))!==null){
      var className=m[1],props=m[2];
      var fillM=props.match(/fill\s*:\s*(#[0-9a-fA-F]{3,8})/i);
      var colorM=props.match(/(?:^|,)\s*color\s*:\s*(#[0-9a-fA-F]{3,8}|white|black)/i);
      var textColor=null;
      if(colorM)textColor=colorM[1]==='white'?'#ffffff':(colorM[1]==='black'?NOIR:colorM[1]);
      else if(fillM&&darkBg(fillM[1]))textColor=BLANC_CASSE;
      if(!textColor)continue;
      container.querySelectorAll('.'+CSS.escape(className)).forEach(function(el){paintText(el,textColor);});}
    var styleRegex=/^\s*style\s+(\S+)\s+([^\n]+)/gm;
    while((m=styleRegex.exec(source))!==null){
      var nodeId=m[1],sprops=m[2];
      var sFillM=sprops.match(/fill\s*:\s*(#[0-9a-fA-F]{3,8})/i);
      var sColorM=sprops.match(/(?:^|,)\s*color\s*:\s*(#[0-9a-fA-F]{3,8}|white|black)/i);
      var sText=null;
      if(sColorM)sText=sColorM[1]==='white'?'#ffffff':(sColorM[1]==='black'?NOIR:sColorM[1]);
      else if(sFillM&&darkBg(sFillM[1]))sText=BLANC_CASSE;
      if(!sText)continue;
      var nodeEl=container.querySelector('[id*="flowchart-'+nodeId+'"]')
              ||container.querySelector('[id*="cluster_'+nodeId+'"]')
              ||container.querySelector('[id*="'+nodeId+'"]');
      if(nodeEl)paintText(nodeEl,sText);}};
})();
