// Banc d'essai du framework Translation — hors de l'app, pour répondre par l'expérience
// aux trois questions de l'entrée 1.2 : couverture des cinq langues et Mac Catalyst,
// diffusion des résultats (une réponse par requête ou séquence au fil de l'eau),
// et moment où tombe l'invite de téléchargement du dictionnaire.

import SwiftUI
import Translation
import Foundation

let LANGUES = ["fr", "en", "de", "es", "it"]

// Un document d'essai : des blocs de tailles réalistes, avec la syntaxe Markdown
// qui ne doit pas survivre au hasard mais par construction.
let BLOCS: [String] = [
    "Rapport annuel 2026 de la commune de Villeneuve",
    "Le présent rapport rend compte de l'exercice écoulé et des décisions prises par le conseil communal. Il couvre les comptes, les investissements réalisés et les perspectives pour l'année suivante.",
    "Les charges de fonctionnement s'élèvent à 4,2 millions de francs, en hausse de 3,1 % par rapport à l'exercice précédent. Cette progression s'explique principalement par l'indexation des salaires et par la mise en service de la nouvelle installation de chauffage à distance.",
    "Le taux d'endettement reste maîtrisé.",
    "Trois chantiers ont été menés à leur terme : la réfection du collecteur d'eaux usées du chemin des Vignes, l'assainissement énergétique de la salle polyvalente et le remplacement de l'éclairage public par des luminaires à diodes.",
    "La commission de gestion a siégé à sept reprises.",
    "Les recettes fiscales des personnes physiques ont progressé de 2,4 %, tandis que celles des personnes morales reculent de 1,8 % sous l'effet du départ d'une entreprise du secteur horloger.",
    "Perspectives pour 2027",
    "Le conseil entend poursuivre l'effort d'assainissement du patrimoine bâti et engager l'étude d'une nouvelle desserte en transports publics vers le chef-lieu du district.",
    "Une consultation publique sera organisée au printemps.",
    "Le budget 2027 prévoit un excédent de charges de 180 000 francs, absorbable par la fortune nette.",
    "Annexes : comptes détaillés, tableau des amortissements, liste des subventions accordées.",
]

actor Minuterie {
    var fini = false
    func marquer() { fini = true }
}

@MainActor
final class Banc: ObservableObject {
    @Published var config: TranslationSession.Configuration?
    private var travail: ((TranslationSession) async -> Void)?
    private var suite: CheckedContinuation<Void, Never>?
    private var rapport = ""
    private let debut = Date()
    private var versions = 0
    private lazy var chemin: String = ProcessInfo.processInfo.environment["BENCH_OUT"]
        ?? "/tmp/banc-translation.txt"

    func dire(_ texte: String = "") {
        let t = String(format: "%7.3f", Date().timeIntervalSince(debut))
        let ligne = texte.isEmpty ? "" : "[\(t)] \(texte)"
        print(ligne)
        fflush(stdout)
        rapport += ligne + "\n"
        // Écrit à chaque ligne : l'app peut être lancée sans terminal (open -a),
        // et une épreuve qui bloque ne doit pas emporter le journal avec elle.
        try? rapport.write(toFile: chemin, atomically: true, encoding: .utf8)
    }

