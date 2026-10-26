// ─────────────────────────────────────────────────────────────────────────────────────────────
// Copie de fornews.ai — FornewsCore/Sources/FornewsFeatures/Explorer/FicheArticle.swift (commit b2d8c521, 26/10/2026).
// Option Analytic (1.4) : le même algorithme que fornews. ⛔ Ne pas modifier ici : corriger dans
// fornews, puis relancer scripts/copier-fornews.sh.
// Seule retouche : les `import Fornews…` retirés.
// ─────────────────────────────────────────────────────────────────────────────────────────────

import Foundation

/// **La fiche de lecture d'un article** — le nouveau look du « Rapport Markdown » d'« Envoyer vers… »
/// (Patrick, 04/10/2026 : « nouveaux looks validés (éditorial percutant, briefing semaine à semaine, fiche
/// d'article) — à coder » ; maquette `docs/maquettes/fiche-article.html`).
///
/// Dans l'ordre : la grande image (le média, son logo, le temps de lecture), l'en-tête « Fiche de lecture ·
/// média · date », le titre (et le titre original s'il est traduit), « En bref », « En chiffres », « Qui est
/// cité », « Le schéma », le texte avec sa lettrine et sa citation en exergue, la carte des lieux, puis
/// « L'article d'origine ». La signature et l'avertissement IA ferment le document (`AvertissementIA`).
///
/// ⛔ **Aucun fait ajouté.** Le résumé et le schéma viennent du modèle et passent par leurs contrôles
/// (`VerificateurAncrage`, `validerDiagrammeIA`, `schemaAncre`). Les chiffres et la citation sont relevés et
/// CONTRÔLÉS par le code contre le texte : un chiffre absent du texte n'est jamais écrit, une citation
/// introuvable mot pour mot n'est pas mise en exergue.
///
/// ⚠️ Markdown pour md Viewer ET pour une page web autonome (exigence de Patrick, 04/10/2026 : « les
/// documents doivent pouvoir être consultés par des personnes qui n'ont pas fornews ») : titres `##`, blocs
/// en HTML à STYLES EN LIGNE, un élément par ligne, couleurs en `rgba()` lisibles en clair comme en sombre,
/// aucune syntaxe propre à md Viewer ou à Obsidian. ⛔ Jamais de ligne `---` dans le corps : md Viewer
/// passerait en diaporama.
enum FicheArticle {

    // MARK: - Les couleurs

    /// Le rouge de la fiche (maquette validée) : surtitre, lettrine, bouton, premier chiffre comparé.
    static let accent = "225,29,72"
    static let ardoise = "100,116,139"

    /// Les quatre familles de « Qui est cité », aux couleurs des `mark.ner-tag` du rapport de veille.
    enum Famille: CaseIterable {
        case personnes, organisations, lieux, autres
        var rgb: String {
            switch self {
            case .personnes: return "217,119,6"
            case .organisations: return "37,99,235"
            case .lieux: return "5,150,105"
            case .autres: return "100,116,139"
            }
        }
        /// Les dates et les montants ne sont pas des noms cités.
        static func de(_ t: TypeEntite) -> Famille? {
            switch t {
            case .person: return .personnes
            case .org: return .organisations
            case .gpe, .loc: return .lieux
            case .date, .money: return nil
            case .product, .event, .work, .maladie, .autre: return .autres
            }
        }
    }

    // MARK: - Les libellés, dans les cinq langues

    enum GenreSchema { case liens, chronologie, echanges, themes, repartition, noms }

    struct Textes {
        let surtitre, enBref, enChiffres, quiEstCite, schema, texteIntegral, pointsCles, articleOrigine: String
        let personnes, organisations, lieux, autres: String
        let lireOriginal, titreOriginal, foi, resumeAuto, chapeau, chapeauTraduit, surligne: String
        let figure, schemaNote, chiffresNote, publicationCitee: String
        let lecture: (Int) -> String
        let image: (String) -> String
        let publie: (String) -> String
        let lireSur: (String) -> String
        let legende: (GenreSchema) -> String

        func famille(_ f: Famille) -> String {
            switch f {
            case .personnes: return personnes
            case .organisations: return organisations
            case .lieux: return lieux
            case .autres: return autres
            }
        }
    }

    static func textes(_ langue: String) -> Textes {
        switch String(langue.prefix(2)).lowercased() {
        case "en": return Textes(
            surtitre: "Reading notes", enBref: "In brief", enChiffres: "By the numbers", quiEstCite: "Who is mentioned",
            schema: "The diagram", texteIntegral: "The full text", pointsCles: "Key points", articleOrigine: "The original article",
            personnes: "People", organisations: "Organizations", lieux: "Places", autres: "Others",
            lireOriginal: "Read the original ↗", titreOriginal: "Original title", foi: "Machine translation; the original article prevails.",
            resumeAuto: "Summary drawn up automatically from the text of the article.", chapeau: "The article's standfirst.",
            chapeauTraduit: "The article's standfirst, translated.", surligne: "In the text, each name is highlighted in the colour of its group.",
            figure: "Figure", schemaNote: "Diagram drawn up automatically from the text of the article.",
            chiffresNote: "Each figure is quoted exactly as it appears in the text.", publicationCitee: "Cited publication",
            lecture: { "\($0) min read" }, image: { "Image: \($0)" }, publie: { "Published on \($0)" },
            lireSur: { "Read the article on \($0) →" },
            legende: {
                switch $0 {
                case .liens: return "How the key elements of the article are linked."
                case .chronologie: return "The article's events over time."
                case .echanges: return "The exchanges between the article's actors."
                case .themes: return "The themes of the article."
                case .repartition: return "The figures given by the article."
                case .noms: return "The names mentioned in the article, by group."
                }
            })
        case "de": return Textes(
            surtitre: "Artikelsteckbrief", enBref: "Kurz gefasst", enChiffres: "In Zahlen", quiEstCite: "Wer genannt wird",
            schema: "Das Schema", texteIntegral: "Der vollständige Text", pointsCles: "Kernpunkte", articleOrigine: "Der Originalartikel",
            personnes: "Personen", organisations: "Organisationen", lieux: "Orte", autres: "Weitere",
            lireOriginal: "Original lesen ↗", titreOriginal: "Originaltitel", foi: "Maschinelle Übersetzung; maßgeblich ist der Originalartikel.",
            resumeAuto: "Automatisch aus dem Text des Artikels erstellte Zusammenfassung.", chapeau: "Der Vorspann des Artikels.",
            chapeauTraduit: "Der Vorspann des Artikels, übersetzt.", surligne: "Im Text ist jeder Name in der Farbe seiner Gruppe hervorgehoben.",
            figure: "Abbildung", schemaNote: "Automatisch aus dem Text des Artikels erstelltes Schema.",
            chiffresNote: "Jede Zahl steht genau so im Text.", publicationCitee: "Zitierte Publikation",
            lecture: { "\($0) Min. Lesezeit" }, image: { "Bild: \($0)" }, publie: { "Veröffentlicht am \($0)" },
            lireSur: { "Artikel auf \($0) lesen →" },
            legende: {
                switch $0 {
                case .liens: return "Wie die Kernelemente des Artikels zusammenhängen."
                case .chronologie: return "Die Ereignisse des Artikels im zeitlichen Ablauf."
                case .echanges: return "Der Austausch zwischen den Akteuren des Artikels."
                case .themes: return "Die Themen des Artikels."
                case .repartition: return "Die Zahlen des Artikels."
                case .noms: return "Die im Artikel genannten Namen, nach Gruppe."
                }
            })
        case "es": return Textes(
            surtitre: "Ficha de lectura", enBref: "En resumen", enChiffres: "En cifras", quiEstCite: "Quién aparece",
            schema: "El esquema", texteIntegral: "El texto íntegro", pointsCles: "Puntos clave", articleOrigine: "El artículo original",
            personnes: "Personas", organisations: "Organizaciones", lieux: "Lugares", autres: "Otros",
            lireOriginal: "Leer el original ↗", titreOriginal: "Título original", foi: "Traducción automática; prevalece el artículo original.",
            resumeAuto: "Resumen elaborado automáticamente a partir del texto del artículo.", chapeau: "La entradilla del artículo.",
            chapeauTraduit: "La entradilla del artículo, traducida.", surligne: "En el texto, cada nombre aparece resaltado con el color de su grupo.",
            figure: "Figura", schemaNote: "Esquema elaborado automáticamente a partir del texto del artículo.",
            chiffresNote: "Cada cifra se reproduce tal como aparece en el texto.", publicationCitee: "Publicación citada",
            lecture: { "\($0) min de lectura" }, image: { "Imagen: \($0)" }, publie: { "Publicado el \($0)" },
            lireSur: { "Leer el artículo en \($0) →" },
            legende: {
                switch $0 {
                case .liens: return "Cómo se relacionan los elementos clave del artículo."
                case .chronologie: return "Los hechos del artículo a lo largo del tiempo."
                case .echanges: return "Los intercambios entre los actores del artículo."
                case .themes: return "Los temas del artículo."
                case .repartition: return "Las cifras que da el artículo."
                case .noms: return "Los nombres citados en el artículo, por grupo."
                }
            })
        case "it": return Textes(
            surtitre: "Scheda di lettura", enBref: "In breve", enChiffres: "In cifre", quiEstCite: "Chi è citato",
            schema: "Lo schema", texteIntegral: "Il testo integrale", pointsCles: "Punti chiave", articleOrigine: "L'articolo originale",
            personnes: "Persone", organisations: "Organizzazioni", lieux: "Luoghi", autres: "Altri",
            lireOriginal: "Leggi l'originale ↗", titreOriginal: "Titolo originale", foi: "Traduzione automatica; fa fede l'articolo originale.",
            resumeAuto: "Riassunto redatto automaticamente dal testo dell'articolo.", chapeau: "L'occhiello dell'articolo.",
            chapeauTraduit: "L'occhiello dell'articolo, tradotto.", surligne: "Nel testo, ogni nome è evidenziato con il colore del suo gruppo.",
            figure: "Figura", schemaNote: "Schema redatto automaticamente dal testo dell'articolo.",
            chiffresNote: "Ogni cifra è riportata esattamente come nel testo.", publicationCitee: "Pubblicazione citata",
            lecture: { "\($0) min di lettura" }, image: { "Immagine: \($0)" }, publie: { "Pubblicato il \($0)" },
            lireSur: { "Leggi l'articolo su \($0) →" },
            legende: {
                switch $0 {
                case .liens: return "Come si collegano gli elementi chiave dell'articolo."
                case .chronologie: return "I fatti dell'articolo nel tempo."
                case .echanges: return "Gli scambi tra gli attori dell'articolo."
                case .themes: return "I temi dell'articolo."
                case .repartition: return "Le cifre fornite dall'articolo."
                case .noms: return "I nomi citati nell'articolo, per gruppo."
                }
            })
        default: return Textes(
            surtitre: "Fiche de lecture", enBref: "En bref", enChiffres: "En chiffres", quiEstCite: "Qui est cité",
            schema: "Le schéma", texteIntegral: "Le texte intégral", pointsCles: "Points clés", articleOrigine: "L'article d'origine",
            personnes: "Personnes", organisations: "Organisations", lieux: "Lieux", autres: "Autres",
            lireOriginal: "Lire l'original ↗", titreOriginal: "Titre original", foi: "Traduction automatique ; l'article original fait foi.",
            resumeAuto: "Résumé établi automatiquement d'après le texte de l'article.", chapeau: "Le chapeau de l'article.",
            chapeauTraduit: "Le chapeau de l'article, traduit.", surligne: "Dans le texte, chaque nom est surligné de la couleur de sa famille.",
            figure: "Figure", schemaNote: "Schéma établi automatiquement d'après le texte de l'article.",
            chiffresNote: "Chaque chiffre est repris tel quel du texte.", publicationCitee: "Publication citée",
            lecture: { "\($0) min de lecture" }, image: { "Image : \($0)" }, publie: { "Publié le \($0)" },
            lireSur: { "Lire l'article sur \($0) →" },
            legende: {
                switch $0 {
                case .liens: return "Les liens entre les éléments clés de l'article."
                case .chronologie: return "Les faits de l'article dans le temps."
                case .echanges: return "Les échanges entre les acteurs de l'article."
                case .themes: return "Les thèmes de l'article."
                case .repartition: return "Les chiffres donnés par l'article."
                case .noms: return "Les noms cités dans l'article, par famille."
                }
            })
        }
    }

