import Foundation

// 1.5.1 — Les textes du coffre expliqué (AGENTS.md, CLAUDE.md, les index de `.mdviewer/`) dans les
// quinze langues de l'app : un assistant les lit dans la langue de l'utilisateur (Patrick,
// 26/11/2026 : « les consignes sont à placer dans la langue de l'utilisateur »).
// Fichier généré à partir des traductions ; les chemins, les noms de fichiers et les clés YAML
// (`coffre md viewer`, `titre`, `date`…) restent tels quels : ce sont ceux que l'app écrit.

extension CoffreExplique {

    struct Textes: Sendable {
        let agents: String
        let claude: String
        let indexTitre: String
        /// `%d` : le nombre de documents.
        let indexIntro: String
        let indexColonnes: [String]
        let entitesTitre: String
        let entitesIntro: String
        let entitesColonnes: [String]

        /// La langue de l'app (`Localization.code`) ; l'anglais pour une langue inconnue.
        nonisolated static func pour(_ code: String) -> Textes {
            if let t = tous[code] { return t }
            if let t = tous.first(where: { code.hasPrefix($0.key) || $0.key.hasPrefix(code) })?.value { return t }
            return tous["en"]!
        }

        nonisolated private static let tous: [String: Textes] = [
            "fr": Textes(
                agents: """
            # Ce coffre, pour les assistants

            Ce dossier est un coffre de **md Viewer** (ok-ia.ch) : des documents Markdown. md Viewer a écrit ce
            fichier et le tient à jour. Pour y mettre vos propres consignes, retirez la première ligne : md Viewer
            ne le touchera plus.

            ## Où trouver quoi

            - `.mdviewer/index.md` : tous les documents, un par ligne, avec leur titre, leur date et leur source.
              Commencez par lui ; `index.json` en est la version pour les programmes.
            - `.mdviewer/entites.md` (après l'analyse du coffre) : les personnes, organisations, lieux… et les
              documents où ils apparaissent ; `entites.json` donne la liste des documents de chacun.
            - `coffre md viewer/AAAA/MM/` : les documents importés dans md Viewer (Word, PDF, PowerPoint, pages
              web…), rangés par année et par mois.
            - Les dossiers `rapports-…` : des rapports de fornews.ai. Les autres dossiers sont ceux de
              l'utilisateur.

            ## Lire un document

            - Un en-tête YAML facultatif entre deux lignes `---` : `titre` ou `title`, `date`, `source` ou `url`,
              `auteur`, `tags`.
            - Un diaporama : les diapositives sont séparées par une ligne `---` ; les commentaires HTML
              `<!-- … -->` d'une diapositive sont les notes de l'orateur.
            - Les blocs ```` ```mermaid ```` sont des diagrammes, ```` ```leaflet ```` des cartes ; `$…$` et
              `$$…$$` des formules en LaTeX.
            - Les rapports de fornews.ai ont une section « Entités » : des noms classés par genre, souvent
              reliés à Wikidata.
            - Un bloc `<!-- md-viewer-annotations … -->` à la fin d'un fichier garde les surlignages et les notes
              de l'utilisateur : ne le modifiez jamais et ne le recopiez pas.
            - Des images sont parfois intégrées en `data:` (base64) : vous pouvez les ignorer.

            ## Citer

            Citez chaque document par son chemin depuis la racine du coffre et son titre, par exemple :
            `coffre md viewer/2026/11/budget.md` — « Le budget 2027 ». N'avancez aucun fait, chiffre ou date
            qui ne soit dans un document.

            ## Écrire

            - Ne supprimez, ne déplacez et ne renommez aucun fichier sans que l'utilisateur le demande.
            - Un nouveau document va de préférence dans `coffre md viewer/AAAA/MM/`, avec un en-tête YAML
              (`titre`, `date`).
            - Ne modifiez pas le dossier `.mdviewer/` : md Viewer le réécrit.

            """,
                claude: "Les consignes pour ce coffre sont dans AGENTS.md :",
                indexTitre: "Index du coffre",
                indexIntro: "%d documents, du plus récent au plus ancien. Écrit par md Viewer ; ne pas modifier.",
                indexColonnes: ["Document", "Titre", "Date", "Source", "Étiquettes"],
                entitesTitre: "Les entités du coffre",
                entitesIntro: "Trouvées par l'analyse du coffre de md Viewer, les plus présentes d'abord. Le détail, avec les documents, est dans `entites.json`.",
                entitesColonnes: ["Nom", "Genre", "Wikidata", "Documents", "Première", "Dernière", "Souvent avec"]),
            "en": Textes(
                agents: """
            # This vault, for assistants

            This folder is an **md Viewer** vault (ok-ia.ch): Markdown documents. md Viewer wrote this file and
            keeps it up to date. To put your own instructions here, remove the first line: md Viewer will not
            touch it again.

            ## Where to find what

            - `.mdviewer/index.md`: every document, one per line, with its title, date and source. Start there;
              `index.json` is the version for programs.
            - `.mdviewer/entites.md` (after the vault analysis): people, organizations, places… and the documents
              they appear in; `entites.json` lists each one's documents.
            - `coffre md viewer/YYYY/MM/`: documents imported into md Viewer (Word, PDF, PowerPoint, web
              pages…), filed by year and month.
            - `rapports-…` folders: reports from fornews.ai. Other folders are the user's own.

            ## Reading a document

            - An optional YAML header between two `---` lines: `titre` or `title`, `date`, `source` or `url`,
              `auteur` (author), `tags`.
            - A slideshow: slides are separated by a `---` line; the HTML comments `<!-- … -->` of a slide are
              the speaker notes.
            - ```` ```mermaid ```` blocks are diagrams, ```` ```leaflet ```` blocks are maps; `$…$` and `$$…$$`
              are LaTeX formulas.
            - fornews.ai reports have an "Entités" section: names grouped by kind, often linked to Wikidata.
            - A `<!-- md-viewer-annotations … -->` block at the end of a file holds the user's highlights and
              notes: never edit it and do not copy it.
            - Images are sometimes embedded as `data:` (base64): you can ignore them.

            ## Citing

            Cite each document by its path from the vault root and its title, for example:
            `coffre md viewer/2026/11/budget.md` — "Le budget 2027". State no fact, figure or date that is not
            in a document.

            ## Writing

            - Do not delete, move or rename any file unless the user asks.
            - A new document preferably goes in `coffre md viewer/YYYY/MM/`, with a YAML header (`titre`,
              `date`).
            - Do not edit the `.mdviewer/` folder: md Viewer rewrites it.

            """,
                claude: "The instructions for this vault are in AGENTS.md:",
                indexTitre: "Vault index",
                indexIntro: "%d documents, newest first. Written by md Viewer; do not edit.",
                indexColonnes: ["Document", "Title", "Date", "Source", "Tags"],
                entitesTitre: "Entities in the vault",
                entitesIntro: "Found by md Viewer's vault analysis, most frequent first. The details, with the documents, are in `entites.json`.",
                entitesColonnes: ["Name", "Kind", "Wikidata", "Documents", "First", "Last", "Often with"]),
            "de": Textes(
                agents: """
            # Diese Ablage, für Assistenten

            Dieser Ordner ist eine Ablage von **md Viewer** (ok-ia.ch): Markdown-Dokumente. md Viewer hat diese Datei geschrieben und hält sie aktuell. Um eigene Anweisungen einzutragen, entfernen Sie die erste Zeile: md Viewer rührt die Datei dann nicht mehr an.

            ## Wo was liegt

            - `.mdviewer/index.md`: alle Dokumente, eines pro Zeile, mit Titel, Datum und Quelle. Beginnen Sie dort; `index.json` ist die Fassung für Programme.
            - `.mdviewer/entites.md` (nach der Analyse der Ablage): Personen, Organisationen, Orte… und die Dokumente, in denen sie vorkommen; `entites.json` listet die Dokumente jedes Eintrags.
            - `coffre md viewer/JJJJ/MM/`: in md Viewer importierte Dokumente (Word, PDF, PowerPoint, Webseiten…), nach Jahr und Monat abgelegt.
            - Ordner `rapports-…`: Berichte von fornews.ai. Alle anderen Ordner gehören dem Benutzer.

            ## Ein Dokument lesen

            - Ein optionaler YAML-Kopf zwischen zwei Zeilen `---`: `titre` oder `title`, `date`, `source` oder `url`, `auteur` (Autor), `tags`.
            - Eine Diashow: Die Folien sind durch eine Zeile `---` getrennt; die HTML-Kommentare `<!-- … -->` einer Folie sind die Sprechernotizen.
            - Blöcke ```` ```mermaid ```` sind Diagramme, ```` ```leaflet ```` Karten; `$…$` und `$$…$$` sind LaTeX-Formeln.
            - Berichte von fornews.ai haben einen Abschnitt „Entités“: Namen nach Art geordnet, oft mit Wikidata verknüpft.
            - Ein Block `<!-- md-viewer-annotations … -->` am Ende einer Datei enthält die Markierungen und Notizen des Benutzers: Ändern Sie ihn nie und kopieren Sie ihn nicht.
            - Bilder sind manchmal als `data:` (base64) eingebettet: Sie können sie ignorieren.

            ## Zitieren

            Zitieren Sie jedes Dokument mit seinem Pfad ab der Wurzel der Ablage und seinem Titel, zum Beispiel: `coffre md viewer/2026/11/budget.md` – „Das Budget 2027“. Nennen Sie keine Tatsache, Zahl oder Datum, die nicht in einem Dokument stehen.

            ## Schreiben

            - Löschen, verschieben oder benennen Sie keine Datei um, ohne dass der Benutzer es verlangt.
            - Ein neues Dokument gehört vorzugsweise nach `coffre md viewer/JJJJ/MM/`, mit einem YAML-Kopf (`titre`, `date`).
            - Ändern Sie den Ordner `.mdviewer/` nicht: md Viewer schreibt ihn neu.

            """,
                claude: "Die Anweisungen für diese Ablage stehen in AGENTS.md:",
                indexTitre: "Index der Ablage",
                indexIntro: "%d Dokumente, das neueste zuerst. Von md Viewer geschrieben; nicht bearbeiten.",
                indexColonnes: ["Dokument", "Titel", "Datum", "Quelle", "Schlagwörter"],
                entitesTitre: "Die Entitäten der Ablage",
                entitesIntro: "Gefunden von der Analyse der Ablage in md Viewer, die häufigsten zuerst. Die Einzelheiten, mit den Dokumenten, stehen in `entites.json`.",
                entitesColonnes: ["Name", "Art", "Wikidata", "Dokumente", "Erstes", "Letztes", "Oft mit"]),
            "es": Textes(
                agents: """
            # Este archivo, para los asistentes

            Esta carpeta es un archivo de **md Viewer** (ok-ia.ch): documentos Markdown. md Viewer ha escrito este fichero y lo mantiene al día. Para poner aquí tus propias instrucciones, quita la primera línea: md Viewer ya no lo tocará.

            ## Dónde está cada cosa

            - `.mdviewer/index.md`: todos los documentos, uno por línea, con su título, su fecha y su fuente. Empieza por él; `index.json` es la versión para programas.
            - `.mdviewer/entites.md` (tras el análisis del archivo): personas, organizaciones, lugares… y los documentos donde aparecen; `entites.json` da la lista de documentos de cada uno.
            - `coffre md viewer/AAAA/MM/`: los documentos importados en md Viewer (Word, PDF, PowerPoint, páginas web…), ordenados por año y mes.
            - Las carpetas `rapports-…`: informes de fornews.ai. Las demás carpetas son del usuario.

            ## Leer un documento

            - Un encabezado YAML opcional entre dos líneas `---`: `titre` o `title`, `date`, `source` o `url`, `auteur` (autor), `tags`.
            - Una presentación: las diapositivas se separan con una línea `---`; los comentarios HTML `<!-- … -->` de una diapositiva son las notas del orador.
            - Los bloques ```` ```mermaid ```` son diagramas, ```` ```leaflet ```` mapas; `$…$` y `$$…$$` son fórmulas LaTeX.
            - Los informes de fornews.ai tienen una sección «Entités»: nombres clasificados por tipo, a menudo enlazados con Wikidata.
            - Un bloque `<!-- md-viewer-annotations … -->` al final de un fichero guarda los subrayados y las notas del usuario: no lo modifiques nunca ni lo copies.
            - A veces hay imágenes incrustadas como `data:` (base64): puedes ignorarlas.

            ## Citar

            Cita cada documento por su ruta desde la raíz del archivo y su título, por ejemplo: `coffre md viewer/2026/11/budget.md` — «El presupuesto 2027». No afirmes ningún hecho, cifra o fecha que no esté en un documento.

            ## Escribir

            - No borres, muevas ni renombres ningún fichero sin que el usuario lo pida.
            - Un documento nuevo va preferentemente en `coffre md viewer/AAAA/MM/`, con un encabezado YAML (`titre`, `date`).
            - No modifiques la carpeta `.mdviewer/`: md Viewer la reescribe.

            """,
                claude: "Las instrucciones para este archivo están en AGENTS.md:",
                indexTitre: "Índice del archivo",
                indexIntro: "%d documentos, del más reciente al más antiguo. Escrito por md Viewer; no modificar.",
                indexColonnes: ["Documento", "Título", "Fecha", "Fuente", "Etiquetas"],
                entitesTitre: "Las entidades del archivo",
                entitesIntro: "Encontradas por el análisis del archivo de md Viewer, las más presentes primero. El detalle, con los documentos, está en `entites.json`.",
                entitesColonnes: ["Nombre", "Tipo", "Wikidata", "Documentos", "Primera", "Última", "A menudo con"]),
            "it": Textes(
                agents: """
            # Questo archivio, per gli assistenti

            Questa cartella è un archivio di **md Viewer** (ok-ia.ch): documenti Markdown. md Viewer ha scritto questo file e lo tiene aggiornato. Per inserire qui le tue istruzioni, togli la prima riga: md Viewer non lo toccherà più.

            ## Dove trovare cosa

            - `.mdviewer/index.md`: tutti i documenti, uno per riga, con titolo, data e fonte. Comincia da qui; `index.json` ne è la versione per i programmi.
            - `.mdviewer/entites.md` (dopo l'analisi dell'archivio): persone, organizzazioni, luoghi… e i documenti in cui compaiono; `entites.json` elenca i documenti di ciascuno.
            - `coffre md viewer/AAAA/MM/`: i documenti importati in md Viewer (Word, PDF, PowerPoint, pagine web…), ordinati per anno e mese.
            - Le cartelle `rapports-…`: rapporti di fornews.ai. Le altre cartelle sono dell'utente.

            ## Leggere un documento

            - Un'intestazione YAML facoltativa tra due righe `---`: `titre` o `title`, `date`, `source` o `url`, `auteur` (autore), `tags`.
            - Una presentazione: le diapositive sono separate da una riga `---`; i commenti HTML `<!-- … -->` di una diapositiva sono le note del relatore.
            - I blocchi ```` ```mermaid ```` sono diagrammi, ```` ```leaflet ```` mappe; `$…$` e `$$…$$` sono formule LaTeX.
            - I rapporti di fornews.ai hanno una sezione «Entités»: nomi ordinati per tipo, spesso collegati a Wikidata.
            - Un blocco `<!-- md-viewer-annotations … -->` alla fine di un file conserva le evidenziazioni e le note dell'utente: non modificarlo mai e non copiarlo.
            - A volte le immagini sono incorporate come `data:` (base64): puoi ignorarle.

            ## Citare

            Cita ogni documento con il suo percorso dalla radice dell'archivio e il suo titolo, per esempio: `coffre md viewer/2026/11/budget.md` — «Il bilancio 2027». Non affermare fatti, cifre o date che non siano in un documento.

            ## Scrivere

            - Non eliminare, spostare né rinominare alcun file senza che l'utente lo chieda.
            - Un nuovo documento va di preferenza in `coffre md viewer/AAAA/MM/`, con un'intestazione YAML (`titre`, `date`).
            - Non modificare la cartella `.mdviewer/`: md Viewer la riscrive.

            """,
                claude: "Le istruzioni per questo archivio sono in AGENTS.md:",
                indexTitre: "Indice dell'archivio",
                indexIntro: "%d documenti, dal più recente al più vecchio. Scritto da md Viewer; non modificare.",
                indexColonnes: ["Documento", "Titolo", "Data", "Fonte", "Etichette"],
                entitesTitre: "Le entità dell'archivio",
                entitesIntro: "Trovate dall'analisi dell'archivio di md Viewer, le più presenti prima. Il dettaglio, con i documenti, è in `entites.json`.",
                entitesColonnes: ["Nome", "Tipo", "Wikidata", "Documenti", "Prima", "Ultima", "Spesso con"]),
            "ja": Textes(
                agents: """
            # この保管庫について（アシスタント向け）

            このフォルダは **md Viewer**（ok-ia.ch）の保管庫で、Markdown書類が入っています。このファイルはmd Viewerが書き、最新の状態に保っています。独自の指示を書き込むには、1行目を削除してください。以後md Viewerはこのファイルに触れません。

            ## どこに何があるか

            - `.mdviewer/index.md`：すべての書類を1行に1件ずつ、タイトル、日付、出典付きで掲載。まずここから始めてください。`index.json` はプログラム向けの版です。
            - `.mdviewer/entites.md`（保管庫の分析後）：人物、組織、場所など、およびそれらが登場する書類。`entites.json` には項目ごとの書類一覧があります。
            - `coffre md viewer/YYYY/MM/`：md Viewerに読み込まれた書類（Word、PDF、PowerPoint、Webページなど）を年月別に整理。
            - `rapports-…` フォルダ：fornews.ai のレポート。そのほかのフォルダはユーザーのものです。

            ## 書類の読み方

            - 2本の `---` 行に挟まれた任意のYAMLヘッダ：`titre` または `title`、`date`、`source` または `url`、`auteur`（著者）、`tags`。
            - スライドショー：スライドは `---` の行で区切られ、スライド内のHTMLコメント `<!-- … -->` は発表者ノートです。
            - ```` ```mermaid ```` ブロックは図、```` ```leaflet ```` ブロックは地図、`$…$` と `$$…$$` はLaTeXの数式です。
            - fornews.ai のレポートには「Entités」セクションがあり、名前が種類別に並び、多くはWikidataにリンクしています。
            - ファイル末尾の `<!-- md-viewer-annotations … -->` ブロックにはユーザーのハイライトとメモが入っています。決して変更せず、コピーもしないでください。
            - 画像が `data:`（base64）として埋め込まれていることがあります。無視してかまいません。

            ## 引用のしかた

            各書類は、保管庫のルートからのパスとタイトルで示してください。例：`coffre md viewer/2026/11/budget.md` —「2027年度予算」。書類にない事実、数値、日付は述べないでください。

            ## 書き込むとき

            - ユーザーの依頼なしに、ファイルを削除、移動、名前変更しないでください。
            - 新しい書類は、なるべく `coffre md viewer/YYYY/MM/` に、YAMLヘッダ（`titre`、`date`）付きで置いてください。
            - `.mdviewer/` フォルダは変更しないでください。md Viewerが書き直します。

            """,
                claude: "この保管庫への指示は AGENTS.md にあります：",
                indexTitre: "保管庫の索引",
                indexIntro: "%d件の書類（新しい順）。md Viewerが作成。編集しないでください。",
                indexColonnes: ["書類", "タイトル", "日付", "出典", "タグ"],
                entitesTitre: "保管庫のエンティティ",
                entitesIntro: "md Viewerの保管庫分析で見つかったもの（出現の多い順）。書類を含む詳細は `entites.json` にあります。",
                entitesColonnes: ["名前", "種類", "Wikidata", "書類", "初出", "最新", "よく一緒に"]),
            "ko": Textes(
                agents: """
            # 이 보관함에 대하여 (어시스턴트용)

            이 폴더는 **md Viewer**(ok-ia.ch)의 보관함으로, Markdown 문서가 들어 있습니다. 이 파일은 md Viewer가 작성하고 최신 상태로 유지합니다. 직접 지침을 적으려면 첫 줄을 지우세요. 그러면 md Viewer가 이 파일을 더 이상 건드리지 않습니다.

            ## 무엇이 어디에 있나

            - `.mdviewer/index.md`: 모든 문서를 한 줄에 하나씩, 제목·날짜·출처와 함께. 여기서 시작하세요. `index.json`은 프로그램용 버전입니다.
            - `.mdviewer/entites.md`(보관함 분석 후): 인물, 조직, 장소 등과 이들이 등장하는 문서. `entites.json`에 항목별 문서 목록이 있습니다.
            - `coffre md viewer/YYYY/MM/`: md Viewer로 가져온 문서(Word, PDF, PowerPoint, 웹 페이지 등)를 연도와 월별로 정리.
            - `rapports-…` 폴더: fornews.ai의 보고서. 나머지 폴더는 사용자의 것입니다.

            ## 문서 읽기

            - 두 개의 `---` 줄 사이에 있는 선택적 YAML 헤더: `titre` 또는 `title`, `date`, `source` 또는 `url`, `auteur`(저자), `tags`.
            - 슬라이드쇼: 슬라이드는 `---` 줄로 구분되며, 슬라이드의 HTML 주석 `<!-- … -->`은 발표자 노트입니다.
            - ```` ```mermaid ```` 블록은 다이어그램, ```` ```leaflet ```` 블록은 지도이고, `$…$`와 `$$…$$`는 LaTeX 수식입니다.
            - fornews.ai 보고서에는 "Entités" 섹션이 있습니다. 이름이 종류별로 정리되어 있고, 대개 Wikidata에 연결되어 있습니다.
            - 파일 끝의 `<!-- md-viewer-annotations … -->` 블록에는 사용자의 하이라이트와 메모가 담겨 있습니다. 절대 수정하거나 복사하지 마세요.
            - 이미지가 `data:`(base64)로 삽입되어 있기도 합니다. 무시해도 됩니다.

            ## 인용하기

            각 문서는 보관함 루트로부터의 경로와 제목으로 밝혀 주세요. 예: `coffre md viewer/2026/11/budget.md` — "2027년 예산". 문서에 없는 사실, 수치, 날짜는 말하지 마세요.

            ## 쓰기

            - 사용자가 요청하지 않는 한 파일을 삭제, 이동, 이름 변경하지 마세요.
            - 새 문서는 가급적 `coffre md viewer/YYYY/MM/`에 YAML 헤더(`titre`, `date`)와 함께 두세요.
            - `.mdviewer/` 폴더는 수정하지 마세요. md Viewer가 다시 작성합니다.

            """,
                claude: "이 보관함의 지침은 AGENTS.md에 있습니다:",
                indexTitre: "보관함 색인",
                indexIntro: "문서 %d개, 최신순. md Viewer가 작성함. 수정하지 마세요.",
                indexColonnes: ["문서", "제목", "날짜", "출처", "태그"],
                entitesTitre: "보관함의 엔티티",
                entitesIntro: "md Viewer의 보관함 분석으로 찾은 항목, 많이 나온 순. 문서를 포함한 자세한 내용은 `entites.json`에 있습니다.",
                entitesColonnes: ["이름", "종류", "Wikidata", "문서", "처음", "마지막", "자주 함께"]),
            "zh-Hans": Textes(
                agents: """
            # 本资料库说明（供助手阅读）

            此文件夹是 **md Viewer**（ok-ia.ch）的资料库，存放 Markdown 文档。本文件由 md Viewer 编写并保持更新。如需写入您自己的指示，请删除第一行：此后 md Viewer 将不再改动本文件。

            ## 内容位置

            - `.mdviewer/index.md`：所有文档，每行一份，附标题、日期和来源。请从这里开始；`index.json` 是供程序使用的版本。
            - `.mdviewer/entites.md`（资料库分析之后）：人物、组织、地点等，以及它们出现的文档；`entites.json` 列出每一项的文档。
            - `coffre md viewer/YYYY/MM/`：导入 md Viewer 的文档（Word、PDF、PowerPoint、网页等），按年和月存放。
            - `rapports-…` 文件夹：fornews.ai 的报告。其他文件夹属于用户。

            ## 阅读文档

            - 两行 `---` 之间可选的 YAML 头：`titre` 或 `title`、`date`、`source` 或 `url`、`auteur`（作者）、`tags`。
            - 幻灯片：幻灯片之间以一行 `---` 分隔；幻灯片中的 HTML 注释 `<!-- … -->` 是演讲者备注。
            - ```` ```mermaid ```` 代码块是示意图，```` ```leaflet ```` 代码块是地图；`$…$` 和 `$$…$$` 是 LaTeX 公式。
            - fornews.ai 的报告有“Entités”一节：按类型归类的名称，通常链接到 Wikidata。
            - 文件末尾的 `<!-- md-viewer-annotations … -->` 块保存用户的高亮和笔记：切勿修改，也不要复制。
            - 图像有时以 `data:`（base64）形式嵌入：可以忽略。

            ## 引用

            引用每份文档时，请给出从资料库根目录起的路径和标题，例如：`coffre md viewer/2026/11/budget.md` ——“2027 年预算”。不要陈述文档中没有的事实、数字或日期。

            ## 写入

            - 除非用户要求，不要删除、移动或重命名任何文件。
            - 新文档最好放在 `coffre md viewer/YYYY/MM/`，并带 YAML 头（`titre`、`date`）。
            - 不要修改 `.mdviewer/` 文件夹：md Viewer 会重写它。

            """,
                claude: "本资料库的指示见 AGENTS.md：",
                indexTitre: "资料库索引",
                indexIntro: "共 %d 份文档，按从新到旧排列。由 md Viewer 编写；请勿修改。",
                indexColonnes: ["文档", "标题", "日期", "来源", "标签"],
                entitesTitre: "资料库中的实体",
                entitesIntro: "由 md Viewer 的资料库分析找到，出现最多的在前。包含文档的详细信息见 `entites.json`。",
                entitesColonnes: ["名称", "类型", "Wikidata", "文档", "首次", "最近", "常与"]),
            "pt-BR": Textes(
                agents: """
            # Este cofre, para os assistentes

            Esta pasta é um cofre do **md Viewer** (ok-ia.ch): documentos Markdown. O md Viewer escreveu este arquivo e o mantém atualizado. Para colocar aqui suas próprias instruções, remova a primeira linha: o md Viewer não vai mais mexer nele.

            ## Onde encontrar o quê

            - `.mdviewer/index.md`: todos os documentos, um por linha, com título, data e fonte. Comece por ele; `index.json` é a versão para programas.
            - `.mdviewer/entites.md` (após a análise do cofre): pessoas, organizações, lugares… e os documentos em que aparecem; `entites.json` lista os documentos de cada um.
            - `coffre md viewer/AAAA/MM/`: os documentos importados no md Viewer (Word, PDF, PowerPoint, páginas web…), organizados por ano e mês.
            - As pastas `rapports-…`: relatórios do fornews.ai. As demais pastas são do usuário.

            ## Ler um documento

            - Um cabeçalho YAML opcional entre duas linhas `---`: `titre` ou `title`, `date`, `source` ou `url`, `auteur` (autor), `tags`.
            - Uma apresentação: os slides são separados por uma linha `---`; os comentários HTML `<!-- … -->` de um slide são as notas do apresentador.
            - Os blocos ```` ```mermaid ```` são diagramas, ```` ```leaflet ```` mapas; `$…$` e `$$…$$` são fórmulas LaTeX.
            - Os relatórios do fornews.ai têm uma seção "Entités": nomes classificados por tipo, muitas vezes ligados ao Wikidata.
            - Um bloco `<!-- md-viewer-annotations … -->` no fim de um arquivo guarda os destaques e as notas do usuário: nunca o modifique nem o copie.
            - Às vezes há imagens incorporadas como `data:` (base64): você pode ignorá-las.

            ## Citar

            Cite cada documento pelo caminho a partir da raiz do cofre e pelo título, por exemplo: `coffre md viewer/2026/11/budget.md` — "O orçamento de 2027". Não afirme nenhum fato, número ou data que não esteja em um documento.

            ## Escrever

            - Não exclua, mova nem renomeie nenhum arquivo sem que o usuário peça.
            - Um novo documento vai de preferência em `coffre md viewer/AAAA/MM/`, com um cabeçalho YAML (`titre`, `date`).
            - Não modifique a pasta `.mdviewer/`: o md Viewer a reescreve.

            """,
                claude: "As instruções para este cofre estão em AGENTS.md:",
                indexTitre: "Índice do cofre",
                indexIntro: "%d documentos, do mais recente ao mais antigo. Escrito pelo md Viewer; não modificar.",
                indexColonnes: ["Documento", "Título", "Data", "Fonte", "Etiquetas"],
                entitesTitre: "As entidades do cofre",
                entitesIntro: "Encontradas pela análise do cofre do md Viewer, as mais presentes primeiro. O detalhe, com os documentos, está em `entites.json`.",
                entitesColonnes: ["Nome", "Tipo", "Wikidata", "Documentos", "Primeira", "Última", "Muitas vezes com"]),
            "nl": Textes(
                agents: """
            # Deze kluis, voor assistenten

            Deze map is een kluis van **md Viewer** (ok-ia.ch): Markdown-documenten. md Viewer heeft dit bestand geschreven en houdt het bij. Wil je hier je eigen instructies zetten, verwijder dan de eerste regel: md Viewer raakt het dan niet meer aan.

            ## Wat staat waar

            - `.mdviewer/index.md`: alle documenten, één per regel, met titel, datum en bron. Begin daar; `index.json` is de versie voor programma's.
            - `.mdviewer/entites.md` (na de analyse van de kluis): personen, organisaties, plaatsen… en de documenten waarin ze voorkomen; `entites.json` geeft per item de documenten.
            - `coffre md viewer/JJJJ/MM/`: documenten die in md Viewer zijn geïmporteerd (Word, PDF, PowerPoint, webpagina's…), geordend per jaar en maand.
            - De mappen `rapports-…`: rapporten van fornews.ai. De andere mappen zijn van de gebruiker.

            ## Een document lezen

            - Een optionele YAML-kop tussen twee regels `---`: `titre` of `title`, `date`, `source` of `url`, `auteur` (auteur), `tags`.
            - Een diavoorstelling: de dia's worden gescheiden door een regel `---`; de HTML-opmerkingen `<!-- … -->` van een dia zijn de notities van de spreker.
            - Blokken ```` ```mermaid ```` zijn diagrammen, ```` ```leaflet ```` kaarten; `$…$` en `$$…$$` zijn LaTeX-formules.
            - Rapporten van fornews.ai hebben een sectie 'Entités': namen per soort, vaak gekoppeld aan Wikidata.
            - Een blok `<!-- md-viewer-annotations … -->` aan het eind van een bestand bewaart de markeringen en notities van de gebruiker: wijzig het nooit en kopieer het niet.
            - Afbeeldingen zijn soms ingesloten als `data:` (base64): je kunt ze negeren.

            ## Citeren

            Citeer elk document met zijn pad vanaf de hoofdmap van de kluis en zijn titel, bijvoorbeeld: `coffre md viewer/2026/11/budget.md` — 'De begroting 2027'. Noem geen feit, cijfer of datum dat niet in een document staat.

            ## Schrijven

            - Verwijder, verplaats of hernoem geen enkel bestand zonder dat de gebruiker erom vraagt.
            - Een nieuw document hoort bij voorkeur in `coffre md viewer/JJJJ/MM/`, met een YAML-kop (`titre`, `date`).
            - Wijzig de map `.mdviewer/` niet: md Viewer schrijft die opnieuw.

            """,
                claude: "De instructies voor deze kluis staan in AGENTS.md:",
                indexTitre: "Index van de kluis",
                indexIntro: "%d documenten, nieuwste eerst. Geschreven door md Viewer; niet bewerken.",
                indexColonnes: ["Document", "Titel", "Datum", "Bron", "Labels"],
                entitesTitre: "De entiteiten van de kluis",
                entitesIntro: "Gevonden door de analyse van de kluis in md Viewer, de meest voorkomende eerst. De details, met de documenten, staan in `entites.json`.",
                entitesColonnes: ["Naam", "Soort", "Wikidata", "Documenten", "Eerste", "Laatste", "Vaak met"]),
            "ru": Textes(
                agents: """
            # Это хранилище — для ассистентов

            Эта папка — хранилище **md Viewer** (ok-ia.ch): документы Markdown. md Viewer создал этот файл и поддерживает его в актуальном состоянии. Чтобы записать сюда свои инструкции, удалите первую строку: md Viewer больше не будет его трогать.

            ## Что где лежит

            - `.mdviewer/index.md`: все документы, по одному на строку, с названием, датой и источником. Начинайте с него; `index.json` — версия для программ.
            - `.mdviewer/entites.md` (после анализа хранилища): люди, организации, места… и документы, в которых они встречаются; `entites.json` перечисляет документы для каждого.
            - `coffre md viewer/ГГГГ/ММ/`: документы, импортированные в md Viewer (Word, PDF, PowerPoint, веб-страницы…), разложенные по годам и месяцам.
            - Папки `rapports-…`: отчёты fornews.ai. Остальные папки принадлежат пользователю.

            ## Как читать документ

            - Необязательный заголовок YAML между двумя строками `---`: `titre` или `title`, `date`, `source` или `url`, `auteur` (автор), `tags`.
            - Слайд-шоу: слайды разделены строкой `---`; HTML-комментарии `<!-- … -->` слайда — это заметки докладчика.
            - Блоки ```` ```mermaid ```` — диаграммы, ```` ```leaflet ```` — карты; `$…$` и `$$…$$` — формулы LaTeX.
            - В отчётах fornews.ai есть раздел «Entités»: имена, сгруппированные по типам, часто со ссылками на Wikidata.
            - Блок `<!-- md-viewer-annotations … -->` в конце файла хранит выделения и заметки пользователя: никогда не изменяйте и не копируйте его.
            - Изображения иногда встроены как `data:` (base64): их можно пропускать.

            ## Как цитировать

            Указывайте каждый документ по пути от корня хранилища и по названию, например: `coffre md viewer/2026/11/budget.md` — «Бюджет на 2027 год». Не приводите фактов, чисел или дат, которых нет в документах.

            ## Как писать

            - Не удаляйте, не перемещайте и не переименовывайте файлы без просьбы пользователя.
            - Новый документ лучше помещать в `coffre md viewer/ГГГГ/ММ/` с заголовком YAML (`titre`, `date`).
            - Не изменяйте папку `.mdviewer/`: md Viewer перезаписывает её.

            """,
                claude: "Инструкции для этого хранилища — в AGENTS.md:",
                indexTitre: "Указатель хранилища",
                indexIntro: "Документов: %d, сначала самые новые. Создано md Viewer; не изменять.",
                indexColonnes: ["Документ", "Название", "Дата", "Источник", "Теги"],
                entitesTitre: "Сущности хранилища",
                entitesIntro: "Найдены при анализе хранилища в md Viewer, самые частые — первыми. Подробности, с документами, — в `entites.json`.",
                entitesColonnes: ["Имя", "Тип", "Wikidata", "Документы", "Первое", "Последнее", "Часто вместе с"]),
            "uk": Textes(
                agents: """
            # Це сховище — для асистентів

            Ця папка — сховище **md Viewer** (ok-ia.ch): документи Markdown. md Viewer створив цей файл і підтримує його в актуальному стані. Щоб записати сюди власні інструкції, видаліть перший рядок: md Viewer більше не чіпатиме його.

            ## Що де лежить

            - `.mdviewer/index.md`: усі документи, по одному на рядок, з назвою, датою та джерелом. Починайте з нього; `index.json` — версія для програм.
            - `.mdviewer/entites.md` (після аналізу сховища): люди, організації, місця… і документи, у яких вони трапляються; `entites.json` перелічує документи для кожного.
            - `coffre md viewer/РРРР/ММ/`: документи, імпортовані в md Viewer (Word, PDF, PowerPoint, вебсторінки…), розкладені за роками й місяцями.
            - Папки `rapports-…`: звіти fornews.ai. Решта папок належить користувачеві.

            ## Як читати документ

            - Необов'язковий заголовок YAML між двома рядками `---`: `titre` або `title`, `date`, `source` або `url`, `auteur` (автор), `tags`.
            - Слайд-шоу: слайди розділені рядком `---`; HTML-коментарі `<!-- … -->` слайда — це нотатки доповідача.
            - Блоки ```` ```mermaid ```` — діаграми, ```` ```leaflet ```` — карти; `$…$` і `$$…$$` — формули LaTeX.
            - У звітах fornews.ai є розділ «Entités»: імена, згруповані за типами, часто з посиланнями на Wikidata.
            - Блок `<!-- md-viewer-annotations … -->` у кінці файлу зберігає виділення та нотатки користувача: ніколи не змінюйте й не копіюйте його.
            - Зображення іноді вбудовані як `data:` (base64): їх можна пропускати.

            ## Як цитувати

            Указуйте кожен документ за шляхом від кореня сховища та за назвою, наприклад: `coffre md viewer/2026/11/budget.md` — «Бюджет на 2027 рік». Не наводьте фактів, чисел чи дат, яких немає в документах.

            ## Як писати

            - Не видаляйте, не переміщуйте й не перейменовуйте файли без прохання користувача.
            - Новий документ краще розміщувати в `coffre md viewer/РРРР/ММ/` із заголовком YAML (`titre`, `date`).
            - Не змінюйте папку `.mdviewer/`: md Viewer перезаписує її.

            """,
                claude: "Інструкції для цього сховища — в AGENTS.md:",
                indexTitre: "Покажчик сховища",
                indexIntro: "Документів: %d, спершу найновіші. Створено md Viewer; не змінювати.",
                indexColonnes: ["Документ", "Назва", "Дата", "Джерело", "Теги"],
                entitesTitre: "Сутності сховища",
                entitesIntro: "Знайдені під час аналізу сховища в md Viewer, найчастіші — першими. Подробиці, з документами, — в `entites.json`.",
                entitesColonnes: ["Ім'я", "Тип", "Wikidata", "Документи", "Перше", "Останнє", "Часто разом із"]),
            "tr": Textes(
                agents: """
            # Bu kasa, asistanlar için

            Bu klasör bir **md Viewer** kasasıdır (ok-ia.ch): Markdown belgeleri. Bu dosyayı md Viewer yazdı ve güncel tutuyor. Buraya kendi talimatlarınızı yazmak için ilk satırı silin: md Viewer dosyaya bir daha dokunmaz.

            ## Ne nerede

            - `.mdviewer/index.md`: tüm belgeler, her satırda bir tane, başlığı, tarihi ve kaynağıyla. Buradan başlayın; `index.json` programlar için olan sürümüdür.
            - `.mdviewer/entites.md` (kasa analizinden sonra): kişiler, kuruluşlar, yerler… ve geçtikleri belgeler; `entites.json` her birinin belgelerini listeler.
            - `coffre md viewer/YYYY/AA/`: md Viewer'a içe aktarılan belgeler (Word, PDF, PowerPoint, web sayfaları…), yıla ve aya göre düzenlenmiş.
            - `rapports-…` klasörleri: fornews.ai raporları. Diğer klasörler kullanıcıya aittir.

            ## Bir belgeyi okumak

            - İki `---` satırı arasında isteğe bağlı bir YAML başlığı: `titre` veya `title`, `date`, `source` veya `url`, `auteur` (yazar), `tags`.
            - Bir slayt gösterisi: slaytlar bir `---` satırıyla ayrılır; bir slayttaki `<!-- … -->` HTML yorumları konuşmacı notlarıdır.
            - ```` ```mermaid ```` blokları diyagramdır, ```` ```leaflet ```` blokları haritadır; `$…$` ve `$$…$$` LaTeX formülleridir.
            - fornews.ai raporlarında bir "Entités" bölümü vardır: türe göre gruplanmış adlar, çoğu zaman Wikidata'ya bağlı.
            - Bir dosyanın sonundaki `<!-- md-viewer-annotations … -->` bloğu, kullanıcının vurgularını ve notlarını saklar: onu asla değiştirmeyin ve kopyalamayın.
            - Görseller bazen `data:` (base64) olarak gömülüdür: bunları yok sayabilirsiniz.

            ## Kaynak göstermek

            Her belgeyi kasanın kökünden itibaren yolu ve başlığıyla belirtin, örneğin: `coffre md viewer/2026/11/budget.md` — "2027 Bütçesi". Bir belgede bulunmayan hiçbir olgu, sayı veya tarih öne sürmeyin.

            ## Yazmak

            - Kullanıcı istemedikçe hiçbir dosyayı silmeyin, taşımayın veya yeniden adlandırmayın.
            - Yeni bir belge tercihen `coffre md viewer/YYYY/AA/` içine, bir YAML başlığıyla (`titre`, `date`) konur.
            - `.mdviewer/` klasörünü değiştirmeyin: md Viewer onu yeniden yazar.

            """,
                claude: "Bu kasa için talimatlar AGENTS.md dosyasında:",
                indexTitre: "Kasa dizini",
                indexIntro: "%d belge, en yeniden en eskiye. md Viewer tarafından yazıldı; değiştirmeyin.",
                indexColonnes: ["Belge", "Başlık", "Tarih", "Kaynak", "Etiketler"],
                entitesTitre: "Kasadaki varlıklar",
                entitesIntro: "md Viewer'ın kasa analiziyle bulundu, en sık geçenler önce. Belgelerle birlikte ayrıntılar `entites.json` içinde.",
                entitesColonnes: ["Ad", "Tür", "Wikidata", "Belgeler", "İlk", "Son", "Sık birlikte"]),
            "vi": Textes(
                agents: """
            # Kho này, dành cho trợ lý

            Thư mục này là một kho của **md Viewer** (ok-ia.ch): các tài liệu Markdown. md Viewer đã viết tệp này và luôn cập nhật nó. Để ghi chỉ dẫn riêng của bạn vào đây, hãy xóa dòng đầu tiên: md Viewer sẽ không động đến tệp nữa.

            ## Tìm gì ở đâu

            - `.mdviewer/index.md`: mọi tài liệu, mỗi dòng một tài liệu, kèm tiêu đề, ngày và nguồn. Hãy bắt đầu từ đây; `index.json` là phiên bản dành cho chương trình.
            - `.mdviewer/entites.md` (sau khi phân tích kho): người, tổ chức, địa điểm… và các tài liệu nhắc đến họ; `entites.json` liệt kê tài liệu của từng mục.
            - `coffre md viewer/YYYY/MM/`: các tài liệu đã nhập vào md Viewer (Word, PDF, PowerPoint, trang web…), xếp theo năm và tháng.
            - Các thư mục `rapports-…`: báo cáo của fornews.ai. Các thư mục khác là của người dùng.

            ## Đọc một tài liệu

            - Một phần đầu YAML tùy chọn nằm giữa hai dòng `---`: `titre` hoặc `title`, `date`, `source` hoặc `url`, `auteur` (tác giả), `tags`.
            - Một bài trình chiếu: các slide được ngăn bằng một dòng `---`; các chú thích HTML `<!-- … -->` của một slide là ghi chú của người thuyết trình.
            - Các khối ```` ```mermaid ```` là sơ đồ, ```` ```leaflet ```` là bản đồ; `$…$` và `$$…$$` là công thức LaTeX.
            - Báo cáo của fornews.ai có một mục "Entités": các tên được xếp theo loại, thường liên kết với Wikidata.
            - Khối `<!-- md-viewer-annotations … -->` ở cuối tệp lưu phần tô sáng và ghi chú của người dùng: tuyệt đối không sửa và không sao chép nó.
            - Đôi khi hình ảnh được nhúng dưới dạng `data:` (base64): bạn có thể bỏ qua.

            ## Trích dẫn

            Trích dẫn mỗi tài liệu bằng đường dẫn từ gốc kho và tiêu đề của nó, ví dụ: `coffre md viewer/2026/11/budget.md` — "Ngân sách 2027". Không đưa ra sự kiện, con số hay ngày tháng nào không có trong tài liệu.

            ## Viết

            - Không xóa, di chuyển hay đổi tên tệp nào nếu người dùng không yêu cầu.
            - Tài liệu mới nên đặt trong `coffre md viewer/YYYY/MM/`, kèm phần đầu YAML (`titre`, `date`).
            - Không sửa thư mục `.mdviewer/`: md Viewer sẽ ghi lại nó.

            """,
                claude: "Chỉ dẫn cho kho này nằm trong AGENTS.md:",
                indexTitre: "Chỉ mục của kho",
                indexIntro: "%d tài liệu, mới nhất trước. Do md Viewer viết; không chỉnh sửa.",
                indexColonnes: ["Tài liệu", "Tiêu đề", "Ngày", "Nguồn", "Nhãn"],
                entitesTitre: "Các thực thể trong kho",
                entitesIntro: "Được tìm thấy qua phân tích kho của md Viewer, xuất hiện nhiều nhất trước. Chi tiết, kèm tài liệu, nằm trong `entites.json`.",
                entitesColonnes: ["Tên", "Loại", "Wikidata", "Tài liệu", "Đầu tiên", "Gần nhất", "Thường đi cùng"]),
            "hi": Textes(
                agents: """
            # यह वॉल्ट, सहायकों के लिए

            यह फ़ोल्डर **md Viewer** (ok-ia.ch) का वॉल्ट है: Markdown दस्तावेज़। यह फ़ाइल md Viewer ने लिखी है और इसे अपडेट रखता है। यहाँ अपने निर्देश लिखने के लिए पहली पंक्ति हटा दें: फिर md Viewer इसे नहीं छुएगा।

            ## क्या कहाँ है

            - `.mdviewer/index.md`: सभी दस्तावेज़, हर पंक्ति में एक, शीर्षक, तारीख़ और स्रोत के साथ। यहीं से शुरू करें; `index.json` प्रोग्रामों के लिए उसका संस्करण है।
            - `.mdviewer/entites.md` (वॉल्ट के विश्लेषण के बाद): व्यक्ति, संगठन, स्थान… और वे दस्तावेज़ जिनमें वे आते हैं; `entites.json` हर एक के दस्तावेज़ों की सूची देता है।
            - `coffre md viewer/YYYY/MM/`: md Viewer में इम्पोर्ट किए गए दस्तावेज़ (Word, PDF, PowerPoint, वेब पेज…), साल और महीने के अनुसार रखे हुए।
            - `rapports-…` फ़ोल्डर: fornews.ai की रिपोर्टें। बाक़ी फ़ोल्डर उपयोगकर्ता के हैं।

            ## दस्तावेज़ पढ़ना

            - दो `---` पंक्तियों के बीच एक वैकल्पिक YAML हेडर: `titre` या `title`, `date`, `source` या `url`, `auteur` (लेखक), `tags`।
            - स्लाइडशो: स्लाइडें एक `---` पंक्ति से अलग होती हैं; किसी स्लाइड की HTML टिप्पणियाँ `<!-- … -->` प्रस्तुतकर्ता नोट्स हैं।
            - ```` ```mermaid ```` ब्लॉक डायग्राम हैं, ```` ```leaflet ```` ब्लॉक मैप हैं; `$…$` और `$$…$$` LaTeX फ़ॉर्मूले हैं।
            - fornews.ai की रिपोर्टों में एक "Entités" सेक्शन होता है: प्रकार के अनुसार समूहित नाम, अक्सर Wikidata से जुड़े।
            - किसी फ़ाइल के अंत में `<!-- md-viewer-annotations … -->` ब्लॉक उपयोगकर्ता की हाइलाइट और नोट्स रखता है: इसे कभी न बदलें और न कॉपी करें।
            - इमेज कभी-कभी `data:` (base64) के रूप में जुड़ी होती हैं: आप उन्हें अनदेखा कर सकते हैं।

            ## हवाला देना

            हर दस्तावेज़ का हवाला वॉल्ट की जड़ से उसके पाथ और उसके शीर्षक से दें, उदाहरण: `coffre md viewer/2026/11/budget.md` — "बजट 2027"। कोई ऐसा तथ्य, आँकड़ा या तारीख़ न बताएँ जो किसी दस्तावेज़ में न हो।

            ## लिखना

            - उपयोगकर्ता के कहे बिना कोई फ़ाइल न मिटाएँ, न हटाएँ, न उसका नाम बदलें।
            - नया दस्तावेज़ बेहतर है कि `coffre md viewer/YYYY/MM/` में, YAML हेडर (`titre`, `date`) के साथ रखें।
            - `.mdviewer/` फ़ोल्डर न बदलें: md Viewer उसे फिर से लिखता है।

            """,
                claude: "इस वॉल्ट के निर्देश AGENTS.md में हैं:",
                indexTitre: "वॉल्ट इंडेक्स",
                indexIntro: "%d दस्तावेज़, सबसे नए पहले। md Viewer द्वारा लिखा गया; संपादित न करें।",
                indexColonnes: ["दस्तावेज़", "शीर्षक", "तारीख़", "स्रोत", "टैग"],
                entitesTitre: "वॉल्ट की एंटिटी",
                entitesIntro: "md Viewer के वॉल्ट विश्लेषण से मिलीं, सबसे ज़्यादा आने वाली पहले। दस्तावेज़ों सहित विवरण `entites.json` में है।",
                entitesColonnes: ["नाम", "प्रकार", "Wikidata", "दस्तावेज़", "पहली", "आख़िरी", "अक्सर साथ"]),
        ]
    }
}
