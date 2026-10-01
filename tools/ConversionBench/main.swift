// Banc d'essai — convertir un rapport en présentation avec le modèle de l'appareil (1.3).
//
// Le banc compile le moteur de l'app tel quel : ce qu'il mesure est ce que l'app livrera.
//
//   swiftc -O OKiaMarkdownViewer/Models/PresentationConverter.swift tools/ConversionBench/main.swift \
//          -o build/conversion-bench
//   build/conversion-bench <rapport.md> <nombre de diapositives> [sortie.md]

import Foundation

let args = CommandLine.arguments
guard args.count >= 3, let demande = Int(args[2]) else {
    print("usage : conversion-bench <rapport.md> <nombre de diapositives> [sortie.md]"); exit(2)
}
let md = try String(contentsOfFile: args[1], encoding: .utf8)
let nom = URL(fileURLWithPath: args[1]).deletingPathExtension().lastPathComponent

let rapport = RapportDecoupe(markdown: md, titreParDefaut: nom)
let plan = PlanDiapositives.repartir(min(max(5, demande), PlanDiapositives.maximumUtile(rapport)), rapport)
print("── « \(rapport.titre) » — \(md.count) caractères, langue \(rapport.langue)")
print("   au plus \(PlanDiapositives.maximumUtile(rapport)) diapositives utiles")
for (s, n) in zip(rapport.contenu, plan.parSection) {
    print("   \(String(format: "%2d", n)) diapo. · \(String(format: "%6d", s.texte.count)) car. · \(s.blocs.count) visuel(s) · \(s.images.count) image(s) · \(s.titre)")
}
print("   fixes : ouverture \(plan.ouverture), plan \(plan.plan), à retenir \(plan.retenir), sources \(plan.sources)")

let horloge = ContinuousClock()
let debut = horloge.now
do {
    let r = try await ConvertisseurPresentation().convertir(markdown: md, titreParDefaut: nom, diapositives: demande) { a in
        print("   … \(a.etape)/\(a.total) \(a.section.isEmpty ? "ouverture et conclusion" : a.section) — \(a.diapositives.count)/\(a.prevues) prêtes")
    }
    let duree = horloge.now - debut
    if args.count >= 4 { try r.markdown.write(toFile: args[3], atomically: true, encoding: .utf8) }
    let separateurs = r.markdown.components(separatedBy: "\n").filter { $0 == "---" }.count
    print("── \(r.diapositives) diapositives pour \(r.demandees) demandées — \(separateurs + 1) dans le fichier")
    print("   durée : \(duree.formatted(.units(allowed: [.seconds], fractionalPart: .show(length: 1))))")
    print("   puces écartées faute d'un chiffre présent dans le rapport : \(r.pucesEcartees.count)")
    for p in r.pucesEcartees.prefix(6) { print("     ⚠️ \(p)") }
    print("   laissé de côté :")
    for o in r.omissions { print("     · \(o)") }
} catch {
    print("✗ \(error)"); exit(1)
}
