import Foundation
import NaturalLanguage
import os
#if canImport(Translation)
import Translation
#endif

/// Un morceau de texte du document rendu — un nœud de texte du DOM, numéroté.
/// Les morceaux `protege` se lisent mais ne se traduisent pas : cible de wiki-lien,
/// nom d'entité, code, URL. Ils sont transmis au modèle quand même, car il lui faut la
/// phrase entière pour bien traduire ce qui les entoure, et il les rend intacts.
struct TranslationPart: Decodable {
    let i: Int
    let texte: String
    let protege: Bool
}

/// Un bloc du document : un paragraphe, un titre, une puce, une cellule. C'est l'unité
/// de traduction — une phrase coupée en deux requêtes se traduit deux fois moins bien —
/// et l'unité d'animation.
struct TranslationBlock: Decodable {
    let id: Int
    let haut: Int        // position absolue dans la page, pour ordonner la vague
    let signes: Int      // poids en caractères, pour un avancement honnête
    let parts: [TranslationPart]
}

/// Un bloc traduit, prêt à être réécrit dans le DOM.
struct TranslatedBlock {
    let id: Int
    /// Les morceaux, dans l'ordre du texte traduit.
    let parts: [(i: Int, texte: String)]
    /// Vrai quand cet ordre est représentable dans le DOM — voir `traduire(bloc:session:)`.
    let reordonnable: Bool
}

/// La traduction d'un document, sur l'appareil, bloc par bloc.
///
/// La classe ne connaît pas le framework `Translation` : ses types n'existent qu'à partir
/// d'iOS 18 et de macCatalyst 26, et une propriété stockée d'un type indisponible
/// contaminerait toute la vue qui la détient. Elle publie donc une simple `Demande`
/// (deux codes de langue et un jeton) ; c'est `TranslationHostView` qui en fait une
/// `TranslationSession.Configuration` et rend la session par l'extension plus bas.
@MainActor
final class DocumentTranslator: ObservableObject {

    /// Journal de mise au point. Une traduction qui s'arrête au milieu ne laisse aucune
    /// trace visible — le document reste simplement à moitié traduit — et c'est
    /// exactement le genre de panne qu'on ne reproduit pas deux fois de la même façon.
    /// `log show --debug --predicate 'subsystem == "ch.ok-ia.markdownviewer"'`
    static let journal = Logger(subsystem: "ch.ok-ia.markdownviewer", category: "traduction")

    enum State: Equatable {
        case idle
        /// Rien à faire : document déjà dans la langue du lecteur, ou paire indisponible.
        case skipped(String)
        case running(faits: Int, total: Int)      // en caractères, pas en blocs
        /// « traduit, sauf trois paragraphes » — une fin qui n'arrive pas est pire qu'un échec.
        case finished(blocs: Int, echecs: Int)
        case failed(String)
    }

    /// Ce que la vue hôte doit ouvrir. Le jeton rend chaque demande distincte : deux
    /// configurations de même paire sont ÉGALES, et `translationTask` ne se relance que
    /// si la valeur change — sans cela, le deuxième document fr→de ne serait jamais
    /// traduit. Mesuré au banc, `tools/TranslationBench`.
    struct Demande: Equatable {
        let source: String
        let cible: String
        let jeton: Int
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var demande: Demande?

    /// La langue d'origine du document en cours, pour l'annoncer au lecteur. Elle survit
    /// à la fin de la traduction, alors que `demande` retombe à nil.
    @Published private(set) var demandeSource: String?

    /// Appelé pour chaque bloc traduit, dans l'ordre où la vague les traite.
    var onBloc: ((TranslatedBlock) -> Void)?

    /// Les libellés hors texte — Mermaid, marqueurs de cartes — à traduire quand la vague
    /// a fini. Ils passent en dernier : ce qui se lit d'abord, c'est la prose.
    var extras: (() async -> [String])?
    var onExtras: (([String: String]) -> Void)?

    private var file: [TranslationBlock] = []
    private var totalSignes = 0
    private var faitsSignes = 0
    private var echecs = 0
    private var jeton = 0

    // MARK: - Décider s'il y a lieu de traduire

