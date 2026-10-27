import Foundation

/// Option Analytic (1.4) — la fiche de lecture d'une page web, à la manière de fornews : la même
/// composition (`RapportObsidian.generer` et `FicheArticle`, copiés mot pour mot), nourrie par ce
/// que md Viewer sait faire sur l'appareil — la détection d'entités et vos corrections, Wikidata
/// pour situer les lieux si vous l'avez accepté, Apple Intelligence pour le résumé et les chiffres.
///
/// ⛔ Aucun fait ajouté : le résumé, les chiffres et le schéma du modèle passent par les gardes de
/// fornews (`FicheArticle.resumeFidele`, `chiffresDepuisModele`, `validerDiagrammeIA`,
/// `schemaAncre`) ; à défaut, la fiche prend le chapeau de la page, les chiffres relevés par le code
/// et le schéma que fornews dessine sans le modèle (les noms cités, par genre).
enum FichePageWeb {

    /// La page en Markdown simple : le texte, sans analyse — sans l'option, ou en secours.
    static func texteSeul(_ p: PageWeb) -> (titre: String, markdown: String) {
        let titre = p.titre?.nonVide ?? p.url
        var md = MarkdownImport.entete(titre: titre, source: p.media?.nonVide ?? p.url, genre: "page")
        md += "\n\n# " + MarkdownImport.echapper(titre) + "\n\n" + corps(p).markdown
        md += "\n\n[\(MarkdownImport.echapper(p.media?.nonVide ?? p.url))](\(p.url))\n"
        return (titre, md)
    }

    /// Le corps de l'article en Markdown, et les illustrations à part (la fiche les intercale).
    static func corps(_ p: PageWeb) -> (markdown: String, images: [String]) {
        var lignes: [String] = []
        var liste: [String] = []
        var images: [String] = []
        func fermer() { if !liste.isEmpty { lignes.append(liste.joined(separator: "\n")); liste = [] } }
        for b in p.blocs ?? [] {
            let x = MarkdownImport.echapper(b.x)
            switch b.t {
            case "img": images.append(b.x)
            case "li":  liste.append("- " + x)
            case "h":   fermer(); lignes.append("### " + x)
            case "q":   fermer(); lignes.append("> " + x)
            default:    fermer(); lignes.append(MarkdownImport.debutDeLigne(x))
            }
        }
        fermer()
        return (lignes.joined(separator: "\n\n"), images)
    }

    /// La fiche complète. `langue` : celle de l'interface — les libellés, le résumé, et le texte,
    /// traduit par `traducteur` quand la page est écrite dans une autre langue.
    static func produire(_ p: PageWeb, langue: String, wikidata: Bool, traducteur: TraducteurPonctuel?,
                         suivi: SuiviImport?) async -> (titre: String, markdown: String) {
        let texteOriginal = (p.blocs ?? []).filter { $0.t != "img" }.map(\.x).joined(separator: "\n\n")
        let langueArticle = String((p.langue?.nonVide ?? MoteurRedaction.langue(texteOriginal)).prefix(2)).lowercased()
        let titreOriginal = p.titre?.nonVide ?? p.url
        let etapes = 6
        func etape(_ n: Int, _ quoi: String) async {
            await suivi?(AvancementImport(etape: tr("Fiche de lecture"), fait: n, total: etapes, dernier: quoi))
        }

        // 0. Le texte dans la langue de l'interface (Patrick, 26/10/2026) : le titre, le chapeau et
        //    chaque bloc, traduits sur l'appareil. Sans traduction possible, la fiche garde l'original.
        var page = p
        var traduit = false
        if langueArticle != String(langue.prefix(2)), let traducteur {
            await etape(0, tr("Traduction"))
            let blocs = p.blocs ?? []
            let textes = [titreOriginal, p.description ?? ""] + blocs.map { $0.t == "img" ? "" : $0.x }
            let aTraduire = textes.enumerated().filter { !$0.element.isEmpty }
            if let rendus = await traducteur.traduire(aTraduire.map(\.element), de: langueArticle, vers: String(langue.prefix(2)),
                                                      progression: { fait, total in
                                                          Task { await suivi?(AvancementImport(etape: tr("Traduction"), fait: fait,
                                                                                               total: total, dernier: nil)) }
                                                      }) {
                var t = textes
                for (k, (i, _)) in aTraduire.enumerated() { t[i] = rendus[k] }
                page.titre = t[0]
                if p.description != nil { page.description = t[1] }
                page.blocs = blocs.enumerated().map { i, b in b.t == "img" ? b : PageWeb.Bloc(t: b.t, x: t[i + 2]) }
                traduit = true
            }
        }
        let (corpsMD, images) = corps(page)
        let texte = (page.blocs ?? []).filter { $0.t != "img" }.map(\.x).joined(separator: "\n\n")
        let titre = page.titre?.nonVide ?? p.url

        // 1. Les entités : la détection de md Viewer sur le texte d'origine (les noms ne changent pas
        //    à la traduction, et la détection est meilleure dans la langue de l'article), vos corrections.
        await etape(1, tr("Entités"))
        var entites = await DetecteurEntites.detecter(texteOriginal, langue: langueArticle).entites
        DetecteurEntites.compterMentions(&entites, dans: texteOriginal)
        entites = DetecteurEntites.absorberFormesCourtes(entites).filter { $0.mentions > 0 }
        let detectees = entites
        entites = await MainActor.run { CorrectionsEntites.partage.appliquer(detectees) }
        entites.sort { $0.mentions > $1.mentions }

        // 2. Les lieux situés, pour la carte — seulement si Wikidata est accepté ; seuls les noms partent.
        var geo: [RapportObsidian.GeoPoint] = []
        if wikidata {
            await etape(2, tr("Lieux"))
            geo = await lieux(entites.filter { $0.type == .gpe || $0.type == .loc }.prefix(8).map { $0 }, langue: langueArticle)
        }

        // 3. Le résumé et les chiffres, par le modèle de l'appareil, sous les gardes de fornews.
        await etape(3, tr("Résumé"))
        let resume = await resumer(texte, langue: langue, langueArticle: traduit ? String(langue.prefix(2)) : langueArticle)
        await etape(4, tr("Chiffres"))
        let lots = await FicheArticle.chiffresIA(texte: texte, langue: langue)
        // Le schéma, comme fornews : le type choisi par le modèle (chronologie, échanges, thèmes,
        // répartition, causes et conséquences), écarté s'il est invalide ou s'il avance un nombre
        // absent du texte — le schéma des noms cités prend alors sa place.
        await etape(5, tr("Schéma"))
        let diagramme = await DiagrammeArticle.genererDiagramme(titre: titre, texte: texte,
                                                                 entites: entites.map(\.nom), langue: langue)
            .flatMap { RapportObsidian.validerDiagrammeIA($0) }
            .flatMap { FicheArticle.schemaAncre($0, texte: texte) }

        // 4. La composition de fornews.
        let d = RapportObsidian.DonneesRapport(
            titre: titre, source: p.media?.nonVide ?? URL(string: p.url)?.host ?? "", url: p.url,
            dateStr: dateISO(p.date), langueSource: langueArticle, imagePrincipale: p.image?.nonVide,
            resumeMd: page.description.map { "## En bref\n\n" + $0 } ?? "",
            entites: entites.map { RapportObsidian.EntiteRapport(nom: $0.nom, type: $0.type) },
            geo: geo, titreOriginal: traduit ? titreOriginal : nil, logoSource: p.logo?.nonVide,
            traduit: traduit, longueurContenuOriginal: texte.count)
        var md = RapportObsidian.generer(donnees: d, langue: langue, diagramme: diagramme, corpsComplet: corpsMD,
                                         imagesInline: images, pointsGeo: geo, carteDataURI: nil,
                                         resume: resume, lots: lots)
        // La signature est celle de md Viewer : c'est lui qui a composé cette fiche.
        let signature = AvertissementIA.signature(langue)
        md = md.replacingOccurrences(of: signature, with: signature.replacingOccurrences(of: "fornews.ai", with: "md Viewer"))
        return (titre, md)
    }

