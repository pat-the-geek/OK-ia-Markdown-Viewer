// ─────────────────────────────────────────────────────────────────────────────────────────────
// Copie de fornews.ai — FornewsCore/Sources/FornewsPipeline/ConsignesLocales.swift (commit b2d8c521, 26/10/2026).
// Option Analytic (1.4) : le même algorithme que fornews. ⛔ Ne pas modifier ici : corriger dans
// fornews, puis relancer scripts/copier-fornews.sh.
// Seule retouche : les `import Fornews…` retirés.
// ─────────────────────────────────────────────────────────────────────────────────────────────

import Foundation

/// **Les consignes écrites DANS la langue du rapport** (Patrick, 04/10/2026, « fais 1 2 3 4 », point 2).
///
/// 📏 Essais en cinq langues : avec une consigne en français et un ordre de langue en fin, le modèle suivait les extraits
/// français ; le code traduisait ensuite section par section — un rapport anglais prenait deux fois le temps d'un rapport
/// français (Ukraine : 103 s → 233 s). Écrite dans la langue cible, la consigne fait écrire juste du premier coup ; la
/// traduction par le code reste en repli.
///
/// ⚠️ Seules les sections que le modèle RÉDIGE encore sont traduites : la vérification et la critique rendent des listes
/// lues par le code, en français, et ne produisent aucun texte publié. Le français garde `ConsignesAnalyste`.
/// ⚠️ Mêmes règles, mêmes interdits, même ordre que la version française ; même plafond (`plafondCaracteres`).
enum ConsignesLocales {

    struct Textes: Sendable {
        let socle: String, tics: String
        let resume: String, chapeau: String, titre: String, perspectives: @Sendable (String) -> String, resonances: String, retouche: String
        let phases: @Sendable (String) -> String, fils: @Sendable (String) -> String, titresPoints: @Sendable (String) -> String
    }

    static func consigne(_ s: ConsignesAnalyste.Section, code: String, sujet: String?) -> String? {
        guard let t = textes(code) else { return nil }
        let n = sujet ?? "?"
        switch s {
        case .resumeExecutif: return t.socle + "\n" + t.tics + "\n" + t.resume
        case .chapeau: return t.socle + "\n" + t.tics + "\n" + t.chapeau
        case .titre: return t.titre + "\n" + t.tics
        case .perspectives: return t.socle + "\n" + t.tics + "\n" + t.perspectives(sujet ?? "")
        case .resonances: return t.socle + "\n" + t.tics + "\n" + t.resonances
        case .retouche: return t.socle + "\n" + t.tics + "\n" + t.retouche
        case .phases: return t.phases(n)
        case .fils: return t.fils(n)
        case .titresPoints: return t.titresPoints(n)
        default: return nil
        }
    }

    static func textes(_ code: String) -> Textes? {
        switch code {
        case "en": anglais
        case "de": allemand
        case "es": espagnol
        case "it": italien
        default: nil
        }
    }