    /// La langue du document, devinée sur sa prose — pas sur sa syntaxe. Rien ne sort de
    /// l'appareil : `NLLanguageRecognizer` travaille en local comme le reste.
    static func langue(de blocs: [TranslationBlock]) -> String? {
        let prose = blocs
            .flatMap { $0.parts }
            .filter { !$0.protege }
            .map { $0.texte }
            .joined(separator: " ")
        let echantillon = String(prose.prefix(4000))
        guard echantillon.count >= 40 else { return nil }   // trop court pour deviner
        let devin = NLLanguageRecognizer()
        devin.processString(echantillon)
        guard let langue = devin.dominantLanguage else { return nil }
        // La confiance compte : un document trilingue ou très court ferait dire n'importe
        // quoi au devin, et traduire à tort est pire que ne pas traduire.
        let hypotheses = devin.languageHypotheses(withMaximum: 1)
        guard let confiance = hypotheses[langue], confiance >= 0.60 else { return nil }
        return langue.rawValue
    }

    /// Vrai quand la traduction peut tourner sur cet appareil pour cette paire.
    /// `status(from:to:)` fait foi et répond en quelques dizaines de millisecondes —
    /// `supportedLanguages`, lui, annonce 38 langues jusque sur un simulateur où plus
    /// rien ne traduit. Mesuré au banc.
    static func disponible(de source: String, vers cible: String) async -> Bool {
        #if canImport(Translation)
        if #available(iOS 18.0, macCatalyst 26.0, macOS 15.0, *) {
            let statut = await LanguageAvailability().status(
                from: Locale.Language(identifier: source),
                to: Locale.Language(identifier: cible))
            switch statut {
            case .installed, .supported: return true
            case .unsupported: return false
            @unknown default: return false
            }
        }
        #endif
        return false
    }

    // MARK: - Lancer

    /// Prépare la file et demande une session. La vague part du premier bloc visible et
    /// descend ; ce qui reste au-dessus suit ensuite, en silence. Un rapport rouvert à la
    /// page 7 ne doit pas faire attendre six pages que personne ne regarde.
    func demarrer(blocs: [TranslationBlock], defilement: Int, source: String, cible: String) {
        guard !blocs.isEmpty else {
            state = .skipped("document sans texte à traduire")
            return
        }
        Self.journal.debug("démarrage \(source, privacy: .public)→\(cible, privacy: .public) : \(blocs.count) blocs, défilement \(defilement)")
        file = Self.ordonner(blocs, depuis: defilement)
        totalSignes = max(1, blocs.reduce(0) { $0 + $1.signes })
        faitsSignes = 0
        echecs = 0
        state = .running(faits: 0, total: totalSignes)
        jeton += 1
        demandeSource = source
        demande = Demande(source: source, cible: cible, jeton: jeton)
    }

    /// Ce qui est à l'écran d'abord, le reste ensuite — l'ordre seul change, tout le
    /// document y passe. Une direction se lit : le lecteur comprend en une seconde où en
    /// est le travail. Un ordre optimisé irait plus vite et ressemblerait à du désordre.
    static func ordonner(_ blocs: [TranslationBlock], depuis defilement: Int) -> [TranslationBlock] {
        let tries = blocs.sorted { $0.haut < $1.haut }
        let dessous = tries.filter { $0.haut >= defilement }
        let dessus  = tries.filter { $0.haut <  defilement }
        return dessous + dessus
    }

    func annuler() {
        file = []
        demande = nil
        demandeSource = nil
        state = .idle
    }

    fileprivate func avancer(_ signes: Int) {
        faitsSignes = min(totalSignes, faitsSignes + signes)
        state = .running(faits: faitsSignes, total: totalSignes)
    }

    fileprivate func terminer(blocs: Int) {
        demande = nil
        state = .finished(blocs: blocs, echecs: echecs)
    }

    fileprivate func compterEchec() { echecs += 1 }

    fileprivate var fileCourante: [TranslationBlock] { file }
}

#if canImport(Translation)

/// L'index du nœud d'où vient chaque morceau. Un attribut à nous, pas de Foundation :
/// vérifié au banc, il survit à la traduction et se réaligne sur le sens — les trois
/// phrases numérotées reviennent numérotées, dans l'ordre. C'est lui qui permet de
/// réécrire chaque nœud de texte à sa place sans jamais reconstruire de HTML.
@available(iOS 18.0, macCatalyst 26.0, macOS 15.0, *)
enum OKiaNodeIndex: AttributedStringKey {
    typealias Value = Int
    static let name = "okiaIndexNoeud"
}