    /// Le nom d'une langue dans la langue du document : « anglais », « English », « Englisch »…
    static func nomLangue(_ code: String, dans langue: String) -> String {
        let doc = String(langue.prefix(2)).lowercased()
        let brut = Locale(identifier: doc).localizedString(forLanguageCode: String(code.prefix(2)).lowercased()) ?? code
        // Les noms de langue prennent une minuscule en français, en espagnol et en italien.
        return ["fr", "es", "it"].contains(doc) ? brut.lowercased() : brut.prefix(1).uppercased() + brut.dropFirst()
    }

    /// « Traduit de l'anglais », « Translated from English », « Aus dem Englischen übersetzt »…
    static func traduitDe(_ code: String, langue: String) -> String {
        let nom = nomLangue(code, dans: langue)
        let voyelle = nom.first.map { "aeiouyhàâéèêîïôœ".contains($0.lowercased()) } ?? false
        switch String(langue.prefix(2)).lowercased() {
        case "en": return "Translated from \(nom)"
        case "de": return "Aus dem \(nom)en übersetzt"
        case "es": return "Traducido del \(nom)"
        case "it":
            let lo = nom.hasPrefix("s") && nom.dropFirst().first.map { !"aeiou".contains($0) } == true || nom.hasPrefix("z")
            return voyelle ? "Tradotto dall'\(nom)" : (lo ? "Tradotto dallo \(nom)" : "Tradotto dal \(nom)")
        default: return voyelle ? "Traduit de l'\(nom)" : "Traduit du \(nom)"
        }
    }

    /// « en anglais », « in English », « auf Englisch »…
    static func enLangue(_ code: String, langue: String) -> String {
        let nom = nomLangue(code, dans: langue)
        switch String(langue.prefix(2)).lowercased() {
        case "en", "it": return "in \(nom)"
        case "de": return "auf \(nom)"
        default: return "en \(nom)"
        }
    }

    // MARK: - Le texte de l'article

    struct Texte: Equatable {
        /// Le chapeau stocké (la section « En bref » du résumé rangé avec l'article), s'il y en a un.
        let chapeau: String?
        /// Le texte lu : le texte intégral rechargé, sinon le reste du résumé rangé.
        let corps: String
        /// Vrai si `corps` est bien le texte entier, pas seulement ses points clés.
        let integral: Bool
    }

    /// Les titres de la section d'ouverture du résumé rangé, dans les cinq langues (`ResumeurExtractif`).
    static let titresEnBref: Set<String> = ["en bref", "in brief", "kurz gefasst", "en resumen", "in breve"]

