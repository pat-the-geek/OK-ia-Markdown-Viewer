// Banc de la détection d'entités de l'option Analytic (1.4), hors de l'app : la même suite que
// `AnalyseEntites.analyser` (rapport fornews, NLTagger + FiltreEntitesNER, mentions, formes courtes),
// sans l'interface ni Wikidata. Né le 25/10/2026 : Patrick ne voyait ni Donald Trump ni Elon Musk —
// une personne fondue dans « Maison Blanche de Donald Trump », et des doublons qui perdaient des lignes.
//
// Usage : tools/BancEntites/banc.sh fichier.md…   (CHERCHE=trump,musk ; TOUT=1 : toute la liste)
// ⚠️ À garder aligné sur `AnalyseEntites.analyser` quand celle-ci change.
import Foundation
let fornewsUserAgent = "banc"
for chemin in CommandLine.arguments.dropFirst() {
    let texte = (try? String(contentsOfFile: chemin, encoding: .utf8)) ?? ""
    let sem = DispatchSemaphore(value: 0)
    Task {
        let langue = TexteAnalysable.langue(texte) ?? "fr"
        let duRapport = LecteurRapportFornews.lire(texte)
        // FORCE=majuscules : le dernier recours seul, celui d'un appareil sans modèle de noms.
        let (detectees, methode): ([EntiteDocument], DetecteurEntites.Methode)
        if ProcessInfo.processInfo.environment["FORCE"] == "majuscules" {
            let t = TexteAnalysable.depuis(texte)
            detectees = FiltreEntitesNER.filtrer(DetecteurEntites.parMajuscules(t), texteSource: t)
                .map { EntiteDocument(nom: $0.valeur, type: $0.type, origine: .detection) }
            methode = .majuscules
        } else {
            (detectees, methode) = await DetecteurEntites.detecter(texte, langue: langue)
        }
        var toutes = LecteurRapportFornews.dedoublonner(duRapport + detectees)
        DetecteurEntites.compterMentions(&toutes, dans: texte)
        toutes = DetecteurEntites.absorberFormesCourtes(toutes)
        let finales = toutes.filter { $0.mentions > 0 || $0.origine == .rapport }
        let cherche = (ProcessInfo.processInfo.environment["CHERCHE"] ?? "trump,musk")
            .split(separator: ",").map { String($0).lowercased() }
        print("—", (chemin as NSString).lastPathComponent, "[\(methode.rawValue)]", "langue", langue, "| texte", texte.count, "car. | prose", TexteAnalysable.depuis(texte).count, "car. | rapport", duRapport.count, "| détectées", detectees.count, "| finales", finales.count)
        for c in cherche {
            let dansTexte = texte.lowercased().components(separatedBy: c).count - 1
            print("   ", c, ": texte", dansTexte, "| rapport", duRapport.filter { $0.id.contains(c) }.map(\.nom),
                  "| détection", detectees.filter { $0.id.contains(c) }.map { "\($0.nom)/\($0.type.rawValue)" },
                  "| finales", finales.filter { $0.id.contains(c) }.map { "\($0.nom)=\($0.mentions)" })
        }
        if ProcessInfo.processInfo.environment["TOUT"] != nil {
            print("   finales :", finales.sorted { $0.mentions > $1.mentions }.map { "\($0.nom)/\($0.type.rawValue)=\($0.mentions)" }.joined(separator: " · "))
        }
        sem.signal()
    }
    sem.wait()
}