@available(iOS 18.0, macCatalyst 26.0, macOS 15.0, *)
extension DocumentTranslator {

    /// Traduit la file, bloc par bloc, en rendant chaque bloc dès qu'il arrive.
    ///
    /// Le lot n'accélère rien — mesuré au banc : douze blocs coûtent 9,3 s en lot contre
    /// 8,4 s un par un, parce que le framework traduit en série et se contente de diffuser.
    /// On garde donc la main sur l'ordre, ce qui permettra plus tard de repasser devant un
    /// bloc que le lecteur vient d'atteindre.
    func traduire(avec session: TranslationSession) async {
        let blocs = fileCourante
        var rendus = 0

        Self.journal.debug("session ouverte, \(blocs.count) blocs en file")
        for bloc in blocs {
            if Task.isCancelled {
                Self.journal.debug("annulé après \(rendus) blocs")
                break
            }
            do {
                let rendu = try await Self.traduire(bloc: bloc, session: session)
                onBloc?(TranslatedBlock(id: bloc.id, parts: rendu.parts,
                                        reordonnable: rendu.reordonnable))
                rendus += 1
            } catch {
                // Un bloc qui échoue ne fait pas échouer le document : la barre doit
                // pouvoir finir en disant « traduit, sauf trois paragraphes ».
                Self.journal.error("bloc \(bloc.id) en échec : \(String(describing: error), privacy: .public)")
                compterEchec()
            }
            avancer(bloc.signes)
        }
        // Les libellés de diagrammes et de cartes en dernier : un diagramme se redessine,
        // et mieux vaut que ce soit une fois, à la fin, sous le regard d'un lecteur qui a
        // déjà son texte.
        if !Task.isCancelled, let demande = await extras?(), !demande.isEmpty {
            var table: [String: String] = [:]
            for libelle in demande {
                if Task.isCancelled { break }
                if let reponse = try? await session.translate(libelle) {
                    table[libelle] = reponse.targetText
                }
            }
            Self.journal.debug("libellés hors texte : \(table.count)/\(demande.count)")
            if !table.isEmpty { onExtras?(table) }
        }

        Self.journal.debug("fin : \(rendus) blocs rendus")
        terminer(blocs: rendus)
    }


    /// Recoud les jointures et les points de suture internes.
    ///
    /// Les frontières entre morceaux ne tombent pas où le français les avait mises : le
    /// modèle rend « … 30. Juni ." avec une espace de trop, ou colle deux morceaux sans
    /// séparateur — « veröffentlichtder Gemeindeseite ». Trois règles, et seulement
    /// celles qui valent dans les cinq langues de l'app.
    private static func recoudre(_ sequence: [(i: Int, texte: String)],
                                 proteges: Set<Int>) -> [(i: Int, texte: String)] {
        var out = sequence

        // 1. À l'intérieur d'un morceau : une espace devant un point ou une virgule n'a
        //    sa place dans aucune des cinq langues. On s'arrête là — « ; : ! ? » en
        //    prennent une en français, et corriger l'allemand en abîmant le français
        //    serait un mauvais échange.
        for k in 0..<out.count where !proteges.contains(out[k].i) {
            out[k].texte = out[k].texte
                .replacingOccurrences(of: "[ \u{00A0}\u{202F}]+([.,])",
                                      with: "$1", options: .regularExpression)
        }

        let fermantes = CharacterSet(charactersIn: ".,;:!?…)]}»%")
        for k in 0..<max(0, out.count - 1) {
            let courantProtege = proteges.contains(out[k].i)
            let suivantProtege = proteges.contains(out[k + 1].i)
            guard let premier = out[k + 1].texte.first else { continue }

            // 2. « Juni  . » → « Juni. »
            if !courantProtege, out[k].texte.last?.isWhitespace == true,
               let apres = out[k + 1].texte.drop(while: { $0.isWhitespace }).first,
               let scalaire = apres.unicodeScalars.first, fermantes.contains(scalaire) {
                out[k].texte = String(out[k].texte.reversed()
                                        .drop(while: { $0.isWhitespace }).reversed())
            }

            // 3. Deux mots soudés à une jointure : « veröffentlichtder ». Le DOM sépare
            //    deux nœuds là où la phrase avait un blanc ; quand la traduction déplace
            //    l'un des deux, ce blanc peut se perdre. Deux caractères de mot qui se
            //    touchent à une frontière n'arrivent jamais dans ces cinq langues.
            let dernier = out[k].texte.last
            if let d = dernier, d.isLetter || d.isNumber, premier.isLetter || premier.isNumber {
                if suivantProtege {
                    out[k].texte += " "
                } else {
                    out[k + 1].texte = " " + out[k + 1].texte
                }
            }
        }
        return out
    }