    static let anglais = Textes(
        socle: """
        You write, in English, one section of a press ANALYSIS REPORT from the excerpts.
        ⛔ No section heading, no list of sources, no link, no image, no diagram: they are added after you.
        ⛔ Every proper name, figure and date must appear in the excerpts: invent or infer none.
        ⛔ Prose, no bullet points.
        ⛔ An excerpt marked [allégation] stays attributed to its source ("according to…"), never stated as fact.
        """,
        tics: "⛔ Plain style, no tics: no \"it is important to note\", no \"in conclusion\", no \"testament to\", no \"crucial\", no rhetorical question, no triad of adjectives.",
        resume: "Write THREE short paragraphs separated by a blank line. 1) What is happening: the phases of the timeline (first), in order, named or dated, rephrased. 2) Why it matters. 3) What comes next. \"Then\", \"next\", \"while\": only if the dates confirm it. Do not duplicate any actor.",
        chapeau: "Write ONE short paragraph: ONE sentence per excerpt, in their order, giving the essence of what it reports. What is only claimed stays attributed (\"according to…\"). No date or figure that is not in the excerpt.",
        titre: """
        Propose ONE report title, in English, of 5 to 12 words, stating what the text reveals: a thesis, not a mere topic.
        Return the title alone, on one line, without quotes, without a colon, without a final full stop.
        ⛔ Every proper name must appear in the text. No date.
        """,
        perspectives: { sujet in
            "First line: a title of at most 8 words, in the future or conditional. Then ONE paragraph on \(sujet.isEmpty ? "the likely next steps" : sujet): what it opens up, without starting with \"The decision\". ⛔ Write NO date that is not in the excerpts. Without a fact that commits the future, say the corpus does not allow a conclusion."
        },
        resonances: "Write ONE paragraph on the critical or sceptical voices in the excerpts: who doubts, warns or objects, and about what. Attribute each position to its author (\"according to…\", \"X believes that…\"). If the excerpts contain no critical voice, answer only: RIEN.",
        retouche: "This paragraph has lost sentences. Make it flow: link the remaining sentences and fix transitions that became wrong. ⛔ Add NO fact, name, figure or date; change the meaning of no sentence; keep each one recognisable. Return the paragraph alone.",
        phases: { n in
            """
            The facts provided are grouped into \(n) phases, in chronological order. Give each phase a name of 2 to 5 words, in English, saying what is at stake, in a neutral, factual tone: no "secret", no "plot", no "shock", no headline effect.
            Answer with \(n) lines and NOTHING else, one per phase, in the form: 1. Name
            ⛔ No proper name or date that is not in the facts.
            """
        },
        fils: { n in
            """
            The article titles provided are grouped into \(n) groups. Give each group a heading of 2 to 6 words, in English, saying what it is about, in a neutral, factual tone.
            Answer with \(n) lines and NOTHING else, one per group, in the form: 1. Heading
            ⛔ No proper name that is not in the titles.
            """
        },
        titresPoints: { n in
            """
            The article titles provided are grouped into \(n) groups. For each group, write in English a headline of 4 to 9 words that says WHAT IS HAPPENING, as a sentence with a verb in the present tense, naming who or what is concerned.
            If the titles report what someone CLAIMS, attribute it ("X says…"). Neutral tone, no headline effect.
            Answer with \(n) lines and NOTHING else, one per group, in the form: 1. Headline
            ⛔ No proper name that is not in the titles. No date.
            """
        })