    /// « En bref » : trois phrases au plus, dans la langue de l'interface ; gardé seulement s'il est
    /// fidèle au texte (noms et nombres présents), sinon la fiche prend le chapeau de la page.
    private static func resumer(_ texte: String, langue: String, langueArticle: String) async -> String? {
        guard MoteurRedaction.disponible, texte.count > 400 else { return nil }
        let consigne = """
            Tu résumes un article, en \(ConsignesAnalyste.nomLangue(langue)), en trois phrases au plus : ce qui se passe, et pourquoi c'est important.
            ⛔ Tout nom propre, chiffre et date doit figurer dans l'article : n'en invente aucun.
            ⛔ Rends le résumé seul, sans titre ni liste.
            \(ConsignesAnalyste.styleSansTics)
            """ + ConsignesAnalyste.ordreDeLangue(langue)
        guard let r = await MoteurRedaction.rediger(consigne: consigne, matiere: texte, motsAttendus: 90) else { return nil }
        return FicheArticle.resumeFidele(r, source: texte, memeLangue: langue.prefix(2) == langueArticle.prefix(2),
                                         langue: langue) ? r : nil
    }

    /// Les lieux situés par Wikidata, au travers du cache de md Viewer.
    private static func lieux(_ liste: [EntiteDocument], langue: String) async -> [RapportObsidian.GeoPoint] {
        let resolveur = ResolveurWikidata()
        var r: [RapportObsidian.GeoPoint] = []
        for e in liste {
            var res = await MainActor.run { CacheEntites.partage.resolution(e.nom, type: e.type, langue: langue) }
            if res == nil, let lu = try? await resolveur.resoudre(e.nom, type: e.type, langue: langue) {
                await MainActor.run { CacheEntites.partage.retenir(lu, nom: e.nom, type: e.type, langue: langue) }
                res = lu
            }
            if let lat = res?.latitude, let lon = res?.longitude {
                r.append(RapportObsidian.GeoPoint(nom: e.nom, type: e.type, lat: lat, lon: lon))
            }
        }
        return r
    }

    /// La date de publication en `aaaa-mm-jj`, comme fornews l'attend.
    private static func dateISO(_ s: String?) -> String {
        guard let s, s.count >= 10, s.range(of: #"^\d{4}-\d{2}-\d{2}"#, options: .regularExpression) != nil else { return "" }
        return String(s.prefix(10))
    }
}

private extension String {
    var nonVide: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