    /// Un bloc, une requête. Les morceaux protégés partent avec le reste — la phrase
    /// entière — mais marqués : le modèle les rend intacts au lieu de traduire une cible
    /// de wiki-lien en allemand.
    private static func traduire(bloc: TranslationBlock, session: TranslationSession)
        async throws -> (parts: [(i: Int, texte: String)], reordonnable: Bool) {
        if #available(iOS 26.4, macCatalyst 26.4, macOS 26.4, *) {
            var source = AttributedString()
            for part in bloc.parts {
                var morceau = AttributedString(part.texte)
                morceau[OKiaNodeIndex.self] = part.i
                if part.protege { morceau.skipsTranslation = true }
                source.append(morceau)
            }
            let reponse = try await session.translate(source)
            guard let cible = reponse.attributedTargetText else {
                throw TranslationError.internalError
            }
            // Les segments reviennent alignés sur le sens, ET dans l'ordre de la langue
            // d'arrivée — qui n'est pas celui du français. On garde cet ordre : c'est lui
            // qui dit où chaque morceau doit atterrir dans la phrase allemande. Les
            // morceaux protégés restent dans la séquence, sans quoi on ignorerait où le
            // modèle les a placés.
            // Un même nœud peut recevoir plusieurs segments, et pas toujours d'affilée :
            // l'allemand peut couper ce que le français disait d'un trait. On fusionne
            // donc par nœud — sans quoi le dernier segment écrase les précédents et le
            // texte disparaît — en gardant l'ordre de première apparition.
            var ordre: [Int] = []
            var textes: [Int: String] = [:]
            var contigu = true
            var precedent: Int?
            for run in cible.runs {
                guard let index = run[OKiaNodeIndex.self] else { continue }
                let morceau = String(cible[run.range].characters)
                if textes[index] == nil {
                    ordre.append(index)
                } else if precedent != index {
                    // Le nœud revient plus loin dans la phrase : son contenu est éclaté en
                    // deux endroits que le DOM ne peut pas représenter d'un seul tenant.
                    contigu = false
                }
                textes[index, default: ""] += morceau
                precedent = index
            }
            var sequence = ordre.map { (i: $0, texte: textes[$0] ?? "") }
            let proteges = Set(bloc.parts.filter { $0.protege }.map { $0.i })
            sequence = recoudre(sequence, proteges: proteges)
            // On ne remet dans l'ordre de la langue d'arrivée que si cet ordre est
            // représentable : un nœud éclaté rendrait la phrase incomplète ou mélangée.
            // Dans ce cas on garde l'ordre du français — imparfait, mais entier.
            return (parts: sequence, reordonnable: contigu)
        }

        // Repli pour iOS 18 → 26.3, où `skipsTranslation` et la traduction d'un
        // `AttributedString` n'existent pas encore : chaque morceau part seul. Le modèle
        // perd le contexte de la phrase, mais rien ne casse — et un bloc sans morceau
        // protégé, le cas courant, n'y perd qu'un peu de qualité.
        var resultat: [(i: Int, texte: String)] = []
        for part in bloc.parts where !part.protege {
            let reponse = try await session.translate(part.texte)
            resultat.append((i: part.i, texte: reponse.targetText))
        }
        // Chaque morceau traduit seul : rien ne dit où la phrase voudrait le placer, donc
        // on ne déplace rien.
        return (parts: resultat, reordonnable: false)
    }
}

#endif
