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

  // App language, injected by the host app. window.OKIA_LANG is what render.js (fornews) knows
  // — five languages, English for the others ; window.OKIA_LANG_APP is the app's own language
  // (fifteen since 1.4).
  var LANGS = ['fr', 'en', 'de', 'es', 'it', 'ja', 'ko', 'zh-Hans', 'pt-BR', 'nl', 'ru', 'uk',
               'tr', 'vi', 'hi'];
  var DEMANDE = window.OKIA_LANG_APP || window.OKIA_LANG;
  var LANG = LANGS.indexOf(DEMANDE) >= 0 ? DEMANDE : 'fr';

  // The French text is the key, so French needs no entry of its own — and an untranslated
  // string degrades to readable French rather than to an identifier.
  var STRINGS = {
    // Transitions
    'Fondu':          { en: 'Dissolve', de: 'Überblenden', es: 'Fundido', it: 'Dissolvenza',
        ja: 'ディゾルブ', ko: '디졸브', 'zh-Hans': '溶解', 'pt-BR': 'Dissolver', nl: 'Vervagen', ru: 'Растворение', uk: 'Розчинення', tr: 'Çözülme', vi: 'Hòa tan', hi: 'डिज़ॉल्व' },
    'Poussée':        { en: 'Push', de: 'Schieben', es: 'Empujar', it: 'Spinta',
        ja: 'プッシュ', ko: '밀어내기', 'zh-Hans': '推移', 'pt-BR': 'Empurrar', nl: 'Duwen', ru: 'Сдвиг', uk: 'Зсув', tr: 'İtme', vi: 'Đẩy', hi: 'पुश' },
    'Entrée':         { en: 'Move In', de: 'Einfahren', es: 'Entrada', it: 'Entrata',
        ja: 'ムーブイン', ko: '이동', 'zh-Hans': '移入', 'pt-BR': 'Mover para Dentro', nl: 'Inschuiven', ru: 'Наплыв', uk: 'Наплив', tr: 'İçeri Taşıma', vi: 'Di chuyển vào', hi: 'मूव इन' },
    'Échelle':        { en: 'Scale', de: 'Skalieren', es: 'Escala', it: 'Scala',
        ja: 'スケール', ko: '크기 조절', 'zh-Hans': '缩放', 'pt-BR': 'Escala', nl: 'Schalen', ru: 'Масштаб', uk: 'Масштаб', tr: 'Ölçekleme', vi: 'Thu phóng', hi: 'स्केल' },
    'Retournement 3D':{ en: '3D Flip', de: '3D-Drehung', es: 'Giro 3D', it: 'Ribaltamento 3D',
        ja: '3Dフリップ', ko: '3D 뒤집기', 'zh-Hans': '3D 翻转', 'pt-BR': 'Virar em 3D', nl: '3D-omslag', ru: '3D-переворот', uk: '3D-перевертання', tr: '3B Çevirme', vi: 'Lật 3D', hi: '3D फ़्लिप' },
    'Balayage':       { en: 'Wipe', de: 'Wischen', es: 'Barrido', it: 'Tendina',
        ja: 'ワイプ', ko: '닦아내기', 'zh-Hans': '擦除', 'pt-BR': 'Varrer', nl: 'Vegen', ru: 'Стирание', uk: 'Витирання', tr: 'Silme', vi: 'Quét', hi: 'वाइप' },
    'Découverte':     { en: 'Reveal', de: 'Aufdecken', es: 'Revelar', it: 'Rivela',
        ja: 'リビール', ko: '드러내기', 'zh-Hans': '显露', 'pt-BR': 'Revelar', nl: 'Onthullen', ru: 'Открытие', uk: 'Відкриття', tr: 'Açığa Çıkarma', vi: 'Hé lộ', hi: 'रिवील' },
    'Cube':           { en: 'Cube', de: 'Würfel', es: 'Cubo', it: 'Cubo',
        ja: 'キューブ', ko: '큐브', 'zh-Hans': '立方体', 'pt-BR': 'Cubo', nl: 'Kubus', ru: 'Куб', uk: 'Куб', tr: 'Küp', vi: 'Khối lập phương', hi: 'क्यूब' },
    'Iris':           { en: 'Iris', de: 'Iris', es: 'Iris', it: 'Iride',
        ja: 'アイリス', ko: '조리개', 'zh-Hans': '光圈', 'pt-BR': 'Íris', nl: 'Iris', ru: 'Диафрагма', uk: 'Діафрагма', tr: 'İris', vi: 'Mống mắt', hi: 'आइरिस' },
    'Fondu au noir':  { en: 'Fade Through Black', de: 'Über Schwarz', es: 'Fundido a negro',
                        it: 'Dissolvenza al nero',
        ja: '黒へフェード', ko: '검정색으로 페이드', 'zh-Hans': '渐隐至黑色', 'pt-BR': 'Esmaecer pelo Preto', nl: 'Vervagen via zwart', ru: 'Через чёрный', uk: 'Через чорне', tr: 'Siyah Üzerinden Geçiş', vi: 'Mờ dần qua màu đen', hi: 'काले रंग से फ़ेड' },
    'Damier':         { en: 'Checkerboard', de: 'Schachbrett', es: 'Damero', it: 'Scacchiera',
        ja: 'チェッカーボード', ko: '바둑판', 'zh-Hans': '棋盘格', 'pt-BR': 'Xadrez', nl: 'Dambord', ru: 'Шахматная доска', uk: 'Шахівниця', tr: 'Dama Tahtası', vi: 'Bàn cờ', hi: 'चेकरबोर्ड' },
    // Thèmes
    'Clair':          { en: 'Light', de: 'Hell', es: 'Claro', it: 'Chiaro',
        ja: 'ライト', ko: '라이트', 'zh-Hans': '浅色', 'pt-BR': 'Claro', nl: 'Licht', ru: 'Светлая', uk: 'Світла', tr: 'Açık', vi: 'Sáng', hi: 'लाइट' },
    'Sombre':         { en: 'Dark', de: 'Dunkel', es: 'Oscuro', it: 'Scuro',
        ja: 'ダーク', ko: '다크', 'zh-Hans': '深色', 'pt-BR': 'Escuro', nl: 'Donker', ru: 'Тёмная', uk: 'Темна', tr: 'Koyu', vi: 'Tối', hi: 'डार्क' },
    'Console':        { en: 'Console', de: 'Konsole', es: 'Consola', it: 'Console',
        ja: 'コンソール', ko: '콘솔', 'zh-Hans': '控制台', 'pt-BR': 'Console', nl: 'Console', ru: 'Консоль', uk: 'Консоль', tr: 'Konsol', vi: 'Console', hi: 'कंसोल' },
    'Sépia':          { en: 'Sepia', de: 'Sepia', es: 'Sepia', it: 'Seppia',
        ja: 'セピア', ko: '세피아', 'zh-Hans': '棕褐色', 'pt-BR': 'Sépia', nl: 'Sepia', ru: 'Сепия', uk: 'Сепія', tr: 'Sepya', vi: 'Sepia', hi: 'सीपिया' },
    'Océan':          { en: 'Ocean', de: 'Ozean', es: 'Océano', it: 'Oceano',
        ja: 'オーシャン', ko: '오션', 'zh-Hans': '海洋', 'pt-BR': 'Oceano', nl: 'Oceaan', ru: 'Океан', uk: 'Океан', tr: 'Okyanus', vi: 'Đại dương', hi: 'महासागर' },
    // Menu et chrome du diaporama
    'Thème':          { en: 'Theme', de: 'Thema', es: 'Tema', it: 'Tema',
        ja: 'テーマ', ko: '테마', 'zh-Hans': '主题', 'pt-BR': 'Tema', nl: 'Thema', ru: 'Тема', uk: 'Тема', tr: 'Tema', vi: 'Chủ đề', hi: 'थीम' },
    'Transition':     { en: 'Transition', de: 'Übergang', es: 'Transición', it: 'Transizione',
        ja: 'トランジション', ko: '전환 효과', 'zh-Hans': '过渡', 'pt-BR': 'Transição', nl: 'Overgang', ru: 'Переход', uk: 'Перехід', tr: 'Geçiş', vi: 'Chuyển tiếp', hi: 'ट्रांज़िशन' },
    'Diapositives':   { en: 'Slides', de: 'Folien', es: 'Diapositivas', it: 'Diapositive',
        ja: 'スライド', ko: '슬라이드', 'zh-Hans': '幻灯片', 'pt-BR': 'Slides', nl: 'Dia\'s', ru: 'Слайды', uk: 'Слайди', tr: 'Slaytlar', vi: 'Trang chiếu', hi: 'स्लाइड' },
    'Diapositive précédente': { en: 'Previous slide', de: 'Vorherige Folie',
                                es: 'Diapositiva anterior', it: 'Diapositiva precedente',
        ja: '前のスライド', ko: '이전 슬라이드', 'zh-Hans': '上一张幻灯片', 'pt-BR': 'Slide anterior', nl: 'Vorige dia', ru: 'Предыдущий слайд', uk: 'Попередній слайд', tr: 'Önceki slayt', vi: 'Trang chiếu trước', hi: 'पिछली स्लाइड' },
    'Diapositive suivante':   { en: 'Next slide', de: 'Nächste Folie',
                                es: 'Diapositiva siguiente', it: 'Diapositiva successiva',
        ja: '次のスライド', ko: '다음 슬라이드', 'zh-Hans': '下一张幻灯片', 'pt-BR': 'Próximo slide', nl: 'Volgende dia', ru: 'Следующий слайд', uk: 'Наступний слайд', tr: 'Sonraki slayt', vi: 'Trang chiếu tiếp theo', hi: 'अगली स्लाइड' },
    'Quitter le diaporama':   { en: 'End slideshow', de: 'Diashow beenden',
                                es: 'Salir de la presentación', it: 'Esci dalla presentazione',
        ja: 'スライドショーを終了', ko: '슬라이드쇼 종료', 'zh-Hans': '结束放映', 'pt-BR': 'Encerrar apresentação', nl: 'Beëindig diavoorstelling', ru: 'Завершить слайд-шоу', uk: 'Завершити слайд-шоу', tr: 'Slayt gösterisinden çık', vi: 'Kết thúc trình chiếu', hi: 'स्लाइडशो से बाहर निकलें' },
    'Transitions':    { en: 'Transitions', de: 'Übergänge', es: 'Transiciones', it: 'Transizioni',
        ja: 'トランジション', ko: '전환 효과', 'zh-Hans': '过渡效果', 'pt-BR': 'Transições', nl: 'Overgangen', ru: 'Переходы', uk: 'Переходи', tr: 'Geçişler', vi: 'Hiệu ứng chuyển tiếp', hi: 'ट्रांज़िशन' },
    'Vue d’ensemble des diapositives': { en: 'Slide overview', de: 'Folienübersicht',
                                         es: 'Vista general de diapositivas',
                                         it: 'Panoramica delle diapositive',
        ja: 'スライドの概要', ko: '슬라이드 개요', 'zh-Hans': '幻灯片概览', 'pt-BR': 'Visão geral dos slides', nl: 'Overzicht van dia\'s', ru: 'Обзор слайдов', uk: 'Огляд слайдів', tr: 'Slayt genel bakışı', vi: 'Tổng quan trang chiếu', hi: 'स्लाइड ओवरव्यू' },
    'Fermer':         { en: 'Close', de: 'Schließen', es: 'Cerrar', it: 'Chiudi',
        ja: '閉じる', ko: '닫기', 'zh-Hans': '关闭', 'pt-BR': 'Fechar', nl: 'Sluit', ru: 'Закрыть', uk: 'Закрити', tr: 'Kapat', vi: 'Đóng', hi: 'बंद करें' },
    'Annoter':        { en: 'Annotate', de: 'Anmerken', es: 'Anotar', it: 'Annota',
        ja: '注釈', ko: '주석 달기', 'zh-Hans': '标注', 'pt-BR': 'Anotar', nl: 'Annoteer', ru: 'Аннотировать', uk: 'Анотувати', tr: 'Not ekle', vi: 'Chú thích', hi: 'एनोटेट करें' },
    'Présenter sur un second écran': { en: 'Present on a second screen', de: 'Auf zweitem Bildschirm präsentieren',
                                       es: 'Presentar en una segunda pantalla', it: 'Presenta su un secondo schermo',
        ja: '2台目の画面で発表', ko: '보조 화면에서 발표', 'zh-Hans': '在第二个屏幕上演示', 'pt-BR': 'Apresentar em uma segunda tela', nl: 'Presenteer op een tweede scherm', ru: 'Показать на втором экране', uk: 'Показати на другому екрані', tr: 'İkinci ekranda sun', vi: 'Trình bày trên màn hình thứ hai', hi: 'दूसरी स्क्रीन पर प्रस्तुत करें' },
    // « PowerPoint (.pptx) » reste tel quel : nom de produit + extension.
    'Export':         { en: 'Export', de: 'Export', es: 'Exportar', it: 'Esporta',
        ja: '書き出し', ko: '내보내기', 'zh-Hans': '导出', 'pt-BR': 'Exportar', nl: 'Exporteer', ru: 'Экспорт', uk: 'Експорт', tr: 'Dışa aktar', vi: 'Xuất', hi: 'एक्सपोर्ट करें' }
  };
  function TXT(fr) {
    var entry = STRINGS[fr];
    if (LANG === 'fr' || !entry) return fr;
    // Une langue sans sa traduction lit l'anglais plutôt que le français.
    return entry[LANG] || entry.en || fr;
  }

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

  // La transition que le document demande dans son en-tête (« transition: push ») : celle d'un
  // PowerPoint importé (1.4). Elle vaut pour ce document seulement ; le choix de l'utilisateur,
  // retenu d'un document à l'autre, reprend la main dès qu'il en change.
  function transitionDuDocument(md) {
    var m = md.match(/^﻿?---\r?\n([\s\S]*?)\r?\n---/);
    var t = m && m[1].match(/^transition:[ \t]*["']?([a-z]+)["']?[ \t]*$/m);
    return t && SPECS[t[1]] ? t[1] : null;
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
    return partagerReferences(slides.map(function (s) { return s.trim(); }).filter(function (s) { return s.length; }));
  }

  // Les définitions de référence (« [img3]: data:image/… ») valent pour tout le document : un
  // PowerPoint importé (1.4) n'écrit qu'une fois une image qui revient sur onze diapositives. Le
  // découpage les laissait à la dernière diapositive seulement : chacune reçoit celles qu'elle cite.
  var DEFINITION = /^ {0,3}\[([^\]\n]+)\]:[ \t]*\S.*$/;
  function partagerReferences(slides) {
    var defs = {}, nettoyees = slides.map(function (s) {
      return s.split('\n').filter(function (l) {
        var m = l.match(DEFINITION);
        if (m) { defs[m[1].toLowerCase()] = l; return false; }
        return true;
      }).join('\n').trim();
    });
    var cles = Object.keys(defs);
    if (!cles.length) return slides;
    return nettoyees.map(function (s) {
      var citees = cles.filter(function (k) { return s.toLowerCase().indexOf('][' + k + ']') !== -1; });
      return citees.length ? s + '\n\n' + citees.map(function (k) { return defs[k]; }).join('\n') : s;
    }).filter(function (s) { return s.length; });
  }

  /* ---- state -------------------------------------------------------------- */

  var deck, progressBar, counter;
  var sections = [];                  // <section.slide> per slide
  var rawSlides = [];
  var rendered = [];                  // bool per slide
  var current = 0;

  // Slide transitions — onze classiques : les cinq de départ, puis cinq de plus et le damier,
  // ajoutés en 1.3 à la demande de Patrick. Each spec returns the incoming slide's start state
  // and the outgoing slide's end state (per direction d: +1 = forward / next, -1 = backward /
  // prev). A state may carry `c`, a clip-path, for the transitions that cut rather than move.
  var TRANSITIONS = [
    { key: 'dissolve', label: TXT('Fondu') },
    { key: 'push',     label: TXT('Poussée') },
    { key: 'movein',   label: TXT('Entrée') },
    { key: 'scale',    label: TXT('Échelle') },
    { key: 'flip',     label: TXT('Retournement 3D') },
    { key: 'wipe',     label: TXT('Balayage') },
    { key: 'reveal',   label: TXT('Découverte') },
    { key: 'cube',     label: TXT('Cube') },
    { key: 'iris',     label: TXT('Iris') },
    { key: 'black',    label: TXT('Fondu au noir') },
    { key: 'checker',  label: TXT('Damier') }
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
      leave: function (d) { return { t: 'rotateY(' + (-d * 90) + 'deg)', o: 0 }; } },

    // Balayage — la suivante se dévoile par un bord, du côté d'où elle arrive.
    wipe: { dur: 600, ease: 'cubic-bezier(.4,0,.2,1)', incomingOnTop: true,
      enter: function (d) { return { t: '', o: 1, c: d > 0 ? 'inset(0 0 0 100%)' : 'inset(0 100% 0 0)' }; },
      clipEnd: 'inset(0 0 0 0)',
      leave: function () { return { t: '', o: 1 }; } },
    // Découverte — l'inverse d'« Entrée » : la diapositive courante s'écarte, dessus, et
    // découvre la suivante restée en place.
    reveal: { dur: 520, ease: 'cubic-bezier(.4,0,.2,1)', outgoingOnTop: true,
      enter: function () { return { t: '', o: 1 }; },
      leave: function (d) { return { t: 'translateX(' + (-d * 100) + '%)', o: 1 }; } },
    // Cube — deux faces qui pivotent autour de leur arête commune. Chacune tourne autour du
    // bord qu'elle partage avec l'autre, et cette arête glisse d'un côté de l'écran à l'autre.
    cube: { dur: 720, ease: 'cubic-bezier(.45,0,.25,1)', threeD: true,
      origin: function (d) { return d > 0 ? { to: '0% 50%', from: '100% 50%' }
                                            : { to: '100% 50%', from: '0% 50%' }; },
      enter: function (d) { return { t: 'translateX(' + (d * 100) + '%) rotateY(' + (d * 90) + 'deg)', o: 1 }; },
      leave: function (d) { return { t: 'translateX(' + (-d * 100) + '%) rotateY(' + (-d * 90) + 'deg)', o: 1 }; } },
    // Iris — la suivante s'ouvre en cercle depuis le centre. 75 % du rayon de référence
    // couvre les coins de n'importe quel format d'écran.
    iris: { dur: 650, ease: 'cubic-bezier(.4,0,.2,1)', incomingOnTop: true,
      enter: function () { return { t: '', o: 1, c: 'circle(0% at 50% 50%)' }; },
      clipEnd: 'circle(75% at 50% 50%)',
      leave: function () { return { t: '', o: 1 }; } },
    // Fondu au noir — un voile noir monte puis redescend (`.deck-noir`) ; les diapositives
    // s'échangent à mi-course, sous le voile. Les fondre elles-mêmes ne marcherait pas : elles
    // sont transparentes sur le fond du thème, qui basculerait d'un coup au noir.
    black: { dur: 900, ease: 'linear', throughBlack: true,
      enter: function () { return { t: '', o: 0 }; },
      leave: function () { return { t: '', o: 0 }; } },
    // Damier — la diapositive se découpe en cases, en lignes et en colonnes ; chacune pivote à
    // son tour, dans un ordre tiré au hasard, et montre au dos sa part de la suivante. Demandé
    // ainsi par Patrick : le premier damier, un balayage case par case, ne tournait rien.
    checker: { dur: 1600, ease: 'ease-in-out', cases: true,
      enter: function () { return { t: '', o: 1 }; },
      leave: function () { return { t: '', o: 1 }; } }
  };

  // Chaque case est une carte à deux faces ; chaque face porte une copie de la diapositive,
  // décalée pour n'en laisser voir que sa part. Quatre cases sur le petit côté de l'écran, et
  // ce qu'il faut sur le grand pour qu'elles restent carrées : 4 × 7 en 16:9, soit 56 copies le
  // temps d'une transition — davantage pèserait sur un iPhone quand la diapositive porte une
  // carte ou un grand diagramme.
  var DAMIER_PETIT_COTE = 4, DAMIER_TOUR = 560;
  var damierEl = null;

  function retirerDamier() {
    if (damierEl) { damierEl.remove(); damierEl = null; }
  }

  // Le fond des faces : celui du thème, sans quoi une case laisserait voir ce qui est dessous —
  // les diapositives sont transparentes sur le fond de la page.
  function fondDesCases() {
    var c = getComputedStyle(deck).backgroundColor;
    if (!c || c === 'transparent' || c === 'rgba(0, 0, 0, 0)') c = getComputedStyle(document.body).backgroundColor;
    return c;
  }

  function faceDeCase(slide, x, y, w, h, fond, dos) {
    var f = document.createElement('div');
    f.className = 'damier-face';
    f.style.background = fond;
    if (dos) f.style.transform = dos;
    var copie = slide.cloneNode(true);
    copie.removeAttribute('id');
    copie.classList.add('active');
    copie.style.cssText = 'inset:auto;left:' + (-x) + 'px;top:' + (-y) + 'px;width:' + w + 'px;height:' + h + 'px;'
      + 'opacity:1;transform:none;transition:none;clip-path:none;z-index:auto;pointer-events:none';
    f.appendChild(copie);
    return f;
  }

  function lancerDamier(fromEl, toEl, dur) {
    var w = deck.clientWidth, h = deck.clientHeight;
    var cote = Math.min(w, h) / DAMIER_PETIT_COTE;
    var colonnes = Math.max(1, Math.round(w / cote)), rangees = Math.max(1, Math.round(h / cote));
    var n = colonnes * rangees, fond = fondDesCases();
    // L'ordre de passage, tiré au hasard (Fisher-Yates).
    var ordre = [];
    for (var i = 0; i < n; i++) ordre.push(i);
    for (var j = n - 1; j > 0; j--) {
      var k = Math.floor(Math.random() * (j + 1)), tmp = ordre[j]; ordre[j] = ordre[k]; ordre[k] = tmp;
    }
    var grille = document.createElement('div');
    grille.className = 'damier';
    var cartes = [], fins = [];
    for (var r = 0; r < rangees; r++) {
      for (var c = 0; c < colonnes; c++) {
        // Bords arrondis au pixel sur la grille : deux cases voisines se touchent sans jour.
        var x = Math.round(c * w / colonnes), y = Math.round(r * h / rangees);
        var cw = Math.round((c + 1) * w / colonnes) - x, ch = Math.round((r + 1) * h / rangees) - y;
        // Chaque case tourne sur un axe et dans un sens tirés au hasard ; son dos est retourné
        // sur le même axe, pour arriver à l'endroit.
        var axe = Math.random() < 0.5 ? 'X' : 'Y', sens = Math.random() < 0.5 ? 1 : -1;
        var p = 'perspective(' + Math.round(Math.max(cw, ch) * 4) + 'px) ';
        var carte = document.createElement('div');
        carte.className = 'damier-case';
        carte.style.cssText = 'left:' + x + 'px;top:' + y + 'px;width:' + cw + 'px;height:' + ch + 'px;'
          + 'transform:' + p + 'rotate' + axe + '(0deg)';
        carte.appendChild(faceDeCase(fromEl, x, y, w, h, fond, ''));
        carte.appendChild(faceDeCase(toEl, x, y, w, h, fond, 'rotate' + axe + '(180deg)'));
        var delai = n > 1 ? Math.round(ordre[cartes.length] / (n - 1) * (dur - DAMIER_TOUR)) : 0;
        carte.style.transition = 'transform ' + DAMIER_TOUR + 'ms cubic-bezier(.45,0,.25,1) ' + delai + 'ms';
        cartes.push(carte);
        fins.push(p + 'rotate' + axe + '(' + (sens * 180) + 'deg)');
        grille.appendChild(carte);
      }
    }
    deck.appendChild(grille);
    damierEl = grille;
    void grille.offsetWidth;                     // l'état de départ, posé avant de tourner
    cartes.forEach(function (carte, i) { carte.style.transform = fins[i]; });
  }

  // Moins d'animation quand l'appareil le demande : toute transition devient un fondu. Le
  // cube et le damier, surtout, sont exactement ce que ce réglage veut éviter.
  function transitionSpec() {
    var reduit = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
    return reduit ? SPECS.dissolve : (SPECS[transition] || SPECS.dissolve);
  }
  var transition = 'dissolve';
  var animating = false, animTimer = null;

  // Colour themes — applied as a `theme-<key>` class on <body>.
  var THEMES = [
    { key: 'light',   label: TXT('Clair') },
    { key: 'dark',    label: TXT('Sombre') },
    { key: 'console', label: TXT('Console') },
    { key: 'sepia',   label: TXT('Sépia') },
    { key: 'ocean',   label: TXT('Océan') }
  ];
  var theme = 'light';

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
    // vh/CH and vw/CW are equal by construction — EXCEPT when the 640 floor above kicks
    // in, which happens on any viewport narrower than 0.89 × its height: a phone held
    // upright. The canvas is then wider than the screen, and scaling by height alone cut
    // the slide off on both sides (measured: 640 wide in a 390 window, 138 px lost each
    // side). Fitting the tighter of the two letterboxes instead of cropping.
    var s = Math.min(vh / CH, vw / CW);
    canvas.style.transform = 'scale(' + s.toFixed(4) + ')';
  }

  /* ---- rendering ---------------------------------------------------------- */

  function renderSlide(index) {
    if (rendered[index]) return Promise.resolve();
    rendered[index] = true;
    var inner = sections[index].querySelector('.slide-inner');
    return window.OKIA.renderFragment(inner, rawSlides[index])
      .then(function () {
        fitSlide(sections[index]);
        // Une diapositive vient d'apparaître : l'hôte peut la traduire. Le rendu est
        // paresseux, la traduction l'est donc aussi — on ne traduit pas six diapositives
        // que personne ne regarde encore.
        demanderTraduction(index, inner);
      })
      .catch(function () { fitSlide(sections[index]); });
  }

  /* ---- traduction --------------------------------------------------------- */

  // Rempli par l'hôte : texte d'origine → traduction. Il sert deux fois — pour reposer
  // une diapositive déjà traduite qu'on rouvre, et pour l'export PowerPoint, qui rend
  // chaque diapositive hors écran et n'a alors plus rien à demander au modèle.
  var memoireTr = {};
  var traductionActive = false;

  function demanderTraduction(index, inner) {
    if (!traductionActive || !inner) return;
    // Ce que l'on connaît déjà se repose tout de suite, sans attendre l'hôte.
    try { window.OKIA.translation.applyMemory(inner, memoireTr); } catch (e) {}
    appliquerExtras(index);
    post('slideRendered', { index: index });
  }

  /* Les libellés qui ne sont pas du texte : nœuds de diagrammes Mermaid, bulles de
     marqueurs. Ils vivent dans le SVG et la collecte de texte les ignore — c'est pourquoi
     le diaporama affichait encore ses diagrammes en italien quand tout le reste était
     traduit. */
  function collectSlideExtras(index) {
    var inner = collectRacine(index);
    if (!inner) return [];
    try {
      return window.OKIA.translation.collectExtras(inner).map(function (e) { return e.texte; });
    } catch (e) { return []; }
  }

  /* Repose les libellés connus sur une diapositive, puis la remet à l'échelle : un
     diagramme redessiné n'a plus la même hauteur. */
  function appliquerExtras(index) {
    var inner = collectRacine(index);
    if (!inner || !traductionActive) return;
    try {
      var r = window.OKIA.translation.applyExtras(memoireTr, inner);
      if (r && typeof r.then === 'function') {
        r.then(function () { if (sections[index]) fitSlide(sections[index]); });
      }
    } catch (e) {}
  }

  function collectRacine(index) {
    var section = sections[index];
    return section ? section.querySelector('.slide-inner') : null;
  }

  /* Collecte de la diapositive courante, pour que l'hôte la traduise. */
  function collectSlide(index) {
    var inner = collectRacine(index);
    return inner ? window.OKIA.translation.collect(inner) : [];
  }

  /* Tous les blocs de toutes les diapositives, y compris celles que personne n'a
     encore ouvertes. L'export PowerPoint les rend toutes hors écran : sans cette passe,
     le fichier sortirait à moitié traduit — les diapositives vues en allemand, les
     autres en français. */
  function collectAllSlides() {
    var tmp = document.createElement('div');
    tmp.className = 'slide-inner markdown-body';
    tmp.style.cssText = 'position:absolute;left:-99999px;top:0;width:1120px;';
    document.body.appendChild(tmp);
    var tous = [];
    var chain = Promise.resolve();
    rawSlides.forEach(function (md) {
      chain = chain.then(function () {
        return window.OKIA.renderFragment(tmp, md).then(function () {
          var blocs = window.OKIA.translation.collect(tmp);
          blocs.forEach(function (b) { tous.push(b); });
        });
      });
    });
    return chain.then(function () {
      try { document.body.removeChild(tmp); } catch (e) {}
      return tous;
    });
  }

  /* Les libellés hors texte de TOUTES les diapositives, y compris celles que personne n'a
     ouvertes. Le rendu du diaporama est paresseux : une diapositive jamais affichée n'a pas
     de diagramme dessiné, donc rien à collecter — et son diagramme serait resté dans la
     langue d'origine jusque dans le PowerPoint exporté. On les rend donc hors écran, comme
     pour le texte. */
  function collectAllSlidesExtras() {
    var tmp = document.createElement('div');
    tmp.className = 'slide-inner markdown-body';
    tmp.style.cssText = 'position:absolute;left:-99999px;top:0;width:1120px;';
    document.body.appendChild(tmp);
    var tous = [];
    var chain = Promise.resolve();
    rawSlides.forEach(function (md) {
      chain = chain.then(function () {
        return window.OKIA.renderFragment(tmp, md).then(function () {
          try {
            window.OKIA.translation.collectExtras(tmp).forEach(function (e) {
              if (tous.indexOf(e.texte) === -1) tous.push(e.texte);
            });
          } catch (e) {}
        });
      });
    });
    return chain.then(function () {
      try { document.body.removeChild(tmp); } catch (e) {}
      return tous;
    });
  }

  /* L'hôte annonce que la traduction est active, et livre au fur et à mesure ce qu'il a
     traduit. Une table plutôt que des blocs : le diaporama rouvre des diapositives, et
     retraduire ce qui l'a déjà été serait payer deux fois. */
  function setTranslation(actif, table) {
    traductionActive = !!actif;
    if (table) {
      for (var k in table) {
        if (Object.prototype.hasOwnProperty.call(table, k)) memoireTr[k] = table[k];
      }
    }
    if (!traductionActive) return 0;
    var faits = 0;
    for (var i = 0; i < sections.length; i++) {
      if (!rendered[i]) continue;
      var inner = collectRacine(i);
      if (!inner) continue;
      try { faits += window.OKIA.translation.applyMemory(inner, memoireTr); } catch (e) {}
      appliquerExtras(i);
    }
    return faits;
  }

  function updateChrome() {
    var total = sections.length || 1;
    progressBar.style.width = ((current + 1) / total * 100).toFixed(2) + '%';
    counter.textContent = (current + 1) + ' / ' + total;
    el('navPrev').disabled = (current === 0);
    el('navNext').disabled = (current === sections.length - 1);
    syncOverviewCurrent();
    // Le mode présentateur (1.4) : l'écran du public et l'aperçu de la suivante suivent.
    post('diapositive', { index: current, total: sections.length });
  }

  function clearAnim(elm) {
    elm.style.transition = '';
    elm.style.transform = '';
    elm.style.opacity = '';
    elm.style.zIndex = '';
    elm.style.clipPath = '';
    elm.style.transformOrigin = '';
  }

  // End any in-flight animation immediately, leaving only `keepEl` visible.
  function finishPending(keepEl) {
    if (animTimer) { clearTimeout(animTimer); animTimer = null; }
    retirerDamier();
    deck.classList.remove('deck-noir');
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
    var spec = transitionSpec();
    var dur = spec.dur;
    animating = true;

    deck.classList.toggle('deck-3d', !!spec.threeD);

    // Both slides visible during the transition. On top: the incoming slide when it is the
    // one that moves in, the outgoing one when it moves away to reveal the next (Découverte).
    toEl.classList.add('active');
    toEl.style.zIndex = spec.outgoingOnTop ? '2' : (spec.incomingOnTop ? '3' : '2');
    fromEl.style.zIndex = spec.outgoingOnTop ? '3' : '1';

    // Initial states (no animation yet).
    toEl.style.transition = 'none';
    fromEl.style.transition = 'none';
    if (spec.origin) {
      var or = spec.origin(dir);
      toEl.style.transformOrigin = or.to; fromEl.style.transformOrigin = or.from;
    }
    var e = spec.enter(dir);
    toEl.style.transform = e.t; toEl.style.opacity = e.o;
    toEl.style.clipPath = e.c || '';
    fromEl.style.transform = ''; fromEl.style.opacity = 1;

    // Force reflow so the start state is committed before we animate.
    void toEl.offsetWidth;

    var tr = function (ms, delay) {
      return ['transform', 'opacity', 'clip-path'].map(function (p) {
        return p + ' ' + ms + 'ms ' + spec.ease + (delay ? ' ' + delay + 'ms' : '');
      }).join(', ');
    };
    if (spec.cases) {
      // Les cases couvrent tout ; les deux diapositives restent immobiles dessous.
      lancerDamier(fromEl, toEl, dur);
    } else if (spec.throughBlack) {
      // Le voile fait le fondu ; les diapositives s'échangent d'un coup à mi-course, dessous.
      deck.style.setProperty('--noir-dur', dur + 'ms');
      deck.classList.add('deck-noir');
      toEl.style.transition = tr(1, dur / 2);
      fromEl.style.transition = tr(1, dur / 2);
    } else {
      toEl.style.transition = tr(dur);
      fromEl.style.transition = tr(dur);
    }
    toEl.style.transform = ''; toEl.style.opacity = 1;
    if (e.c) toEl.style.clipPath = spec.clipEnd;
    var l = spec.leave(dir);
    fromEl.style.transform = l.t; fromEl.style.opacity = l.o;

    animTimer = setTimeout(function () {
      animTimer = null;
      retirerDamier();
      fromEl.classList.remove('active');
      clearAnim(fromEl);
      clearAnim(toEl);
      deck.classList.remove('deck-3d');
      deck.classList.remove('deck-noir');
      animating = false;
      // Re-fit now that the slide is settled at full size (re-measures maps).
      fitSlide(toEl);
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
    post('choix', { transition: transition, theme: theme });
  }

  function setTheme(key) {
    if (!THEMES.some(function (t) { return t.key === key; })) return;
    theme = key;
    var b = document.body;
    THEMES.forEach(function (t) { b.classList.remove('theme-' + t.key); });
    b.classList.add('theme-' + key);
    try { localStorage.setItem('okia.theme', key); } catch (e) {}
    syncMenu();
    post('choix', { transition: transition, theme: theme });
  }

  function syncMenu() {
    var menu = el('presentMenu');
    if (!menu) return;
    Array.prototype.forEach.call(menu.querySelectorAll('.present-menu-item'), function (b) {
      var kind = b.getAttribute('data-kind'), key = b.getAttribute('data-key');
      b.classList.toggle('selected', kind === 'theme' ? key === theme : key === transition);
    });
  }

  function menuSection(title, items, kind) {
    var frag = document.createDocumentFragment();
    var h = document.createElement('div');
    h.className = 'present-menu-title';
    h.textContent = title;
    frag.appendChild(h);
    items.forEach(function (it) {
      var b = document.createElement('button');
      b.className = 'present-menu-item';
      b.setAttribute('data-kind', kind);
      b.setAttribute('data-key', it.key);
      b.textContent = it.label;
      b.onclick = function (ev) {
        ev.stopPropagation();
        if (kind === 'theme') setTheme(it.key); else setTransition(it.key);
      };
      frag.appendChild(b);
    });
    return frag;
  }

  function buildMenu() {
    var menu = el('presentMenu');
    if (!menu) return;
    menu.innerHTML = '';
    menu.appendChild(menuSection(TXT('Thème'), THEMES, 'theme'));
    menu.appendChild(menuSection(TXT('Transition'), TRANSITIONS, 'transition'));
    // Export section.
    var h = document.createElement('div');
    h.className = 'present-menu-title';
    h.textContent = TXT('Export');
    menu.appendChild(h);
    var ex = document.createElement('button');
    ex.className = 'present-menu-item';
    ex.textContent = 'PowerPoint (.pptx)';
    ex.onclick = function (e) { e.stopPropagation(); closeMenu(); post('exportPptx', {}); };
    menu.appendChild(ex);
    syncMenu();
  }

  // Build the presentation export model: render each slide off-screen and collect
  // its blocks (the first heading becomes the slide title). Mermaid is rasterised
  // by OKIA.exportModel; maps become a marker list.
  function buildExportModel() {
    var tmp = document.createElement('div');
    tmp.className = 'slide-inner markdown-body';
    tmp.style.cssText = 'position:absolute;left:-99999px;top:0;width:1120px;';
    document.body.appendChild(tmp);
    var out = [];

    // Lire une diapositive rendue et l'ajouter au modèle. Le premier titre devient le
    // titre de la diapositive.
    function lireModele() {
      return window.OKIA.exportModel(tmp).then(function (blocks) {
        var title = [];
        if (blocks.length && blocks[0].t === 'heading') { title = blocks[0].runs; blocks = blocks.slice(1); }
        out.push({ title: title, blocks: blocks });
      });
    }

    var chain = Promise.resolve();
    rawSlides.forEach(function (md) {
      chain = chain.then(function () {
        return window.OKIA.renderFragment(tmp, md).then(function () {
          // Le modèle d'export se lit dans le DOM : on y repose la traduction avant de
          // lire, sinon le fichier PowerPoint sortirait dans la langue d'origine alors
          // que le diaporama, lui, est traduit à l'écran.
          if (!traductionActive) return lireModele();
          try { window.OKIA.translation.applyMemory(tmp, memoireTr); } catch (e) {}
          // Les diagrammes sont rastérisés par exportModel : leurs libellés doivent être
          // traduits ET redessinés avant la lecture, sinon le PowerPoint porte des images
          // restées dans la langue d'origine.
          var pret = null;
          try { pret = window.OKIA.translation.applyExtras(memoireTr, tmp); } catch (e) {}
          return (pret && typeof pret.then === 'function')
            ? pret.then(lireModele)
            : lireModele();
        });
      });
    });
    // La transition choisie voyage avec le modèle : le PowerPoint la rejoue sur chaque
    // diapositive. C'est le choix du présentateur, pas l'éventuel fondu de « Réduire les
    // animations » — ce réglage-là appartient à l'appareil qui projettera le fichier.
    return chain.then(function () { try { document.body.removeChild(tmp); } catch (e) {} return { slides: out, transition: transition }; });
  }

  function openMenu()  { var m = el('presentMenu'); if (m) { m.hidden = false; syncMenu(); } }
  function closeMenu() { var m = el('presentMenu'); if (m) m.hidden = true; }
  function toggleMenu(ev) {
    if (ev) ev.stopPropagation();
    var m = el('presentMenu');
    if (m) { if (m.hidden) openMenu(); else closeMenu(); }
  }

  /* ---- overview / slide navigator ----------------------------------------- */

  function slideTitle(index) {
    var el2 = sections[index] && sections[index].querySelector('h1, h2, h3');
    var t = el2 ? el2.textContent.trim() : '';
    if (!t) {
      var m = rawSlides[index].match(/^#{1,3}\s+(.+?)\s*$/m);
      t = m ? m[1].trim() : '';
    }
    return t || ('Diapositive ' + (index + 1));
  }

  // Fill a thumbnail "stage" with a scaled-down clone of the rendered slide.
  function fillThumb(stage, index) {
    var src = sections[index].querySelector('.slide-inner');
    if (!src) return;
    var w = CW || 1280, h = CH;
    stage.style.width = w + 'px';
    stage.style.height = h + 'px';
    stage.innerHTML = '';

    var pad = document.createElement('div');
    pad.className = 'overview-stage-pad';
    var clone = src.cloneNode(true);
    clone.style.transform = '';
    clone.style.maxWidth = 'none';
    clone.style.width = '100%';
    // Interactive maps don't clone — show a placeholder instead.
    clone.querySelectorAll('.okia-map').forEach(function (m) {
      var ph = document.createElement('div');
      ph.className = 'overview-map-ph';
      ph.textContent = '🗺';
      m.parentNode.replaceChild(ph, m);
    });
    pad.appendChild(clone);
    stage.appendChild(pad);

    var frame = stage.parentNode;
    var fw = frame.clientWidth || 260;
    var scale = fw / w;
    stage.style.transform = 'scale(' + scale + ')';
    frame.style.height = (h * scale) + 'px';
  }

  function buildOverview() {
    var grid = el('overviewGrid');
    if (!grid) return;
    grid.innerHTML = '';
    var thumbs = [];
    rawSlides.forEach(function (_, i) {
      var item = document.createElement('button');
      item.className = 'overview-item' + (i === current ? ' current' : '');
      item.setAttribute('data-index', i);

      var frame = document.createElement('div');
      frame.className = 'overview-frame';
      var stage = document.createElement('div');
      stage.className = 'overview-stage';
      frame.appendChild(stage);
      var num = document.createElement('span');
      num.className = 'overview-num';
      num.textContent = (i + 1);
      frame.appendChild(num);
      item.appendChild(frame);

      var label = document.createElement('div');
      label.className = 'overview-label';
      label.textContent = slideTitle(i);
      item.appendChild(label);

      item.onclick = function () { closeOverview(); show(i); };
      grid.appendChild(item);
      thumbs.push({ stage: stage, index: i });
    });

    // Render every slide (sequentially, to avoid concurrent mermaid runs), then
    // fill its thumbnail. Already-rendered slides resolve instantly.
    var chain = Promise.resolve();
    thumbs.forEach(function (t) {
      chain = chain.then(function () {
        return renderSlide(t.index).then(function () { fillThumb(t.stage, t.index); });
      });
    });
  }

  function syncOverviewCurrent() {
    var grid = el('overviewGrid');
    if (!grid) return;
    Array.prototype.forEach.call(grid.querySelectorAll('.overview-item'), function (it) {
      it.classList.toggle('current', +it.getAttribute('data-index') === current);
    });
  }

  function openOverview() {
    var ov = el('presentOverview');
    if (!ov) return;
    closeMenu();
    ov.hidden = false;
    buildOverview();
    var cur = ov.querySelector('.overview-item.current');
    if (cur) cur.scrollIntoView({ block: 'center' });
  }
  function closeOverview() { var ov = el('presentOverview'); if (ov) ov.hidden = true; }
  function toggleOverview(ev) {
    if (ev) ev.stopPropagation();
    var ov = el('presentOverview');
    if (ov) { if (ov.hidden) openOverview(); else closeOverview(); }
  }

  // Escape priority: close overview, then the menu, otherwise leave the show.
  function escape() {
    var ov = el('presentOverview');
    if (ov && !ov.hidden) { closeOverview(); return; }
    var m = el('presentMenu');
    if (m && !m.hidden) { closeMenu(); return; }
    exit();
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
    // L'écran du public et l'aperçu ne se pilotent pas : ils suivent le présentateur.
    if (modeAffichage !== 'complet') { touchX = null; return; }
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

  // Localise the static chrome of presentation.html (authored in French).
  function localizeChrome() {
    function setLabel(id, fr) {
      var n = el(id);
      if (n) n.setAttribute('aria-label', TXT(fr));
    }
    setLabel('navPrev', 'Diapositive précédente');
    setLabel('navNext', 'Diapositive suivante');
    setLabel('presentEnd', 'Quitter le diaporama');
    setLabel('presentMenuBtn', 'Transitions');
    setLabel('presentGridBtn', 'Vue d’ensemble des diapositives');
    setLabel('presentAnnotBtn', 'Annoter');
    setLabel('presentDuoBtn', 'Présenter sur un second écran');
    setLabel('overviewClose', 'Fermer');
    var t = document.querySelector('.overview-title');
    if (t) t.textContent = TXT('Diapositives');
  }

  function start(md) {
    deck = el('deck');
    progressBar = el('progressBar');
    counter = el('counter');
    localizeChrome();

    rawSlides = splitSlides(md || '');
    if (!rawSlides.length) rawSlides = [' '];
    current = 0;
    build();

    // Restore the saved transition + theme choices.
    try {
      var saved = localStorage.getItem('okia.transition');
      if (saved && SPECS[saved]) transition = saved;
      var savedTheme = localStorage.getItem('okia.theme');
      if (savedTheme && THEMES.some(function (t) { return t.key === savedTheme; })) theme = savedTheme;
    } catch (e) {}
    var demandee = transitionDuDocument(md || '');
    if (demandee) transition = demandee;
    buildMenu();
    setTheme(theme);   // apply the theme class to <body>

    sections[0].classList.add('active');
    updateChrome();
    renderSlide(0).then(function () { fitSlide(sections[0]); });
    if (sections.length > 1) renderSlide(1);

    el('navPrev').onclick = function (e) { e.stopPropagation(); prev(); };
    el('navNext').onclick = function (e) { e.stopPropagation(); next(); };
    el('presentEnd').onclick = function (e) { e.stopPropagation(); exit(); };
    var menuBtn = el('presentMenuBtn');
    if (menuBtn) menuBtn.onclick = toggleMenu;
    var gridBtn = el('presentGridBtn');
    if (gridBtn) gridBtn.onclick = toggleOverview;
    // Option Analytic (1.4) : le mode « Annoter » est tenu par l'hôte (le calque PencilKit).
    var annotBtn = el('presentAnnotBtn');
    if (annotBtn) annotBtn.onclick = function (e) { e.stopPropagation(); closeMenu(); post('annoter', {}); };
    var duoBtn = el('presentDuoBtn');
    if (duoBtn) duoBtn.onclick = function (e) { e.stopPropagation(); closeMenu(); post('presentateur', {}); };
    var ovClose = el('overviewClose');
    if (ovClose) ovClose.onclick = function (e) { e.stopPropagation(); closeOverview(); };
    // Tap anywhere else closes the transition menu.
    document.addEventListener('click', closeMenu);

    window.addEventListener('resize', onResize);
    window.addEventListener('orientationchange', onResize);
    deck.addEventListener('touchstart', onTouchStart, { passive: true });
    deck.addEventListener('touchend', onTouchEnd, { passive: true });

    try { window.focus(); } catch (e) {}
    post('presentStarted', { count: sections.length });
  }

  /* ---- chantier : la présentation qui se construit -------------------------- */
  // Pendant la conversion d'un rapport, l'app envoie les diapositives prêtes au fur et à
  // mesure. Chacune est rendue par le même moteur que le diaporama — même thème, mêmes
  // images, cartes et diagrammes — dans une vignette, sous la précédente. La dernière à
  // venir est annoncée par une case en attente. Rien ne se rend deux fois : seule une
  // diapositive dont le texte a changé repasse au rendu.
  var chantierEl = null, chantierMd = [], chantierFile = Promise.resolve();
  // La vue suit la dernière diapositive, sauf si le lecteur fait défiler lui-même : remonté voir
  // une diapositive plus ancienne, il n'est pas ramené en bas ; redescendu en bas, il suit de
  // nouveau. Seuls ses gestes comptent — le défilement animé de la vue ne décide de rien.
  var suivreLaFin = true;

  function preparerChantier() {
    if (chantierEl) return;
    document.body.classList.add('present-chantier');
    try {
      var savedTheme = localStorage.getItem('okia.theme');
      if (savedTheme && THEMES.some(function (t) { return t.key === savedTheme; })) theme = savedTheme;
    } catch (e) {}
    setTheme(theme);
    chantierEl = document.createElement('div');
    chantierEl.id = 'chantier';
    chantierEl.className = 'chantier';
    document.body.appendChild(chantierEl);
    var geste = null;
    function aPrisLaMain() {
      clearTimeout(geste);
      geste = setTimeout(function () {
        var bas = chantierEl.scrollHeight - chantierEl.scrollTop - chantierEl.clientHeight;
        suivreLaFin = bas < 150;
      }, 250);
    }
    ['wheel', 'touchmove', 'keydown'].forEach(function (type) {
      chantierEl.addEventListener(type, aPrisLaMain, { passive: true });
    });
    window.addEventListener('resize', function () {
      clearTimeout(resizeTimer);
      resizeTimer = setTimeout(function () {
        Array.prototype.forEach.call(chantierEl.querySelectorAll('.chantier-frame'), echelleVignette);
      }, 120);
    });
  }

  // La diapositive garde sa taille de conception (1280 × 720) ; la vignette la réduit.
  function echelleVignette(frame) {
    var section = frame.querySelector('.slide');
    if (!section) return;
    section.style.transform = 'scale(' + ((frame.clientWidth || 320) / 1280).toFixed(4) + ')';
  }

  function itemChantier(i) {
    var items = chantierEl.querySelectorAll('.chantier-item:not(.chantier-attente)');
    if (items[i]) return items[i];
    var item = document.createElement('div');
    item.className = 'chantier-item chantier-neuve';
    var frame = document.createElement('div');
    frame.className = 'chantier-frame';
    var section = document.createElement('section');
    section.className = 'slide active chantier-slide';
    var canvas = document.createElement('div');
    canvas.className = 'slide-canvas';
    var inner = document.createElement('div');
    inner.className = 'slide-inner markdown-body';
    canvas.appendChild(inner);
    section.appendChild(canvas);
    frame.appendChild(section);
    var num = document.createElement('span');
    num.className = 'overview-num';
    num.textContent = i + 1;
    frame.appendChild(num);
    item.appendChild(frame);
    var attente = chantierEl.querySelector('.chantier-attente');
    chantierEl.insertBefore(item, attente);
    echelleVignette(frame);
    return item;
  }

  function rendreVignette(i, md) {
    var item = itemChantier(i);
    var section = item.querySelector('.slide');
    var inner = item.querySelector('.slide-inner');
    section.classList.remove('slide-map');
    // Une diapositive qui échoue au rendu garde son texte brut ; elle ne bloque pas la file.
    var rendu;
    try { rendu = Promise.resolve(window.OKIA.renderFragment(inner, md)); }
    catch (e) { rendu = Promise.resolve(); }
    return rendu
      .catch(function () {})
      .then(function () {
        fitSlide(section);
        echelleVignette(item.querySelector('.chantier-frame'));
        if (item.classList.contains('chantier-neuve')) {
          void item.offsetWidth;
          item.classList.remove('chantier-neuve');
          if (suivreLaFin) {
            (chantierEl.querySelector('.chantier-attente') || item)
              .scrollIntoView({ behavior: 'smooth', block: 'end' });
          }
        }
      });
  }

  // La case de la prochaine diapositive, tant que la conversion n'est pas finie.
  function caseEnAttente(numero, visible) {
    var attente = chantierEl.querySelector('.chantier-attente');
    if (!visible) { if (attente) attente.remove(); return; }
    if (!attente) {
      attente = document.createElement('div');
      attente.className = 'chantier-item chantier-attente';
      attente.innerHTML = '<div class="chantier-frame"><div class="chantier-lueur"></div>' +
        '<span class="overview-num"></span></div>';
      chantierEl.appendChild(attente);
    }
    attente.querySelector('.overview-num').textContent = numero;
  }

  // payload : { slides: [markdown…] } pendant la conversion, ou { md: "…" } une fois finie ;
  // prevues : le nombre attendu ; fini : plus rien à attendre.
  function chantier(payload) {
    preparerChantier();
    // Les blancs autour d'une diapositive ne comptent pas : la présentation enregistrée, une
    // fois finie, ne doit pas faire repasser au rendu celles déjà montrées en route.
    var slides = (payload.slides || splitSlides(payload.md || ''))
      .map(function (md) { return String(md).trim(); })
      .filter(function (md) { return md.length > 0; });
    slides.forEach(function (md, i) {
      if (chantierMd[i] === md) return;
      chantierMd[i] = md;
      chantierFile = chantierFile
        .then(function () { return rendreVignette(i, md); })
        .catch(function (e) { console.error('chantier', i, e); });
    });
    chantierFile = chantierFile.then(function () {
      var items = chantierEl.querySelectorAll('.chantier-item:not(.chantier-attente)');
      for (var k = items.length - 1; k >= slides.length; k--) items[k].remove();
      chantierMd.length = Math.min(chantierMd.length, slides.length);
      caseEnAttente(slides.length + 1, !payload.fini && slides.length < (payload.prevues || 0));
    });
  }

  /* ---- mode présentateur (1.4) ------------------------------------------- */

  // « complet » : le diaporama habituel. « public » : la diapositive seule, sans aucun bouton —
  // l'écran externe ou la fenêtre du projecteur. « apercu » : la diapositive suivante, dans la
  // vue du présentateur, sans transition.
  var modeAffichage = 'complet';
  function mode(m) {
    modeAffichage = m;
    document.body.classList.toggle('present-public', m === 'public');
    document.body.classList.toggle('present-apercu', m === 'apercu');
  }

  // Aller à une diapositive, sur ordre de l'hôte. `instantane` : sans transition (l'aperçu, ou
  // l'écran du public qui arrive en cours de séance).
  function aller(index, instantane) {
    if (index < 0 || index >= sections.length) return;
    if (!instantane) { show(index); return; }
    finishPending(sections[index]);
    sections[current].classList.remove('active');
    current = index;
    sections[index].classList.add('active');
    renderSlide(index).then(function () { fitSlide(sections[index]); });
    fitSlide(sections[index]);
    updateChrome();
  }

  // Les notes de l'orateur d'une diapositive : ses commentaires HTML (l'import PowerPoint y range
  // les notes et les commentaires), sans les marques internes de l'import.
  function notes(index) {
    var md = rawSlides[index] || '', out = [], re = /<!--([\s\S]*?)-->/g, m;
    while ((m = re.exec(md))) {
      var t = m[1].trim();
      // L'en-tête que l'import PowerPoint pose (« Notes de l’orateur : »), dans les cinq langues :
      // la colonne du présentateur a déjà son titre.
      t = t.replace(/^(Notes de l’orateur|Speaker notes|Sprechernotizen|Notas del orador|Note del relatore)\s*:\s*\n/, '').trim();
      if (t && !/^consigne:\d+$/.test(t)) out.push(t);
    }
    return out.join('\n\n');
  }

  // Le présentateur change de transition ou de thème : le public suit.
  function appliquerChoix(c) {
    if (c && c.transition && SPECS[c.transition]) { transition = c.transition; syncMenu(); }
    if (c && c.theme) {
      var b = document.body;
      THEMES.forEach(function (t) { b.classList.remove('theme-' + t.key); });
      if (THEMES.some(function (t) { return t.key === c.theme; })) { theme = c.theme; b.classList.add('theme-' + theme); }
    }
  }

  // L'hôte montre le bouton « Présentateur » sur Mac, avec l'option.
  function permettrePresentateur(oui) { var b = el('presentDuoBtn'); if (b) b.hidden = !oui; }

  // L'hôte montre le bouton « Annoter » quand l'option est acquise, et le dit actif pendant
  // l'annotation.
  function permettreAnnotation(oui) { var b = el('presentAnnotBtn'); if (b) b.hidden = !oui; }
  function annotationActive(oui) {
    var b = el('presentAnnotBtn');
    if (b) b.classList.toggle('actif', !!oui);
  }

  window.OKIA_PRESENT = { start: start, chantier: chantier, next: next, prev: prev, exit: exit,
                          permettreAnnotation: permettreAnnotation, annotationActive: annotationActive,
                          mode: mode, aller: aller, notes: notes, appliquerChoix: appliquerChoix,
                          permettrePresentateur: permettrePresentateur,
                          collectSlide: collectSlide, collectAllSlides: collectAllSlides,
                          collectSlideExtras: collectSlideExtras,
                          collectAllSlidesExtras: collectAllSlidesExtras,
                          setTranslation: setTranslation,
                          setTransition: setTransition, setTheme: setTheme, escape: escape,
                          toggleOverview: toggleOverview, exportModel: buildExportModel };
  post('presentReady', {});
})();