    static let allemand = Textes(
        socle: """
        Du schreibst auf Deutsch einen Abschnitt eines PRESSE-ANALYSEBERICHTS aus den Auszügen.
        ⛔ Keine Überschrift, Quellenliste, Links, Bilder oder Diagramme: sie kommen danach.
        ⛔ Jeder Eigenname, jede Zahl, jedes Datum muss in den Auszügen stehen: nichts erfinden, nichts erschließen.
        ⛔ Fließtext, keine Aufzählungspunkte.
        ⛔ Ein Auszug mit [allégation] bleibt seiner Quelle zugeschrieben („laut…“), nie als Tatsache.
        """,
        tics: "⛔ Nüchtern, ohne Floskeln: kein „es ist wichtig zu beachten“, „zusammenfassend“, „zeugt von“, „entscheidend“, keine rhetorischen Fragen, keine Dreierreihen von Adjektiven.",
        resume: "Schreibe DREI kurze Absätze, getrennt durch eine Leerzeile. 1) Was geschieht: die Phasen des Ablaufs, der Reihe nach, benannt oder datiert, umformuliert. 2) Warum es wichtig ist. 3) Was folgt. „Danach“, „dann“, „während“ nur, wenn die Daten es belegen. Kein Akteur doppelt. Ganze Sätze, Verb an zweiter Stelle.",
        chapeau: "Schreibe EINEN kurzen Absatz: EINEN Satz pro Auszug, in ihrer Reihenfolge, mit dem Wesentlichen, das er berichtet. Bloße Behauptungen bleiben zugeschrieben („laut…“). Kein Datum, keine Zahl, die nicht im Auszug steht.",
        titre: """
        Schlage EINEN Berichtstitel auf Deutsch vor, 5 bis 12 Wörter, der sagt, was der Text zeigt: eine These, nicht nur ein Thema.
        Gib nur den Titel zurück, in einer Zeile, ohne Anführungszeichen, ohne Doppelpunkt, ohne Schlusspunkt.
        ⛔ Jeder Eigenname muss im Text stehen. Kein Datum.
        """,
        perspectives: { sujet in
            "Erste Zeile: ein Titel von höchstens 8 Wörtern, im Futur oder Konjunktiv. Dann EIN Absatz über \(sujet.isEmpty ? "die wahrscheinliche Fortsetzung" : sujet): was sich daraus ergibt, ohne mit „Die Entscheidung“ zu beginnen. ⛔ Schreibe KEIN Datum, das nicht in den Auszügen steht. Ohne Tatsache, die die Zukunft bindet, sage, dass der Korpus keine Aussage erlaubt."
        },
        resonances: "Schreibe EINEN Absatz über die kritischen oder skeptischen Stimmen der Auszüge: wer zweifelt, warnt oder widerspricht, und worüber. Schreibe jede Position ihrem Urheber zu („laut…“, „X meint, dass…“). Ohne kritische Stimme in den Auszügen antworte nur: RIEN.",
        retouche: "Diesem Absatz fehlen Sätze. Mach ihn flüssig: verbinde die verbleibenden Sätze und korrigiere falsch gewordene Übergänge. ⛔ Füge KEINE Tatsache, keinen Namen, keine Zahl und kein Datum hinzu; ändere den Sinn keines Satzes; jeder bleibt erkennbar. Gib nur den Absatz zurück.",
        phases: { n in
            """
            Die Fakten sind in \(n) Phasen gruppiert, zeitlich geordnet. Gib jeder Phase einen Namen von 2 bis 5 Wörtern auf Deutsch, der sagt, worum es geht, sachlich und neutral: kein „Geheimnis“, keine „Verschwörung“, kein „Schock“, keine Schlagzeile.
            Antworte mit \(n) Zeilen und NICHTS anderem, eine pro Phase, in der Form: 1. Name
            ⛔ Kein Eigenname und kein Datum, das nicht in den Fakten steht.
            """
        },
        fils: { n in
            """
            Die Artikeltitel sind in \(n) Gruppen eingeteilt. Gib jeder Gruppe eine Überschrift von 2 bis 6 Wörtern auf Deutsch, die sagt, worum es geht, sachlich und neutral.
            Antworte mit \(n) Zeilen und NICHTS anderem, eine pro Gruppe, in der Form: 1. Überschrift
            ⛔ Kein Eigenname, der nicht in den Titeln steht.
            """
        },
        titresPoints: { n in
            """
            Die Artikeltitel sind in \(n) Gruppen eingeteilt. Schreibe für jede Gruppe auf Deutsch eine Schlagzeile von 4 bis 9 Wörtern, die sagt, WAS GESCHIEHT: ein Satz mit einem Verb im Präsens, der nennt, wer oder was betroffen ist.
            Berichten die Titel, was jemand BEHAUPTET, schreibe es ihm zu („X sagt…“). Sachlicher Ton.
            Antworte mit \(n) Zeilen und NICHTS anderem, eine pro Gruppe, in der Form: 1. Schlagzeile
            ⛔ Kein Eigenname, der nicht in den Titeln steht. Kein Datum.
            """
        })

