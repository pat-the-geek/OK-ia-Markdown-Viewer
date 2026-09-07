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
    let parts: [(i: Int, texte: String)]
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

    /// Appelé pour chaque bloc traduit, dans l'ordre où la vague les traite.
    var onBloc: ((TranslatedBlock) -> Void)?

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
                let parts = try await Self.traduire(bloc: bloc, session: session)
                onBloc?(TranslatedBlock(id: bloc.id, parts: parts))
                rendus += 1
            } catch {
                // Un bloc qui échoue ne fait pas échouer le document : la barre doit
                // pouvoir finir en disant « traduit, sauf trois paragraphes ».
                Self.journal.error("bloc \(bloc.id) en échec : \(String(describing: error), privacy: .public)")
                compterEchec()
            }
            avancer(bloc.signes)
        }
        Self.journal.debug("fin : \(rendus) blocs rendus")
        terminer(blocs: rendus)
    }

    /// Un bloc, une requête. Les morceaux protégés partent avec le reste — la phrase
    /// entière — mais marqués : le modèle les rend intacts au lieu de traduire une cible
    /// de wiki-lien en allemand.
    private static func traduire(bloc: TranslationBlock,
                                 session: TranslationSession) async throws -> [(i: Int, texte: String)] {
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
            // Les segments reviennent alignés sur le sens : le gras suit son syntagme même
            // quand l'allemand rejette le verbe en fin de phrase. On recolle par index.
            var parIndex: [Int: String] = [:]
            for run in cible.runs {
                guard let index = run[OKiaNodeIndex.self] else { continue }
                parIndex[index, default: ""] += String(cible[run.range].characters)
            }
            return bloc.parts.compactMap { part in
                guard !part.protege, let texte = parIndex[part.i] else { return nil }
                return (i: part.i, texte: texte)
            }
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
        return resultat
    }
}

#endif