    static func plier(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).trimmingCharacters(in: .whitespaces)
    }

    /// Sépare le résumé rangé « ## En bref / chapeau / ## Points clés / texte » en chapeau et reste.
    static func decouper(_ md: String) -> (chapeau: String?, reste: String) {
        let lignes = md.components(separatedBy: "\n")
        guard let i0 = lignes.firstIndex(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) else { return (nil, "") }
        let premiere = lignes[i0].trimmingCharacters(in: .whitespaces)
        guard premiere.hasPrefix("## "), titresEnBref.contains(plier(String(premiere.dropFirst(3)))) else {
            return (nil, md.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        let i1 = lignes[(i0 + 1)...].firstIndex { $0.trimmingCharacters(in: .whitespaces).hasPrefix("## ") }
        let chapeau = lignes[(i0 + 1)..<(i1 ?? lignes.count)].joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let reste = i1.map { lignes[($0 + 1)...].joined(separator: "\n") } ?? ""
        return (chapeau.isEmpty ? nil : chapeau, reste.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Le texte que la fiche montre — le même pour la composition et pour le relevé des chiffres.
    static func texte(_ d: RapportObsidian.DonneesRapport, corpsComplet: String?) -> Texte {
        let (brut, reste) = decouper(d.resumeMd)
        // ⛔ Le chapeau des résumés rangés RECOPIE souvent le titre (« ## En bref » puis le titre, 06/10/2026, fiche Apple
        // One) : l'encadré « En bref » ne faisait que le répéter. Sans lui, il ne reste parfois rien — pas d'encadré.
        let chapeau = brut.map { RapportObsidian.retirerTitreEnTete($0, titre: d.titre).trimmingCharacters(in: .whitespacesAndNewlines) }
            .flatMap { $0.isEmpty ? nil : $0 }
        if let c = corpsComplet?.trimmingCharacters(in: .whitespacesAndNewlines), !c.isEmpty {
            return Texte(chapeau: chapeau, corps: nettoyerCorps(RapportObsidian.retirerTitreEnTete(c, titre: d.titre)),
                         integral: true)
        }
        let corps = nettoyerCorps(RapportObsidian.retirerTitreEnTete(reste, titre: d.titre))
        // Le résumé rangé porte souvent le texte entier, traduit ; parfois seulement ses points clés.
        let integral = d.longueurContenuOriginal > 0 && Double(corps.count) >= 0.7 * Double(d.longueurContenuOriginal)
        return Texte(chapeau: chapeau, corps: corps, integral: integral)
    }

    /// ⛔ Pas de `---` (md Viewer passerait en diaporama), et les titres du texte descendent d'un rang : la table
    /// des matières reste celle de la fiche.
    static func nettoyerCorps(_ s: String) -> String {
        var lignes: [String] = []
        for l in s.components(separatedBy: "\n") {
            let t = l.trimmingCharacters(in: .whitespaces)
            // ⛔ La ligne de signature de la page (« Mon 05 Oct 2026, 13:49 EDT · 1 minute read », AppleInsider, 06/10/2026)
            // ouvrait le texte intégral, lettrine comprise. Seulement en TÊTE : plus bas, une telle ligne est du texte.
            if lignes.allSatisfy({ $0.trimmingCharacters(in: .whitespaces).isEmpty }),
               RevuePresse.estLigneDeSignature(t) || RevuePresse.estSignatureDAuteur(t) { continue }
            if t.range(of: "^(?:([-*_])(?:\\s*\\1){2,}|={3,})$", options: .regularExpression) != nil { continue }
            if t.range(of: "^#{1,2}\\s", options: .regularExpression) != nil {
                lignes.append("### " + t.replacingOccurrences(of: "^#{1,2}\\s+", with: "", options: .regularExpression))
                continue
            }
            lignes.append(l)
        }
        return lignes.joined(separator: "\n")
            .replacingOccurrences(of: "\n[ \t]*\n(?:[ \t]*\n)+", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func paragraphes(_ corps: String) -> [String] {
        corps.components(separatedBy: "\n\n").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    /// Le texte en simple prose (ni dièses, ni gras, ni liens Markdown) : pour un bloc HTML.
    static func prose(_ s: String) -> String {
        s.replacingOccurrences(of: "!\\[[^\\]]*\\]\\([^)]*\\)", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\[([^\\]]*)\\]\\([^)]*\\)", with: "$1", options: .regularExpression)
            .replacingOccurrences(of: "(?m)^\\s*#{1,6}\\s*", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\*\\*|__|`", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Le temps de lecture, à 230 mots par minute.
    static func minutesDeLecture(_ texte: String) -> Int {
        let mots = texte.split(whereSeparator: \.isWhitespace).count
        return max(1, Int((Double(mots) / 230).rounded(.up)))
    }

    // MARK: - Les phrases

    static let finDePhrase = try! NSRegularExpression(pattern: "(?<=[.!?…])\\s+(?=[«\"“„\\p{Lu}\\d])")

    static func phrases(_ texte: String) -> [String] {
        var out: [String] = []
        for p in paragraphes(texte) {
            let ns = p as NSString
            var debut = 0
            for m in finDePhrase.matches(in: p, range: NSRange(location: 0, length: ns.length)) {
                out.append(ns.substring(with: NSRange(location: debut, length: m.range.location - debut)))
                debut = m.range.location + m.range.length
            }
            out.append(ns.substring(from: debut))
        }
        return out.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    // MARK: - Les chiffres clés, relevés et contrôlés contre le texte

    struct Chiffre: Equatable, Sendable {
        /// Tel qu'il est écrit dans le texte (« 65 % », « 34 000 », « 128 millions »).
        let valeur: String
        let libelle: String
        /// La valeur, si c'est un pourcentage (pour les barres comparées).
        let pourcent: Double?
        /// La phrase du texte qui le porte.
        let phrase: String
    }

    /// Des chiffres qui vont ensemble : comparés en barres (des pourcentages), ou côte à côte.
    struct Lot: Equatable, Sendable {
        let titre: String?
        let chiffres: [Chiffre]
        var barres: Bool { chiffres.count >= 2 && chiffres.allSatisfy { ($0.pourcent ?? 1_000) <= 100 } }
    }

    enum Genre: Equatable { case pourcent, montant, grand, autre }

    /// Un nombre relevé dans une phrase du texte.
    struct Releve: Equatable {
        let valeur: String
        let nombre: String
        let genre: Genre
        let phrase: String
        let indexPhrase: Int
        let plage: NSRange
        let numerique: Double?
        var estAnnee: Bool {
            nombre.count == 4 && nombre.allSatisfy(\.isNumber) && (1800...2100).contains(Int(nombre) ?? 0)
        }
    }

    static let motifNombre = "\\d{1,3}(?:[ \u{00A0}\u{202F}'’.,]\\d{3})+(?:[.,]\\d+)?|\\d+(?:[.,]\\d+)?"
    static let motifPourcent = "%|pour\\s?cent|percent|per\\s?cent|prozent|por\\s?ciento|per\\s?cento"
    static let motifEchelle = "milliards?|millions?|billions?|trillions?|milliarden|millionen|mil millones|millones|miliardi|milioni|mrd\\.?|mio\\.?|bn"
    static let motifDevise = "dollars?|euros?|francs?|pounds?|yens?|yuans?|dólares|dollari|€|\\$|£|chf"

    static let chiffre = try! NSRegularExpression(pattern:
        "(?<![\\p{L}\\d.,])(?:(us\\$|\\$|€|£|chf)\\s?)?(\(motifNombre))"
        + "(?:\\s?(\(motifPourcent))(?![\\p{L}\\d])"
        + "|\\s(\(motifEchelle))(?:\\s?(?:de\\s|d['’]\\s?|of\\s)?(\(motifDevise)))?(?![\\p{L}\\d])"
        + "|\\s?(?:de\\s|d['’]\\s?)?(\(motifDevise))(?![\\p{L}\\d])"
        + "|(?![\\p{L}\\d]))",
        options: [.caseInsensitive])

    /// Ce qu'on ne relève jamais : une adresse, un DOI, un lien ou une image Markdown.
    static let horsChiffres = try! NSRegularExpression(pattern:
        "https?://\\S+|\\b10\\.\\d{4,9}/\\S+|!?\\[[^\\]]*\\]\\([^)]*\\)", options: [.caseInsensitive])

    static func relever(_ texte: String) -> [Releve] {
        var out: [Releve] = []
        for (i, p) in phrases(texte).enumerated() {
            let ns = p as NSString
            let tout = NSRange(location: 0, length: ns.length)
            let interdits = horsChiffres.matches(in: p, range: tout).map(\.range)
            for m in chiffre.matches(in: p, range: tout)
            where !interdits.contains(where: { NSIntersectionRange($0, m.range).length > 0 }) {
                func g(_ k: Int) -> String? { m.range(at: k).location == NSNotFound ? nil : ns.substring(with: m.range(at: k)) }
                let nombre = g(2) ?? ""
                let n = valeurNumerique(nombre)
                let genre: Genre
                if g(3) != nil { genre = (n ?? 0) <= 1_000 ? .pourcent : .autre }
                else if g(1) != nil || g(5) != nil || g(6) != nil { genre = .montant }
                else if g(4) != nil { genre = .grand }
                else if let n, n >= 1_000, !(nombre.count == 4 && nombre.allSatisfy(\.isNumber)) { genre = .grand }
                else { genre = .autre }
                out.append(Releve(valeur: ns.substring(with: m.range).trimmingCharacters(in: .whitespaces),
                                  nombre: nombre, genre: genre, phrase: p, indexPhrase: i, plage: m.range, numerique: n))
            }
        }
        return out
    }

    /// « 34 000 » → 34000 ; « 5,5 » → 5.5 ; « 1.234,5 » → 1234.5 ; « 34,000 » → 34000.
    static func valeurNumerique(_ brut: String) -> Double? {
        let s = brut.replacingOccurrences(of: "[ \u{00A0}\u{202F}'’]", with: "", options: .regularExpression)
        let seps = s.filter { $0 == "," || $0 == "." }
        guard let dernier = s.lastIndex(where: { $0 == "," || $0 == "." }) else { return Double(s) }
        let apres = s[s.index(after: dernier)...]
        let decimale = Set(seps).count == 2 || (seps.count == 1 && apres.count != 3)
        if decimale {
            let entier = s[..<dernier].filter(\.isNumber)
            return Double("\(entier).\(apres)")
        }
        return Double(s.filter(\.isNumber))
    }

    /// Les mots qui ne portent pas de sens au bord d'un libellé.
    static let motsVides: Set<String> = [
        "de", "du", "des", "la", "le", "les", "l", "d", "en", "et", "a", "au", "aux", "que", "qui", "dont", "pour", "par",
        "sur", "avec", "un", "une", "pres", "environ", "plus", "moins", "soit", "contre",
        "of", "the", "an", "and", "in", "on", "at", "to", "for", "by", "with", "than", "about", "nearly", "some", "more", "less",
        "der", "die", "das", "den", "dem", "und", "im", "von", "mit", "fur", "auf", "zu", "als", "rund", "etwa",
        "del", "el", "los", "las", "y", "por", "para", "con", "unos", "casi",
        "di", "della", "dei", "delle", "il", "lo", "i", "gli", "e", "che", "per", "circa", "quasi",
    ]

    static func motVide(_ mot: String) -> Bool {
        let m = plier(mot).trimmingCharacters(in: CharacterSet.letters.inverted)
        return m.isEmpty || motsVides.contains(m) || mot.hasSuffix("'") || mot.hasSuffix("’")
    }

    /// Le libellé d'un chiffre, LITTÉRAL : les mots qui le suivent dans sa phrase (« 34 000 morceaux de débris
    /// plus grands que 10 centimètres »), jusqu'à la ponctuation. `nil` s'il ne reste rien de parlant.
    static func libelleApres(_ r: Releve) -> String? {
        let ns = r.phrase as NSString
        let reste = ns.substring(from: r.plage.location + r.plage.length)
        let coupe = reste.prefix { !",;:.!?()«»\"“”„[]—–".contains($0) }
        var mots = Array(coupe.split(whereSeparator: \.isWhitespace).map(String.init).prefix(9))
        while let m = mots.last, motVide(m) { mots.removeLast() }
        while let m = mots.first, motVide(m) { mots.removeFirst() }
        guard mots.count >= 2, mots.contains(where: { $0.filter(\.isLetter).count >= 4 }) else { return nil }
        return prose(mots.joined(separator: " "))
    }

    /// La phrase qui porte le chiffre, raccourcie autour de lui si elle est longue.
    static func extrait(_ r: Releve, max: Int = 180) -> String {
        let p = prose(r.phrase)
        guard p.count > max else { return p }
        let ns = p as NSString
        let ici = ns.range(of: r.valeur)
        guard ici.location != NSNotFound else { return String(p.prefix(max)) + "…" }
        let debut = Swift.max(0, ici.location - (max - ici.length - 50))
        let fin = Swift.min(ns.length, Swift.max(ici.location + ici.length + 50, debut + max))
        var t = ns.substring(with: NSRange(location: debut, length: fin - debut))
        if debut > 0, let espace = t.firstIndex(of: " ") { t = "…" + t[t.index(after: espace)...] }
        if fin < ns.length, let espace = t.lastIndex(of: " ") { t = t[..<espace] + "…" }
        return t
    }

    /// **Les chiffres clés relevés par le code seul** — le repli quand le modèle n'est pas là, et ce que les tests
    /// éprouvent. Les pourcentages, les montants, les ordres de grandeur ; jamais une année.
    static func chiffresDuTexte(_ texte: String, max: Int = 6) -> [Lot] {
        var vus = Set<String>()
        let candidats = relever(texte).filter { r in
            [.pourcent, .montant, .grand].contains(r.genre) && !r.estAnnee
                && vus.insert(AncrageLitteral.normaliser(r.valeur)).inserted
        }
        let rang: (Releve) -> Int = { $0.genre == .grand && !$0.valeur.contains(where: \.isLetter) ? 1 : 0 }
        let retenus = candidats.enumerated().sorted { (rang($0.element), $0.offset) < (rang($1.element), $1.offset) }
            .prefix(max).sorted { $0.offset < $1.offset }.map(\.element)
        func chiffre(_ r: Releve) -> Chiffre {
            Chiffre(valeur: r.valeur, libelle: (r.genre == .pourcent ? nil : libelleApres(r)) ?? extrait(r),
                    pourcent: r.genre == .pourcent ? r.numerique : nil, phrase: r.phrase)
        }
        // Les pourcentages qui se suivent de près (trois phrases au plus) se comparent ; les autres chiffres d'une
        // même phrase vont ensemble.
        var lots: [(ordre: Int, lot: Lot)] = []
        let pourcents = retenus.filter { $0.genre == .pourcent }
        var reste = retenus
        if (2...4).contains(pourcents.count),
           let a = pourcents.first?.indexPhrase, let b = pourcents.last?.indexPhrase, b - a <= 2 {
            lots.append((a, Lot(titre: nil, chiffres: pourcents.map(chiffre))))
            reste = retenus.filter { $0.genre != .pourcent }
        }
        for (phrase, rs) in Dictionary(grouping: reste, by: \.indexPhrase) {
            if rs.count >= 2 {
                lots.append((phrase, Lot(titre: nil, chiffres: rs.sorted { $0.plage.location < $1.plage.location }.map(chiffre))))
            } else {
                lots.append((phrase, Lot(titre: nil, chiffres: rs.map(chiffre))))
            }
        }
        return lots.sorted { $0.ordre < $1.ordre }.map(\.lot)
    }

    /// Les mots pleins d'un texte, pliés et réduits à leurs cinq premières lettres (« projectiles » et
    /// « projectile » se reconnaissent).
    static func racines(_ s: String) -> [String] {
        plier(s).components(separatedBy: CharacterSet.letters.inverted)
            .filter { $0.count >= 4 && !motsVides.contains($0) }
            .map { String($0.prefix(5)) }
    }

    /// Vrai si `libelle` est fait des mots de `contexte` (au moins `part` de ses mots pleins), et si chaque nombre
    /// qu'il porte figure dans le texte.
    static func libelleAncre(_ libelle: String, contexte: String, texte: String, part: Double = 0.6) -> Bool {
        let mots = racines(libelle)
        guard !mots.isEmpty else { return false }
        let ici = Set(racines(contexte))
        let trouves = mots.filter { ici.contains($0) }.count
        guard Double(trouves) / Double(mots.count) >= part else { return false }
        let ns = libelle as NSString
        let nombres = (try? NSRegularExpression(pattern: motifNombre))?
            .matches(in: libelle, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range) } ?? []
        return nombres.allSatisfy { AncrageLitteral.figureDans($0, texte: texte) }
    }

    /// **Les chiffres proposés par le modèle, contrôlés un à un contre le texte.** La réponse attendue : une ligne
    /// « valeur | libellé | groupe » par chiffre. Un chiffre n'est retenu que si :
    /// - son nombre figure dans le texte, mot pour mot (`AncrageLitteral`) — et c'est la forme ÉCRITE dans le
    ///   texte qui est montrée, jamais celle du modèle ;
    /// - son libellé est fait des mots de la phrase qui porte le nombre (et de ses voisines) ;
    /// - ce n'est pas une année.
    /// `nil` s'il reste moins de deux chiffres : la fiche se rabat alors sur le relevé du code seul.
    static func chiffresDepuisModele(_ reponse: String, texte: String, max: Int = 6) -> [Lot]? {
        let releves = relever(texte)
        let toutes = phrases(texte)
        var pris = Set<Int>()
        var retenus: [(r: Releve, c: Chiffre, groupe: String)] = []
        let nombre = try! NSRegularExpression(pattern: motifNombre)
        for brut in reponse.split(whereSeparator: \.isNewline) {
            let champs = brut.split(separator: "|", omittingEmptySubsequences: false).map {
                $0.trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: "-*•\"«»“”")))
            }
            guard champs.count >= 2, retenus.count < max else { continue }
            let valeurIA = champs[0], libelle = prose(champs[1]), groupe = champs.count > 2 ? prose(champs[2]) : ""
            let nsv = valeurIA as NSString
            guard let m = nombre.firstMatch(in: valeurIA, range: NSRange(location: 0, length: nsv.length)),
                  !libelle.isEmpty, libelle.count <= 90 else { continue }
            let n = AncrageLitteral.normaliser(nsv.substring(with: m.range))
            let veutPourcent = valeurIA.range(of: motifPourcent, options: [.regularExpression, .caseInsensitive]) != nil
            guard let trouve = releves.enumerated().first(where: {
                !pris.contains($0.offset) && AncrageLitteral.normaliser($0.element.nombre) == n
                    && (!veutPourcent || $0.element.genre == .pourcent)
            }), !trouve.element.estAnnee else { continue }
            let k = trouve.offset, r = trouve.element
            let contexte = toutes[Swift.max(0, r.indexPhrase - 1)...Swift.min(toutes.count - 1, r.indexPhrase + 1)]
                .joined(separator: " ")
            guard libelleAncre(libelle, contexte: contexte, texte: texte) else { continue }
            pris.insert(k)
            retenus.append((r, Chiffre(valeur: r.valeur, libelle: libelle,
                                       pourcent: r.genre == .pourcent ? r.numerique : nil, phrase: r.phrase), groupe))
        }
        guard retenus.count >= 2 else { return nil }
        // Les groupes : un intitulé commun à au moins deux chiffres. L'intitulé n'est écrit que s'il est fait des
        // mots de leurs phrases ; sinon les chiffres restent ensemble, sans titre.
        var lots: [(ordre: Int, lot: Lot)] = []
        var dejaGroupes = Set<String>()
        for (i, e) in retenus.enumerated() {
            let cle = plier(e.groupe)
            if !cle.isEmpty, dejaGroupes.contains(cle) { continue }
            let membres = cle.isEmpty ? [e] : retenus.filter { plier($0.groupe) == cle }
            if !cle.isEmpty { dejaGroupes.insert(cle) }
            if membres.count >= 2 {
                let contexte = membres.map(\.r.phrase).joined(separator: " ")
                let titre = libelleAncre(e.groupe, contexte: contexte, texte: texte, part: 0.5) ? e.groupe : nil
                lots.append((i, Lot(titre: titre, chiffres: membres.map(\.c))))
            } else {
                lots.append((i, Lot(titre: nil, chiffres: [e.c])))
            }
        }
        return lots.sorted { $0.ordre < $1.ordre }.map(\.lot)
    }

    /// La consigne donnée au modèle pour relever les chiffres clés (la réponse passe par `chiffresDepuisModele`).
    static func inviteChiffres(texte: String, langue: String, nomLangue: String) -> String {
        """
        Relève les chiffres clés de ce texte, au plus 6. Une ligne par chiffre, au format exact :
        valeur | libellé | groupe
        - valeur : le nombre recopié EXACTEMENT comme dans le texte, avec son unité s'il en a une.
        - libellé : ce que compte ou mesure ce chiffre, en 3 à 8 mots repris du texte, en \(nomLangue).
        - groupe : un intitulé court commun à plusieurs chiffres qui mesurent la même chose et se comparent ; \
        sinon laisse vide. Dans un groupe, le libellé dit ce qui DISTINGUE chaque chiffre (l'objet, le cas), \
        pas la mesure commune.
        Pas d'années, pas de dates, pas de numéros. Aucun chiffre absent du texte. Rien d'autre que ces lignes.

        Texte :
        \(texte)
        """
    }

    // MARK: - Le résumé et le schéma : les contrôles

    /// **Un résumé du modèle n'entre dans la fiche que s'il est fidèle** : chaque nom propre doit exister dans le
    /// texte résumé (`VerificateurAncrage`, la garde du pipeline de résumés) et, quand résumé et texte sont dans la
    /// même langue, chaque nombre doit s'y retrouver mot pour mot (`AncrageLitteral`). Sinon : le chapeau.
    static func resumeFidele(_ resume: String, source: String, memeLangue: Bool, langue: String) -> Bool {
        let r = resume.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !r.isEmpty else { return false }
        let strict = memeLangue && !langue.hasPrefix("de")
        guard VerificateurAncrage.verdict(resume: r, source: source, modeStrict: strict).ancre else { return false }
        guard memeLangue else { return true }
        let ns = r as NSString
        let nombres = (try? NSRegularExpression(pattern: motifNombre))?
            .matches(in: r, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range) } ?? []
        return nombres.allSatisfy { AncrageLitteral.figureDans($0, texte: source) }
    }

    /// **Les nombres d'un schéma doivent figurer dans le texte** (une part de camembert, un pourcentage dans un
    /// libellé) : le schéma vient du modèle, et « personne ne relit un nombre ». `nil` si l'un d'eux manque.
    static func schemaAncre(_ diagramme: String, texte: String) -> String? {
        let corps = diagramme.split(separator: "\n").dropFirst()
            .filter { !$0.trimmingCharacters(in: .whitespaces).lowercased().hasPrefix("classdef") }
            .joined(separator: "\n")
            // Les identifiants synthétiques (N1, N2…) ne sont pas des nombres du texte.
            .replacingOccurrences(of: "\\bN\\d+\\b", with: " ", options: .regularExpression)
        let ns = corps as NSString
        let nombres = (try? NSRegularExpression(pattern: motifNombre))?
            .matches(in: corps, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range) } ?? []
        return nombres.allSatisfy { AncrageLitteral.figureDans($0, texte: texte) } ? diagramme : nil
    }

    static func genreSchema(_ diagramme: String, deterministe: Bool) -> GenreSchema {
        if deterministe { return .noms }
        let tete = diagramme.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if tete.hasPrefix("timeline") { return .chronologie }
        if tete.hasPrefix("sequencediagram") { return .echanges }
        if tete.hasPrefix("mindmap") { return .themes }
        if tete.hasPrefix("pie") || tete.hasPrefix("xychart") { return .repartition }
        return .liens
    }

    // MARK: - La citation en exergue

    struct Exergue: Equatable { let citation: String; let auteur: String }

    /// **Une citation EXACTE et son locuteur** : une phrase entre guillemets, recopiée telle quelle du texte, avec
    /// une personne citée de l'article juste après (« », a déclaré Yuxin Wang ») ou juste avant. Sans locuteur
    /// retrouvé, pas d'exergue : une phrase sans voix n'est qu'un extrait.
    static func exergue(_ texte: String, personnes: [String], langue: String) -> Exergue? {
        var noms: [String] = []
        for p in personnes.map({ $0.trimmingCharacters(in: .whitespaces) })
        where p.filter(\.isLetter).count >= 3 && !noms.contains(p) { noms.append(p) }
        guard !noms.isEmpty else { return nil }
        noms.sort { $0.count > $1.count }
        var motifs = ["«\\s*([^«»\\n]{40,320}?)\\s*»", "“([^“”\\n]{40,320}?)”"]
        if langue.hasPrefix("de") { motifs += ["„([^„“”\\n]{40,320}?)[“”]", "»([^»«\\n]{40,320}?)«"] }
        for p in paragraphes(texte) {
            let ns = p as NSString
            var candidats: [NSRange] = []   // plage de la citation (guillemets compris), puis du contenu
            var contenus: [NSRange] = []
            for motif in motifs {
                guard let re = try? NSRegularExpression(pattern: motif) else { continue }
                for m in re.matches(in: p, range: NSRange(location: 0, length: ns.length)) {
                    candidats.append(m.range); contenus.append(m.range(at: 1))
                }
            }
            // Les guillemets droits se lisent par paires, dans l'ordre : une regex apparierait le guillemet fermant
            // d'une citation avec l'ouvrant de la suivante.
            let droits = (0..<ns.length).filter { ns.character(at: $0) == 0x22 }
            for k in stride(from: 0, to: droits.count - 1, by: 2) {
                let a = droits[k], b = droits[k + 1]
                guard b - a - 1 >= 40, b - a - 1 <= 320 else { continue }
                candidats.append(NSRange(location: a, length: b - a + 1))
                contenus.append(NSRange(location: a + 1, length: b - a - 1))
            }
            for (r, c) in zip(candidats, contenus).sorted(by: { $0.0.location < $1.0.location }) {
                let citation = ns.substring(with: c).trimmingCharacters(in: .whitespaces)
                guard citation.split(separator: " ").count >= 8, texte.contains(citation) else { continue }
                let fin = r.location + r.length
                let apres = ns.substring(with: NSRange(location: fin, length: min(140, ns.length - fin)))
                let avantDebut = max(0, r.location - 140)
                let avant = ns.substring(with: NSRange(location: avantDebut, length: r.location - avantDebut))
                guard let nom = premierNom(noms, dans: apres, dernier: false) ?? premierNom(noms, dans: avant, dernier: true)
                else { continue }
                // « Reis » seul → « Pedro Reis », si l'article le nomme ainsi.
                let complet = noms.first { $0 != nom && $0.hasSuffix(" " + nom) } ?? nom
                return Exergue(citation: citation, auteur: complet)
            }
        }
        return nil
    }

    static func premierNom(_ noms: [String], dans s: String, dernier: Bool) -> String? {
        var trouve: (Int, String)?
        let ns = s as NSString
        for n in noms {
            guard let re = try? NSRegularExpression(pattern: "(?<![\\p{L}\\d])\(NSRegularExpression.escapedPattern(for: n))(?![\\p{L}\\d])")
            else { continue }
            let ms = re.matches(in: s, range: NSRange(location: 0, length: ns.length))
            guard let m = dernier ? ms.last : ms.first else { continue }
            if trouve == nil || (dernier ? m.range.location > trouve!.0 : m.range.location < trouve!.0) {
                trouve = (m.range.location, n)
            }
        }
        return trouve?.1
    }

    static func guillemets(_ s: String, langue: String) -> String {
        switch String(langue.prefix(2)).lowercased() {
        case "en": return "“\(s)”"
        case "de": return "„\(s)“"
        case "fr": return "«\u{00A0}\(s)\u{00A0}»"
        default: return "«\(s)»"
        }
    }

    // MARK: - Le DOI

    /// Le DOI d'une étude citée par l'article, s'il y en a un (« DOI : 10.1063/5.0324502 »).
    static func doi(_ texte: String) -> String? {
        guard let r = texte.range(of: "\\b10\\.\\d{4,9}/[^\\s\"<>()\\[\\]]+", options: .regularExpression) else { return nil }
        return String(texte[r]).trimmingCharacters(in: CharacterSet(charactersIn: ".,;:»”'"))
    }

    // MARK: - Les noms surlignés

    /// Les noms à surligner : un par nom, la première famille l'emporte ; ni le média lui-même, ni un « nom » de
    /// moins de deux lettres (`CompositeurRapportAnalyste.estArtefact`).
    static func nomsCites(_ entites: [RapportObsidian.EntiteRapport], source: String) -> [(nom: String, famille: Famille)] {
        var out: [(String, Famille)] = []
        var vus = Set<String>()
        let media = plier(source)
        for e in entites {
            let n = e.nom.trimmingCharacters(in: .whitespaces)
            guard let f = Famille.de(e.type), n.filter(\.isLetter).count >= 2, plier(n) != media,
                  vus.insert(plier(n)).inserted else { continue }
            out.append((n, f))
        }
        return out
    }

    static let protegesMarques = try! NSRegularExpression(
        pattern: "<mark[^>]*>.*?</mark>|<[^>]+>|!?\\[[^\\]]*\\]\\([^)]*\\)|`[^`]*`|https?://\\S+", options: [.caseInsensitive])

    /// La balise des noms : la classe que md Viewer rend déjà, et son style EN LIGNE pour une page web autonome.
    static func marque(_ t: String, rgb: String) -> String {
        "<mark class=\"ner-tag\" style=\"--ner-rgb:\(rgb);background:rgba(\(rgb),0.18);color:inherit;border-radius:3px;padding:0 2px;\">\(t)</mark>"
    }

    /// Surligne chaque nom cité de la couleur de sa famille — jamais dans une balise, un lien, une image ou du code.
    static func marquer(_ texte: String, noms: [(nom: String, famille: Famille)], html: Bool) -> String {
        guard !noms.isEmpty, !texte.isEmpty else { return texte }
        var couleur: [String: String] = [:]
        for (n, f) in noms { couleur[html ? h(n) : n] = f.rgb }
        let alternatives = couleur.keys.sorted { $0.count > $1.count }.map { NSRegularExpression.escapedPattern(for: $0) }
        guard let re = try? NSRegularExpression(pattern: "(?<![\\p{L}\\d])(?:\(alternatives.joined(separator: "|")))(?![\\p{L}\\d])")
        else { return texte }
        let ns = texte as NSString
        let tout = NSRange(location: 0, length: ns.length)
        let interdits = protegesMarques.matches(in: texte, range: tout).map(\.range)
        var out = texte
        for m in re.matches(in: texte, range: tout).reversed()
        where !interdits.contains(where: { NSIntersectionRange($0, m.range).length > 0 }) {
            let mot = ns.substring(with: m.range)
            guard let rgb = couleur[mot], let rr = Range(m.range, in: out) else { continue }
            out.replaceSubrange(rr, with: marque(mot, rgb: rgb))
        }
        return out
    }

    static func h(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\n", with: " ")
    }

    static func attr(_ s: String) -> String { h(s).replacingOccurrences(of: "\"", with: "&quot;") }

    /// Une adresse d'image ou de lien sûre à poser dans un attribut : http(s) seulement.
    static func url(_ s: String?) -> String? {
        guard let s = s?.trimmingCharacters(in: .whitespaces), let u = URL(string: s),
              let sc = u.scheme?.lowercased(), sc == "https" || sc == "http" else { return nil }
        return attr(s)
    }

    /// La même, pour un lien ou une image Markdown : brute (un `&amp;` y casserait l'adresse), sans espace ni
    /// parenthèse qui fermerait le lien.
    static func urlBrute(_ s: String?) -> String? {
        guard let s = s?.trimmingCharacters(in: .whitespaces), url(s) != nil,
              s.rangeOfCharacter(from: CharacterSet(charactersIn: " ()<>")) == nil else { return nil }
        return s
    }

    static func hote(_ s: String) -> String? {
        guard let host = URL(string: s)?.host?.lowercased(), !host.isEmpty else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    static func dateLongue(_ iso: String, langue: String) -> String? {
        let p = DateFormatter()
        p.locale = Locale(identifier: "en_US_POSIX"); p.dateFormat = "yyyy-MM-dd"
        guard let d = p.date(from: iso) else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: String(langue.prefix(2)).lowercased())
        f.setLocalizedDateFormatFromTemplate("EEEEdMMMMyyyy")
        return f.string(from: d)
    }

    // MARK: - La composition

    /// Ce que la fiche reçoit, en plus des données de l'article.
    struct Entree {
        var texte: Texte
        var resume: String? = nil
        var lots: [Lot]? = nil
        var diagramme: String? = nil
        var diagrammeDeterministe = false
        var imagesInline: [String] = []
        var carteDataURI: String? = nil
        var blocLeaflet: String? = nil
        var sectionLieux = ""
        var sectionNote = ""
    }

    /// **Le corps de la fiche** (sans frontmatter, sans signature : `RapportObsidian.generer` les pose).
    static func corps(_ d: RapportObsidian.DonneesRapport, _ e: Entree, langue: String) -> String {
        let t = textes(langue)
        let noms = nomsCites(d.entites, source: d.source)
        let traduit = d.traduit && !d.langueSource.isEmpty
        var blocs: [String] = []

        // ── L'ouverture : la grande image, le média, le temps de lecture ─────────────────────────────────
        let minutes = minutesDeLecture(e.texte.corps.isEmpty ? (e.texte.chapeau ?? "") : e.texte.corps)
        var pastilles: [String] = []
        if !d.source.isEmpty {
            let logo = url(d.logoSource).map {
                "<img src=\"\($0)\" alt=\"\" style=\"width:22px;height:22px;border-radius:50%;background:#fff;margin:0;display:inline-block;object-fit:contain;\">"
            } ?? RevuePresse.pastille(d.source, taille: 22)
            pastilles.append("<span style=\"display:inline-flex;align-items:center;gap:7px;font-size:0.8em;font-weight:700;padding:4px 11px 4px 4px;border-radius:999px;background:rgba(0,0,0,0.62);color:#fff;\">\(logo)\(h(d.source))</span>")
        }
        pastilles.append("<span style=\"font-size:0.8em;font-weight:600;padding:4px 11px;border-radius:999px;background:rgba(0,0,0,0.62);color:#fff;\">\(h(t.lecture(minutes)))</span>")
        if let image = url(d.imagePrincipale) {
            blocs.append("<div style=\"position:relative;aspect-ratio:16/9;border-radius:18px;overflow:hidden;background:rgba(127,127,127,0.14);\"><img src=\"\(image)\" alt=\"\(attr(d.titre))\" style=\"position:absolute;top:0;left:0;width:100%;height:100%;object-fit:cover;object-position:center;margin:0;border-radius:0;max-width:none;\"><div style=\"position:absolute;left:12px;bottom:12px;right:12px;display:flex;flex-wrap:wrap;gap:6px;\">\(pastilles.joined())</div></div>")
            if !d.source.isEmpty {
                blocs.append("<div style=\"font-size:0.8em;opacity:0.6;margin:6px 2px 0;\">\(h(t.image(d.source)))</div>")
            }
        } else {
            blocs.append("<div style=\"display:flex;flex-wrap:wrap;gap:6px;\">\(pastilles.joined())</div>")
        }

        // ── L'en-tête : surtitre, titre, titre original, pastilles ─────────────────────────────────────────
        let surtitre = [t.surtitre, d.source.isEmpty ? nil : d.source, dateLongue(d.dateStr, langue: langue)]
            .compactMap { $0 }.joined(separator: " · ")
        blocs.append("<div style=\"margin:26px 0 0;font-size:0.8em;font-weight:800;letter-spacing:0.22em;text-transform:uppercase;color:rgb(\(accent));\">\(h(surtitre))</div>")
        let titre = d.titre.hasSuffix(".") && !d.titre.hasSuffix("..") ? String(d.titre.dropLast()) : d.titre
        blocs.append("<div style=\"font-size:clamp(1.6em,7vw,2.15em);font-weight:800;line-height:1.12;margin:8px 0 10px;letter-spacing:-0.01em;text-wrap:balance;\">\(h(titre))</div>")
        if traduit, let original = d.titreOriginal, plier(original) != plier(d.titre) {
            let deuxPoints = langue.hasPrefix("fr") ? "\u{00A0}: " : ": "
            blocs.append("<div lang=\"\(attr(d.langueSource))\" style=\"font-size:0.92em;font-style:italic;opacity:0.7;margin:0 0 14px;\">\(h(t.titreOriginal))\(deuxPoints)\(h(guillemets(original, langue: langue)))</div>")
        }
        var rangee: [String] = []
        if traduit {
            rangee.append("<span style=\"font-size:0.8em;font-weight:600;padding:3px 10px;border-radius:999px;background:rgba(127,127,127,0.13);\">\(h(traduitDe(d.langueSource, langue: langue)))</span>")
        }
        if let lien = url(d.url) {
            rangee.append("<a href=\"\(lien)\" style=\"font-size:0.8em;font-weight:700;padding:3px 11px;border-radius:999px;background:rgba(\(accent),0.12);color:rgb(\(accent));text-decoration:none;\">\(h(t.lireOriginal))</a>")
        }
        blocs.append("<div style=\"display:flex;flex-wrap:wrap;gap:8px;align-items:center;padding-bottom:18px;border-bottom:3px double rgba(127,127,127,0.45);\">\(rangee.joined())</div>")

        // ── La note personnelle (§7.9) : la voix de l'utilisateur, avant la matière collectée ────────────
        // ⚠️ Nettoyée comme le texte : un `---` écrit par l'utilisateur ferait, lui aussi, un diaporama.
        if let note = d.note.map(nettoyerCorps), !note.isEmpty { blocs.append("## \(e.sectionNote)\n\n\(note)") }

        // ── En bref : le résumé rédigé au partage, sinon le chapeau ──────────────────────────────────────
        let bref: (texte: String, note: String)? = {
            if let r = e.resume.map(prose), !r.isEmpty { return (r, t.resumeAuto) }
            if let c = e.texte.chapeau.map(prose), !c.isEmpty { return (c, traduit ? t.chapeauTraduit : t.chapeau) }
            return nil
        }()
        if let bref {
            let taille = bref.texte.count > 320 ? "1.08em" : "1.3em"
            blocs.append("## \(t.enBref)")
            blocs.append("<div style=\"border-radius:16px;padding:20px 22px;background:rgba(\(accent),0.06);border:1px solid rgba(\(accent),0.22);border-left:5px solid rgb(\(accent));\"><div style=\"font-size:\(taille);line-height:1.45;font-weight:600;text-wrap:pretty;\">\(h(bref.texte))</div><div style=\"font-size:0.8em;opacity:0.7;margin-top:10px;\">\(h(bref.note))</div></div>")
        }

        // ── En chiffres : relevés dans le texte, contrôlés contre lui ─────────────────────────────────────
        let lots = (e.lots ?? chiffresDuTexte(e.texte.corps)).filter { !$0.chiffres.isEmpty }
        if !lots.isEmpty {
            blocs.append("## \(t.enChiffres)")
            var seuls: [Chiffre] = []
            for lot in lots {
                if lot.chiffres.count == 1 { seuls += lot.chiffres; continue }
                blocs.append(lot.barres ? barres(lot, noms: noms) : grille(lot, noms: noms))
            }
            if !seuls.isEmpty {
                let cartes = seuls.map {
                    "<div style=\"border:1px solid rgba(127,127,127,0.28);border-radius:14px;padding:12px 14px;\"><div style=\"font-size:1.6em;font-weight:800;line-height:1.15;font-variant-numeric:tabular-nums;\">\(h($0.valeur))</div><div style=\"font-size:0.84em;opacity:0.75;\">\(marquer(h($0.libelle), noms: noms, html: true))</div></div>"
                }
                blocs.append("<div style=\"display:grid;grid-template-columns:repeat(auto-fit,minmax(min(100%,200px),1fr));gap:12px;\">\(cartes.joined())</div>")
            }
            blocs.append("<div style=\"font-size:0.8em;opacity:0.7;margin-top:10px;\">\(h(t.chiffresNote))</div>")
        }

        // ── Qui est cité : une rangée de pastilles par famille ────────────────────────────────────────────
        let qui = quiEstCite(noms, t: t)
        if !qui.isEmpty {
            blocs.append("## \(t.quiEstCite)")
            blocs.append(qui)
            if !e.texte.corps.isEmpty {
                blocs.append("<div style=\"font-size:0.8em;opacity:0.7;margin-top:10px;\">\(h(t.surligne))</div>")
            }
        }

        // ── Le schéma : la figure légendée ────────────────────────────────────────────────────────────────
        if let diag = e.diagramme?.trimmingCharacters(in: .whitespacesAndNewlines), !diag.isEmpty {
            let legende = t.legende(genreSchema(diag, deterministe: e.diagrammeDeterministe))
            blocs.append("## \(t.schema)")
            // ⚠️ Le bloc ```mermaid entre deux lignes vides : md Viewer, Obsidian et une page rendue par marked le
            // reconnaissent ; la figure HTML l'encadre sans l'avaler.
            blocs.append("<figure style=\"margin:0;\"><div style=\"border:1px solid rgba(127,127,127,0.28);border-radius:16px;padding:12px 8px;\">\n\n```mermaid\n\(diag)\n```\n\n</div><figcaption style=\"font-size:0.84em;opacity:0.75;margin-top:8px;\"><span style=\"font-weight:700;\">\(h(t.figure)) 1 —</span> \(h(legende)) \(h(t.schemaNote))</figcaption></figure>")
        }

        // ── Le texte : mention de traduction, lettrine, citation en exergue, images ──────────────────────
        let paras = paragraphes(e.texte.corps)
        if !paras.isEmpty {
            blocs.append("## \(e.texte.integral ? t.texteIntegral : t.pointsCles)")
            if traduit {
                blocs.append("<div style=\"display:flex;flex-wrap:wrap;gap:8px;align-items:center;margin:-2px 0 18px;font-size:0.8em;\"><span style=\"font-weight:700;padding:2px 9px;border-radius:999px;background:rgba(127,127,127,0.13);\">\(h(traduitDe(d.langueSource, langue: langue)))</span><span style=\"opacity:0.7;\">\(h(t.foi))</span></div>")
            }
            let personnes = d.entites.filter { $0.type == .person }.map(\.nom)
            let ex = exergue(e.texte.corps, personnes: personnes, langue: langue)
            var images = e.imagesInline
            var texte: [String] = []
            for (i, p) in paras.enumerated() {
                texte.append(i == 0 ? (lettrine(p, noms: noms) ?? marquer(p, noms: noms, html: false))
                                    : marquer(p, noms: noms, html: false))
                if let ex, i == min(2, paras.count - 1) {
                    texte.append("<div style=\"margin:26px 0;padding:16px 4px;border-top:2px solid rgb(\(accent));border-bottom:1px solid rgba(127,127,127,0.3);\"><div style=\"font-size:1.32em;line-height:1.4;font-weight:700;text-wrap:balance;\">\(h(guillemets(ex.citation, langue: langue)))</div><div style=\"font-size:0.84em;opacity:0.75;margin-top:8px;\">— \(marquer(h(ex.auteur), noms: noms, html: true))</div></div>")
                }
                if (i + 1) % 3 == 0, !images.isEmpty, let u = urlBrute(images.removeFirst()) { texte.append("![](\(u))") }
            }
            for img in images { if let u = urlBrute(img) { texte.append("![](\(u))") } }
            blocs.append(texte.joined(separator: "\n\n"))
        }

        // ── La carte des lieux ────────────────────────────────────────────────────────────────────────────
        if (e.carteDataURI?.isEmpty == false) || e.blocLeaflet != nil {
            var c = "## \(e.sectionLieux)"
            if let carte = e.carteDataURI, !carte.isEmpty { c += "\n\n![\(RapportObsidian.echapMD(e.sectionLieux))](\(carte))" }
            if let leaflet = e.blocLeaflet { c += "\n\n" + leaflet }
            blocs.append(c)
        }

        // ── L'article d'origine ───────────────────────────────────────────────────────────────────────────
        blocs.append("## \(t.articleOrigine)")
        var carte = "<div style=\"border:1px solid rgba(127,127,127,0.28);border-radius:16px;padding:16px 18px;\">"
        if !d.source.isEmpty {
            let logo = url(d.logoSource).map {
                "<img src=\"\($0)\" alt=\"\" style=\"flex:0 0 44px;width:44px;height:44px;border-radius:50%;background:#fff;border:1px solid rgba(127,127,127,0.25);margin:0;object-fit:contain;\">"
            } ?? RevuePresse.pastille(d.source, taille: 44)
            var meta: [String] = []
            if let date = dateLongue(d.dateStr, langue: langue) { meta.append(t.publie(date)) }
            if !d.langueSource.isEmpty { meta.append(enLangue(d.langueSource, langue: langue)) }
            carte += "<div style=\"display:flex;gap:12px;align-items:center;\">\(logo)<div style=\"min-width:0;\"><div style=\"font-weight:700;\">\(h(d.source))</div><div style=\"font-size:0.84em;opacity:0.7;\">\(h(meta.joined(separator: " · ")))</div></div></div>"
        }
        let titreOrigine = traduit ? (d.titreOriginal ?? d.titre) : d.titre
        carte += "<div lang=\"\(attr(traduit ? d.langueSource : langue))\" style=\"font-size:1.08em;font-weight:600;line-height:1.35;margin:12px 0 14px;\">\(h(titreOrigine))</div>"
        if let lien = url(d.url), let hote = hote(d.url) {
            carte += "<a href=\"\(lien)\" style=\"display:block;text-align:center;font-weight:700;padding:11px 14px;border-radius:12px;background:rgb(\(accent));color:#fff;text-decoration:none;\">\(h(t.lireSur(hote)))</a>"
        }
        if let doi = doi(e.texte.corps + "\n" + (e.texte.chapeau ?? "")) {
            carte += "<div style=\"font-size:0.8em;opacity:0.7;margin-top:12px;overflow-wrap:anywhere;\">\(h(t.publicationCitee)) · <a href=\"https://doi.org/\(attr(doi))\" style=\"color:inherit;\">DOI \(h(doi))</a></div>"
        }
        carte += "</div>"
        blocs.append(carte)

        return blocs.joined(separator: "\n\n") + "\n"
    }

    /// La lettrine du premier paragraphe — seulement sur de la prose simple, qu'un bloc HTML ne défigure pas.
    static func lettrine(_ p: String, noms: [(nom: String, famille: Famille)]) -> String? {
        guard let premier = p.first, premier.isLetter,
              p.rangeOfCharacter(from: CharacterSet(charactersIn: "[]*_`<>#|")) == nil else { return nil }
        let reste = marquer(h(String(p.dropFirst())), noms: noms, html: true)
        return "<p style=\"font-size:1.04em;\"><span style=\"float:left;font-size:3.7em;line-height:0.8;font-weight:800;margin:7px 10px 0 0;color:rgb(\(accent));\">\(h(String(premier)))</span>\(reste)</p>"
    }

    static func entete(_ titre: String) -> String {
        "<div style=\"font-size:0.8em;font-weight:700;letter-spacing:0.08em;text-transform:uppercase;opacity:0.6;margin-bottom:12px;\">\(h(titre))</div>"
    }

    /// Deux pourcentages (ou plus) qui se comparent : une barre chacun, le premier en couleur.
    static func barres(_ lot: Lot, noms: [(nom: String, famille: Famille)]) -> String {
        var s = "<div style=\"border:1px solid rgba(127,127,127,0.28);border-radius:16px;padding:16px 18px;margin-bottom:12px;\">"
        if let titre = lot.titre { s += entete(titre) }
        for (i, c) in lot.chiffres.enumerated() {
            let rgb = i == 0 ? accent : ardoise
            let largeur = Int(min(100, max(0, c.pourcent ?? 0)).rounded())
            let libelle = c.libelle.prefix(1).uppercased() + c.libelle.dropFirst()
            s += "<div style=\"display:flex;justify-content:space-between;gap:10px;align-items:baseline;font-size:0.9em;\"><span>\(marquer(h(libelle), noms: noms, html: true))</span><span style=\"font-size:1.5em;font-weight:800;color:rgb(\(rgb));font-variant-numeric:tabular-nums;white-space:nowrap;\">\(h(c.valeur))</span></div>"
            s += "<div style=\"height:12px;border-radius:6px;background:rgba(127,127,127,0.15);margin:4px 0 \(i == lot.chiffres.count - 1 ? 4 : 14)px;overflow:hidden;\"><div style=\"width:\(largeur)%;height:100%;border-radius:6px;background:rgb(\(rgb));\"></div></div>"
        }
        return s + "</div>"
    }

    /// Des chiffres qui vont ensemble : en grand, côte à côte.
    static func grille(_ lot: Lot, noms: [(nom: String, famille: Famille)]) -> String {
        var s = "<div style=\"border:1px solid rgba(127,127,127,0.28);border-radius:16px;padding:16px 18px;margin-bottom:12px;\">"
        if let titre = lot.titre { s += entete(titre) }
        s += "<div style=\"display:grid;grid-template-columns:repeat(auto-fit,minmax(150px,1fr));gap:14px;\">"
        for c in lot.chiffres {
            s += "<div><div style=\"font-size:2em;font-weight:800;line-height:1.1;font-variant-numeric:tabular-nums;\">\(h(c.valeur))</div><div style=\"font-size:0.84em;opacity:0.75;\">\(marquer(h(c.libelle), noms: noms, html: true))</div></div>"
        }
        return s + "</div></div>"
    }

    /// « Qui est cité » : une rangée par famille. Un nom de famille seul (« Reis ») s'efface devant le nom complet
    /// (« Pedro Reis ») — le texte, lui, surligne les deux.
    static func quiEstCite(_ noms: [(nom: String, famille: Famille)], t: Textes) -> String {
        var rangees: [String] = []
        for f in Famille.allCases {
            var liste = noms.filter { $0.famille == f }.map(\.nom)
            if f == .personnes {
                liste = liste.filter { n in !n.contains(" ") ? !liste.contains { $0 != n && $0.hasSuffix(" " + n) } : true }
            }
            guard !liste.isEmpty else { continue }
            let pastilles = liste.prefix(15).map {
                "<span style=\"font-size:0.88em;padding:3px 11px;border-radius:999px;background:rgba(\(f.rgb),0.14);\">\(h($0))</span>"
            }.joined()
            rangees.append("<div><div style=\"font-size:0.8em;font-weight:700;letter-spacing:0.08em;text-transform:uppercase;opacity:0.6;margin-bottom:6px;\">\(h(t.famille(f)))</div><div style=\"display:flex;flex-wrap:wrap;gap:6px;\">\(pastilles)</div></div>")
        }
        return rangees.isEmpty ? "" : "<div style=\"display:grid;gap:12px;\">\(rangees.joined())</div>"
    }
}

// MARK: - Le relevé par le modèle

extension FicheArticle {
    /// **Les chiffres clés proposés par le modèle de l'appareil**, puis contrôlés un à un (`chiffresDepuisModele`).
    /// `nil` sans Apple Intelligence, après un échec ou un délai, ou s'il reste moins de deux chiffres : la fiche
    /// relève alors les chiffres par le code seul (`chiffresDuTexte`).
    static func chiffresIA(texte: String, langue: String) async -> [Lot]? {
        guard let reponse = await reponseChiffresIA(texte: texte, langue: langue) else { return nil }
        return chiffresDepuisModele(reponse, texte: texte)
    }

    /// La réponse brute du modèle (le banc la montre ; la fiche ne l'écrit jamais sans `chiffresDepuisModele`).
    static func reponseChiffresIA(texte: String, langue: String) async -> String? {
        #if canImport(FoundationModels) && !os(tvOS)
        guard !texte.isEmpty, DisponibiliteAppleIntelligence().messageIndisponibilite == nil else { return nil }
        let moteur = MoteurFM(instructions: """
            Tu relèves des chiffres dans un texte, sans rien inventer ni reformuler. Tu réponds uniquement par les \
            lignes demandées.
            """)
        let invite = inviteChiffres(texte: String(texte.prefix(BudgetContexteLLM.plafondAdaptatif(6_000, max: 60_000))),
                                    langue: langue, nomLangue: LangueHelper.nomCible(langue))
        do {
            return try await avecDelaiMaxFond(60) { try await moteur.repondre(invite) }
        } catch { return nil }
        #else
        return nil
        #endif
    }
}