    static let espagnol = Textes(
        socle: """
        Redactas, en español, una sección de un INFORME DE ANÁLISIS de prensa a partir de los extractos.
        ⛔ Ni título de sección, ni lista de fuentes, ni enlace, ni imagen, ni diagrama: se añaden después.
        ⛔ Todo nombre propio, cifra y fecha debe figurar en los extractos: no inventes ni deduzcas ninguno.
        ⛔ Prosa, sin viñetas.
        ⛔ Un extracto marcado [allégation] queda atribuido a su fuente («según…»), nunca afirmado como hecho.
        """,
        tics: "⛔ Estilo sobrio, sin muletillas: ni «es importante señalar», ni «en conclusión», ni «da testimonio de», ni «crucial», ni pregunta retórica, ni tríada de adjetivos.",
        resume: "Escribe TRES párrafos breves separados por una línea en blanco. 1) Lo que ocurre: las fases de la cronología (primero), en orden, nombradas o fechadas, reformuladas. 2) Por qué importa. 3) Lo que viene. «Después», «luego», «mientras»: solo si las fechas lo confirman. No dupliques ningún actor.",
        chapeau: "Escribe UN párrafo breve: UNA frase por extracto, en su orden, con lo esencial de lo que cuenta. Lo que solo se afirma queda atribuido («según…»). Ninguna fecha ni cifra que no esté en el extracto.",
        titre: """
        Propón UN título de informe, en español, de 5 a 12 palabras, que diga lo que el texto revela: una tesis, no un simple tema.
        Devuelve solo el título, en una línea, sin comillas, sin dos puntos, sin punto final.
        ⛔ Todo nombre propio debe figurar en el texto. Ninguna fecha.
        """,
        perspectives: { sujet in
            "Primera línea: un título de 8 palabras como máximo, en futuro o condicional. Luego UN párrafo sobre \(sujet.isEmpty ? "lo que probablemente vendrá" : sujet): lo que abre, sin empezar por «La decisión». ⛔ No escribas NINGUNA fecha que no figure en los extractos. Sin un hecho que comprometa el futuro, di que el corpus no permite pronunciarse."
        },
        resonances: "Escribe UN párrafo sobre las voces críticas o escépticas de los extractos: quién duda, alerta o se opone, y sobre qué. Atribuye cada posición a su autor («según…», «X considera que…»). Sin voz crítica en los extractos, responde solo: RIEN.",
        retouche: "Este párrafo ha perdido frases. Hazlo fluido: enlaza las frases restantes y corrige las transiciones que se han vuelto falsas. ⛔ No añadas NINGÚN hecho, nombre, cifra ni fecha; no cambies el sentido de ninguna frase; que cada una siga reconocible. Devuelve solo el párrafo.",
        phases: { n in
            """
            Los hechos están agrupados en \(n) fases, en orden cronológico. Da a cada fase un nombre de 2 a 5 palabras, en español, que diga lo que está en juego, con tono neutro y factual: ni «secreto», ni «complot», ni «choque», ningún efecto de titular.
            Responde con \(n) líneas y NADA más, una por fase, con la forma: 1. Nombre
            ⛔ Ningún nombre propio ni fecha que no figure en los hechos.
            """
        },
        fils: { n in
            """
            Los títulos de artículos están agrupados en \(n) grupos. Da a cada grupo un encabezado de 2 a 6 palabras, en español, que diga de qué trata, con tono neutro y factual.
            Responde con \(n) líneas y NADA más, una por grupo, con la forma: 1. Encabezado
            ⛔ Ningún nombre propio que no figure en los títulos.
            """
        },
        titresPoints: { n in
            """
            Los títulos de artículos están agrupados en \(n) grupos. Para cada grupo, escribe en español un titular de 4 a 9 palabras que diga QUÉ OCURRE: una frase con un verbo en presente que nombre a quién o qué concierne.
            Si los títulos cuentan lo que alguien AFIRMA, atribúyelo («X afirma…»). Tono neutro.
            Responde con \(n) líneas y NADA más, una por grupo, con la forma: 1. Titular
            ⛔ Ningún nombre propio que no figure en los títulos. Ninguna fecha.
            """
        })