    // Le session n'est valide que dans la fermeture de `translationTask` : on lui envoie
    // donc le travail à faire, on ne fait pas sortir la session.
    func avecSession(_ de: String, _ vers: String,
                     _ corps: @escaping (TranslationSession) async -> Void) async {
        // Une épreuve abandonnée laisse sa continuation en suspens : on la libère ici,
        // sinon la suivante écraserait une continuation jamais reprise.
        if let ancienne = suite { suite = nil; ancienne.resume() }
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            self.travail = corps
            self.suite = c
            var cfg = TranslationSession.Configuration(
                source: Locale.Language(identifier: de),
                target: Locale.Language(identifier: vers))
            // Deux configurations de même paire sont ÉGALES, et translationTask ne se
            // relance que si la valeur change : sans invalidate(), la deuxième session
            // fr→de n'arrive jamais. La version doit être strictement croissante, d'où
            // le compteur — une seule invalidation redonnerait la version 1 chaque fois.
            self.versions += 1
            for _ in 0..<self.versions { cfg.invalidate() }
            self.config = nil
            DispatchQueue.main.async { self.config = cfg }
        }
    }

    // Chaque épreuve sous surveillance. Une course, pas un simple avertissement : sur le
    // simulateur, prepareTranslation() ne rend JAMAIS la main — sans abandon, le banc
    // resterait suspendu exactement là où l'app le serait.
    func sousMinuterie(_ nom: String, _ secondes: UInt64, _ corps: @escaping () async -> Void) async {
        await withTaskGroup(of: Bool.self) { groupe in
            groupe.addTask { await corps(); return true }
            groupe.addTask {
                try? await Task.sleep(nanoseconds: secondes * 1_000_000_000)
                return false
            }
            let premier = await groupe.next() ?? false
            if !premier {
                self.dire("!! \(nom) : rien après \(secondes) s — ABANDON, on passe à la suite.")
            }
            groupe.cancelAll()
        }
    }

    func executer(_ session: TranslationSession) async {
        guard let t = travail else { return }
        travail = nil
        await t(session)
        suite?.resume()
        suite = nil
    }

    func ecrireRapport() {
        let sortie = ProcessInfo.processInfo.environment["BENCH_OUT"]
            ?? NSTemporaryDirectory() + "banc-translation.txt"
        try? rapport.write(toFile: sortie, atomically: true, encoding: .utf8)
        print("→ rapport écrit dans \(sortie)")
        fflush(stdout)
    }

    // MARK: - Les épreuves

    func toutFaire() async {
        #if targetEnvironment(macCatalyst)
        let plateforme = "Mac Catalyst"
        #else
        let plateforme = "iOS"
        #endif
        #if targetEnvironment(simulator)
        let sim = " (simulateur)"
        #else
        let sim = ""
        #endif
        dire("PLATEFORME : \(plateforme)\(sim) — \(ProcessInfo.processInfo.operatingSystemVersionString)")
        dire()

        // BENCH_ONLY=9 ou BENCH_ONLY=1,3,9 : ne lancer que ces épreuves.
        let choisies: Set<Int>? = ProcessInfo.processInfo.environment["BENCH_ONLY"].map {
            Set($0.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) })
        }
        func retenue(_ n: Int) -> Bool { choisies == nil || choisies!.contains(n) }

        if retenue(1) { await sousMinuterie("1. couverture", 30) { await self.epreuve1Couverture() } }
        if retenue(2), ProcessInfo.processInfo.environment["BENCH_SANS_PREPARE"] == nil {
            await sousMinuterie("2. invite", 60) { await self.epreuve2Invite() }
        } else if retenue(2) {
            dire("=== 2. INVITE — sautée (BENCH_SANS_PREPARE) ===")
            dire()
        }
        if retenue(3) { await sousMinuterie("3. diffusion", 120) { await self.epreuve3Diffusion() } }
        if retenue(4) { await sousMinuterie("4. markdown", 120) { await self.epreuve4Markdown() } }
        if retenue(5) { await sousMinuterie("5. skipsTranslation", 60) { await self.epreuve5SautTraduction() } }
        if retenue(9) { await sousMinuterie("9. attributs", 120) { await self.epreuve9Attributs() } }
        if retenue(6) { await sousMinuterie("6. débit", 300) { await self.epreuve6Debit() } }
        if retenue(7) { await sousMinuterie("7. paires", 300) { await self.epreuve7Paires() } }
        if retenue(8) { await sousMinuterie("8. langue absente", 180) { await self.epreuve8LangueAbsente() } }

        dire()
        dire("FIN")
        ecrireRapport()
        exit(0)
    }

    // 1. Couverture des cinq langues — sans session, donc sans invite.
    func epreuve1Couverture() async {
        dire("=== 1. COUVERTURE ===")
        let dispo = LanguageAvailability()
        let langues = await dispo.supportedLanguages
        let codes = langues.map { $0.maximalIdentifier }.sorted()
        dire("supportedLanguages : \(langues.count) langues")
        dire(codes.joined(separator: " "))
        dire()
        let racines = Set(langues.compactMap { $0.languageCode?.identifier })
        for l in LANGUES {
            dire("  \(l) présent dans supportedLanguages : \(racines.contains(l) ? "oui" : "NON")")
        }
        dire()
        dire("statut des 20 paires (installed / supported / unsupported) :")
        for de in LANGUES {
            var ligne = "  \(de) → "
            for vers in LANGUES where vers != de {
                let s = await dispo.status(from: Locale.Language(identifier: de),
                                           to: Locale.Language(identifier: vers))
                let m: String
                switch s {
                case .installed: m = "installé"
                case .supported: m = "à télécharger"
                case .unsupported: m = "NON PRIS EN CHARGE"
                @unknown default: m = "?"
                }
                ligne += "\(vers)=\(m)  "
            }
            dire(ligne)
        }
        dire()
    }

    // 2. Quand tombe l'invite de téléchargement.
    func epreuve2Invite() async {
        dire("=== 2. INVITE DE TÉLÉCHARGEMENT (fr → de) ===")
        dire("avant translationTask — aucune invite attendue à ce stade")
        await avecSession("fr", "de") { session in
            self.dire("session créée par translationTask")
            self.dire("  canRequestDownloads = \(session.canRequestDownloads)")
            let pret = await session.isReady
            self.dire("  isReady = \(pret)")
            self.dire("AVANT prepareTranslation() — c'est ici que l'invite devrait tomber")
            let t0 = Date()
            do {
                try await session.prepareTranslation()
                self.dire("APRÈS prepareTranslation() — \(String(format: "%.2f", Date().timeIntervalSince(t0))) s, sans erreur")
            } catch {
                self.dire("APRÈS prepareTranslation() — ERREUR : \(error)")
            }
            let pret2 = await session.isReady
            self.dire("  isReady après préparation = \(pret2)")
        }
        dire()
    }

    // 3. Diffusion : une réponse par requête, ou séquence au fil de l'eau ?
    func epreuve3Diffusion() async {
        dire("=== 3. DIFFUSION DES RÉSULTATS (fr → de, \(BLOCS.count) blocs) ===")
        await avecSession("fr", "de") { session in
            let requetes = BLOCS.enumerated().map {
                TranslationSession.Request(sourceText: $0.element, clientIdentifier: "b\($0.offset)")
            }
            self.dire("a) translate(batch:) — horodatage de chaque élément reçu")
            let t0 = Date()
            var premier: TimeInterval = 0
            var n = 0
            do {
                for try await r in session.translate(batch: requetes) {
                    let dt = Date().timeIntervalSince(t0)
                    if n == 0 { premier = dt }
                    n += 1
                    self.dire(String(format: "   +%6.3f s  %@  (%d car → %d car)",
                                     dt, r.clientIdentifier ?? "?", r.sourceText.count, r.targetText.count))
                }
                let total = Date().timeIntervalSince(t0)
                self.dire(String(format: "   → %d réponses, premier à %.3f s, total %.3f s", n, premier, total))
                self.dire(premier < total * 0.5
                          ? "   → AU FIL DE L'EAU : le premier bloc arrive bien avant la fin."
                          : "   → EN BLOC : tout arrive à la fin, la séquence ne diffuse pas.")
            } catch {
                self.dire("   ERREUR : \(error)")
            }
            self.dire()
            self.dire("b) translations(from:) — attente de la liste complète")
            let t1 = Date()
            do {
                let rs = try await session.translations(from: requetes)
                self.dire(String(format: "   → %d réponses en %.3f s", rs.count, Date().timeIntervalSince(t1)))
            } catch {
                self.dire("   ERREUR : \(error)")
            }
            self.dire()
            self.dire("c) translate(_:) un par un, en série")
            let t2 = Date()
            for (i, b) in BLOCS.enumerated() {
                let ti = Date()
                if let r = try? await session.translate(b) {
                    self.dire(String(format: "   b%d  %6.3f s  %d car", i, Date().timeIntervalSince(ti), r.targetText.count))
                }
            }
            self.dire(String(format: "   → total %.3f s", Date().timeIntervalSince(t2)))
        }
        dire()
    }

    // 4. Ce qui ne doit pas être traduit : la syntaxe survit-elle ?
    func epreuve4Markdown() async {
        dire("=== 4. SYNTAXE MARKDOWN ET CIBLES (fr → de) ===")
        let essais = [
            "Voir le rapport **complet** et la *méthode* employée.",
            "La carte est publiée sur [le site communal](https://ok-ia.ch/rapport.html).",
            "Le chapitre [[Rapport annuel 2026]] décrit la méthode de calcul.",
            "Utiliser la fonction `calculerTotal()` avant l'export.",
            "flowchart TD",
            "    A[Réception du dossier] --> B{Complet ?}",
            "title: Rapport annuel",
            "- [ ] Valider les comptes avant le 30 juin",
            "| Poste | Montant | Écart |",
            "Le collecteur ![schéma](img/collecteur.png) a été refait.",
        ]
        await avecSession("fr", "de") { session in
            for e in essais {
                if let r = try? await session.translate(e) {
                    self.dire("  ORIG : \(e)")
                    self.dire("  TRAD : \(r.targetText)")
                    self.dire("")
                }
            }
        }
        dire()
    }

    // 5. L'attribut skipsTranslation (SDK 26.4) : peut-on protéger une plage ?
    func epreuve5SautTraduction() async {
        dire("=== 5. skipsTranslation SUR ATTRIBUTEDSTRING (fr → de) ===")
        await avecSession("fr", "de") { session in
            var a = AttributedString("Le chapitre ")
            var cible = AttributedString("[[Rapport annuel 2026]]")
            cible.skipsTranslation = true
            var fin = AttributedString(" décrit la méthode de calcul.")
            fin.skipsTranslation = false
            a.append(cible)
            a.append(fin)
            do {
                let r = try await session.translate(a)
                self.dire("  ORIG : \(String(a.characters))")
                self.dire("  TRAD : \(r.targetText)")
                if let at = r.attributedTargetText {
                    self.dire("  attributs conservés dans la réponse : \(at.runs.count) segments")
                    for run in at.runs {
                        self.dire("    « \(String(at[run.range].characters)) »  skips=\(String(describing: run.skipsTranslation))")
                    }
                }
                self.dire(r.targetText.contains("[[Rapport annuel 2026]]")
                          ? "  → la cible du wiki-lien est INTACTE."
                          : "  → la cible du wiki-lien a été ALTÉRÉE.")
            } catch {
                self.dire("  ERREUR : \(error)")
            }
        }
        dire()
    }

    // 6. Débit : un rapport entier, c'est combien de secondes ?
    func epreuve6Debit() async {
        dire("=== 6. DÉBIT (fr → de) ===")
        // Un document réaliste : les blocs répétés jusqu'à ~40 000 caractères.
        var gros: [String] = []
        var total = 0
        var i = 0
        let cible = ProcessInfo.processInfo.environment["BENCH_DEBIT"].flatMap(Int.init) ?? 40000
        while total < cible {
            let b = BLOCS[i % BLOCS.count]
            gros.append(b)
            total += b.count
            i += 1
        }
        dire("  \(gros.count) blocs, \(total) caractères")
        await avecSession("fr", "de") { session in
            let requetes = gros.enumerated().map {
                TranslationSession.Request(sourceText: $0.element, clientIdentifier: "g\($0.offset)")
            }
            let t0 = Date()
            var n = 0
            var jalons: [(Int, TimeInterval)] = []
            do {
                for try await _ in session.translate(batch: requetes) {
                    n += 1
                    if n % 20 == 0 || n == 1 { jalons.append((n, Date().timeIntervalSince(t0))) }
                }
            } catch {
                self.dire("  ERREUR : \(error)")
            }
            let dt = Date().timeIntervalSince(t0)
            for (k, t) in jalons { self.dire(String(format: "   bloc %3d à %6.3f s", k, t)) }
            self.dire(String(format: "  → %d blocs en %.3f s, soit %.0f caractères/s", n, dt, Double(total) / dt))
        }
        dire()
    }

    // 9. LA question qui décide de l'architecture. Un bloc Markdown n'est pas du texte
    //    plat : il porte du gras, des liens, du code. Si les attributs d'une plage
    //    survivent à la traduction ET restent alignés sur le texte correspondant, on peut
    //    traduire un bloc entier — le contexte de phrase est gardé, la mise en forme se
    //    replace toute seule. Sinon il faut traduire chaque nœud de texte isolément, et
    //    le modèle perd le contexte au moment même où il en a le plus besoin.
    func epreuve9Attributs() async {
        dire("=== 9. CONSERVATION DES ATTRIBUTS À TRAVERS LA TRADUCTION (fr → de) ===")
        await avecSession("fr", "de") { session in
            // a) attribut standard de Foundation : le gras d'un Markdown rendu.
            var a = AttributedString("Le conseil a validé ")
            var gras = AttributedString("les comptes annuels")
            gras.inlinePresentationIntent = .stronglyEmphasized
            var suite = AttributedString(" avant le 30 juin, sans réserve.")
            a.append(gras); a.append(suite)
            self.dire("a) gras (inlinePresentationIntent) sur « les comptes annuels »")
            await self.montrerRuns(session, a)

            // b) le même bloc avec en plus une portion protégée : gras ET skipsTranslation
            //    dans la même chaîne, c'est le cas réel d'un paragraphe avec du code inline.
            var b = AttributedString("Appeler ")
            var code = AttributedString("calculerTotal()")
            code.skipsTranslation = true
            var milieu = AttributedString(" puis vérifier ")
            var gras2 = AttributedString("le solde final")
            gras2.inlinePresentationIntent = .stronglyEmphasized
            var fin = AttributedString(" avant de clore l'exercice.")
            b.append(code); b.append(milieu); b.append(gras2); b.append(fin)
            self.dire("b) code protégé + gras dans le même bloc")
            await self.montrerRuns(session, b)

            // c) trois plages marquées d'un lien : l'ordre des runs suit-il le texte ?
            var c = AttributedString("Le rapport, la carte et les annexes sont publiés.")
            if let r = c.range(of: "la carte") {
                c[r].link = URL(string: "https://ok-ia.ch/carte")
            }
            self.dire("c) lien sur « la carte » au milieu de la phrase")
            await self.montrerRuns(session, c)
        }
        dire()
    }

    // Affiche la découpe en segments de la réponse : c'est elle qui dit si l'on peut
    // recoller la mise en forme sur le texte traduit.
    func montrerRuns(_ session: TranslationSession, _ source: AttributedString) async {
        do {
            let r = try await session.translate(source)
            self.dire("   ORIG : \(String(source.characters))")
            self.dire("   TRAD : \(r.targetText)")
            guard let at = r.attributedTargetText else {
                self.dire("   → PAS d'attributedTargetText : le recollage est impossible.")
                return
            }
            self.dire("   \(at.runs.count) segments en sortie (\(source.runs.count) en entrée) :")
            for run in at.runs {
                var marques: [String] = []
                if let i = run.inlinePresentationIntent, i.contains(.stronglyEmphasized) { marques.append("gras") }
                if run.skipsTranslation == true { marques.append("protégé") }
                if let l = run.link { marques.append("lien=\(l.absoluteString)") }
                self.dire("     « \(String(at[run.range].characters)) »  \(marques.isEmpty ? "—" : marques.joined(separator: " "))")
            }
        } catch {
            self.dire("   ERREUR : \(error)")
        }
        self.dire("")
    }

    // 8. Une paire NON installée : c'est le seul cas où l'invite système peut tomber.
    //    fr → ja n'est pas une paire de l'app ; elle sert de témoin.
    func epreuve8LangueAbsente() async {
        dire("=== 8. LANGUE NON INSTALLÉE (fr → ja, témoin de l'invite) ===")
        let dispo = LanguageAvailability()
        let s = await dispo.status(from: Locale.Language(identifier: "fr"),
                                   to: Locale.Language(identifier: "ja"))
        dire("  statut préalable : \(s)")
        await avecSession("fr", "ja") { session in
            self.dire("  session créée — canRequestDownloads = \(session.canRequestDownloads)")
            let pret = await session.isReady
            self.dire("  isReady AVANT = \(pret)")
            self.dire("  → appel de prepareTranslation() ; noter si une invite s'affiche MAINTENANT")
            let t0 = Date()
            do {
                try await session.prepareTranslation()
                self.dire(String(format: "  prepareTranslation() rendu en %.2f s, sans erreur", Date().timeIntervalSince(t0)))
            } catch {
                self.dire("  prepareTranslation() ERREUR : \(error)")
            }
            let pret2 = await session.isReady
            self.dire("  isReady APRÈS = \(pret2)")
            let t1 = Date()
            do {
                let r = try await session.translate("Le conseil communal a validé les comptes.")
                self.dire(String(format: "  traduction en %.2f s : %@", Date().timeIntervalSince(t1), r.targetText))
            } catch {
                self.dire("  traduction ERREUR : \(error)")
            }
        }
        dire()
    }

    // 7. Les paires réellement utiles : chacune traduit-elle ?
    func epreuve7Paires() async {
        dire("=== 7. TRADUCTION EFFECTIVE SUR LES PAIRES ===")
        let phrase = "Le conseil communal a validé les comptes de l'exercice écoulé."
        let phrases = ["fr": phrase,
                       "en": "The municipal council approved the accounts for the past financial year.",
                       "de": "Der Gemeinderat hat die Rechnung des vergangenen Jahres genehmigt.",
                       "es": "El consejo municipal aprobó las cuentas del ejercicio anterior.",
                       "it": "Il consiglio comunale ha approvato i conti dell'esercizio precedente."]
        for de in LANGUES {
            for vers in LANGUES where vers != de {
                await avecSession(de, vers) { session in
                    let t0 = Date()
                    do {
                        let r = try await session.translate(phrases[de]!)
                        self.dire(String(format: "  %@→%@  %5.2f s  %@", de, vers,
                                         Date().timeIntervalSince(t0), r.targetText))
                    } catch {
                        self.dire("  \(de)→\(vers)  ÉCHEC : \(error)")
                    }
                }
            }
        }
        dire()
    }
}

struct VueBanc: View {
    @StateObject private var banc = Banc()
    @State private var lance = false

    var body: some View {
        VStack {
            Text("Banc d'essai Translation")
                .font(.headline)
            Text("Les résultats s'écrivent sur la sortie standard.")
                .font(.caption)
        }
        .padding()
        .translationTask(banc.config) { session in
            await banc.executer(session)
        }
        .task {
            guard !lance else { return }
            lance = true
            await banc.toutFaire()
        }
    }
}

@main
struct BancApp: App {
    var body: some Scene {
        WindowGroup { VueBanc() }
    }
}