    static let italien = Textes(
        socle: """
        Scrivi, in italiano, una sezione di un RAPPORTO DI ANALISI della stampa a partire dagli estratti.
        ⛔ Niente titolo di sezione, elenco di fonti, link, immagine o diagramma: vengono aggiunti dopo.
        ⛔ Ogni nome proprio, cifra e data deve comparire negli estratti: non inventarne né dedurne nessuno.
        ⛔ Prosa, senza elenchi puntati.
        ⛔ Un estratto marcato [allégation] resta attribuito alla sua fonte («secondo…»), mai affermato come fatto.
        """,
        tics: "⛔ Stile sobrio, senza tic: niente «è importante notare», «in conclusione», «testimonia», «cruciale», domande retoriche o triadi di aggettivi.",
        resume: "Scrivi TRE brevi paragrafi separati da una riga vuota. 1) Che cosa succede: le fasi della cronologia (prima), in ordine, nominate o datate, riformulate. 2) Perché conta. 3) Che cosa viene dopo. «Poi», «in seguito», «mentre»: solo se le date lo confermano. Non duplicare nessun attore.",
        chapeau: "Scrivi UN breve paragrafo: UNA frase per estratto, nel loro ordine, con l'essenziale di ciò che riporta. Ciò che è solo affermato resta attribuito («secondo…»). Nessuna data o cifra che non sia nell'estratto.",
        titre: """
        Proponi UN titolo di rapporto, in italiano, di 5-12 parole, che dica ciò che il testo rivela: una tesi, non un semplice tema.
        Restituisci solo il titolo, su una riga, senza virgolette, senza due punti, senza punto finale.
        ⛔ Ogni nome proprio deve comparire nel testo. Nessuna data.
        """,
        perspectives: { sujet in
            "Prima riga: un titolo di al massimo 8 parole, al futuro o al condizionale. Poi UN paragrafo su \(sujet.isEmpty ? "il probabile seguito" : sujet): che cosa apre, senza cominciare con «La decisione». ⛔ NON scrivere alcuna data che non sia negli estratti. Senza un fatto che impegni il futuro, di' che il corpus non permette di pronunciarsi."
        },
        resonances: "Scrivi UN paragrafo sulle voci critiche o scettiche degli estratti: chi dubita, avverte o si oppone, e su che cosa. Attribuisci ogni posizione al suo autore («secondo…», «X ritiene che…»). Senza voci critiche negli estratti, rispondi solo: RIEN.",
        retouche: "Questo paragrafo ha perso delle frasi. Rendilo scorrevole: collega le frasi rimaste e correggi le transizioni diventate sbagliate. ⛔ NON aggiungere fatti, nomi, cifre o date; non cambiare il senso di nessuna frase; ognuna resti riconoscibile. Restituisci solo il paragrafo.",
        phases: { n in
            """
            I fatti sono raggruppati in \(n) fasi, in ordine cronologico. Dai a ogni fase un nome di 2-5 parole, in italiano, che dica che cosa è in gioco, con tono neutro e fattuale: niente «segreto», «complotto», «shock», nessun effetto da titolo.
            Rispondi con \(n) righe e NIENT'ALTRO, una per fase, nella forma: 1. Nome
            ⛔ Nessun nome proprio né data che non compaia nei fatti.
            """
        },
        fils: { n in
            """
            I titoli degli articoli sono raggruppati in \(n) gruppi. Dai a ogni gruppo un'intestazione di 2-6 parole, in italiano, che dica di che cosa parla, con tono neutro e fattuale.
            Rispondi con \(n) righe e NIENT'ALTRO, una per gruppo, nella forma: 1. Intestazione
            ⛔ Nessun nome proprio che non compaia nei titoli.
            """
        },
        titresPoints: { n in
            """
            I titoli degli articoli sono raggruppati in \(n) gruppi. Per ogni gruppo, scrivi in italiano un titolo di 4-9 parole che dica CHE COSA SUCCEDE: una frase con un verbo al presente che nomini chi o che cosa riguarda.
            Se i titoli riportano ciò che qualcuno AFFERMA, attribuiscilo («X afferma…»). Tono neutro.
            Rispondi con \(n) righe e NIENT'ALTRO, una per gruppo, nella forma: 1. Titolo
            ⛔ Nessun nome proprio che non compaia nei titoli. Nessuna data.
            """
        })
}
