import Foundation

/// **La boîte aux lettres partagée entre fornews.ai et md Viewer.**
///
/// ## Le défaut que ça corrige
///
/// Signalé par Patrick le 11/09 : « sur la 628, les markdown ne s'ouvrent pas directement dans md
/// Viewer… sur iOS en tout cas ». C'était exact et voulu — sur macOS `NSWorkspace` prend
/// l'application par son identifiant, mais **iOS n'a aucun moyen de remettre un fichier à une
/// application NOMMÉE**. Le bouton n'existait donc pas là où il servirait le plus.
///
/// ## Pourquoi un dossier partagé, et pas le contenu dans l'URL
///
/// md Viewer accepte `mdviewer://render?content=…`, ce qui n'aurait rien demandé à personne.
///
/// 🔑 **Mesuré avant d'être écarté**, sur les 24 rapports du Mac mini : le plus gros fait
/// **180 560 caractères** de Markdown, soit **272 037 caractères** une fois encodés dans une URL.
/// Une URL de cette taille n'est pas ouverte, et l'échec est SILENCIEUX — le pire des défauts.
/// Le dossier partagé n'a pas de limite de taille, et l'URL qui le désigne tient en quelques
/// dizaines de caractères.
///
/// ## Le groupe porte le nom de fornews, et c'est délibéré
///
/// ⚠️ `group.ai.fornews.native` existe déjà et est livré par fornews depuis longtemps. En créer un
/// neutre obligerait à modifier **les deux** applications et à republier les deux profils ; celui-ci
/// ne demande qu'une déclaration côté md Viewer. Le nom est bancal, le coût ne l'est pas.
///
/// ## Ce qui est déposé est JETABLE
///
/// ⛔ La boîte n'est pas un lieu d'archivage : le document de référence reste celui de Fichiers,
/// écrit par `FichierRapport`. Ici on ne dépose qu'une copie de passage, et `fairePlace` efface les
/// plus anciennes — sans quoi le conteneur partagé enflerait à chaque lecture, invisible dans
/// Réglages comme dans Fichiers.
public enum BoiteAuxLettres {

    public static let groupe = "group.ai.fornews.native"

    /// Sous-dossier de dépôt. Nom en clair : si quelqu'un l'inspecte un jour, il doit comprendre.
    static let sousDossier = "EnLecture"

    /// Au-delà, les fichiers les plus anciens sont effacés. Dix documents suffisent très largement
    /// à ce qu'on relit, et bornent le conteneur à quelques centaines de kilo-octets.
    static let plafond = 10

    public static var dossier: URL? {
        guard let racine = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: groupe) else { return nil }
        let d = racine.appendingPathComponent(sousDossier, isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    /// Dépose le Markdown et renvoie le **nom** du fichier — c'est lui qui voyage dans l'URL, jamais
    /// un chemin : un chemin de conteneur n'a pas le même préfixe d'une application à l'autre.
    public static func deposer(_ markdown: String, nom: String) -> String? {
        guard let d = dossier else { return nil }
        let propre = nomSur(nom)
        guard (try? Data(markdown.utf8).write(to: d.appendingPathComponent(propre),
                                              options: .atomic)) != nil else { return nil }
        fairePlace(dans: d, sauf: propre)
        return propre
    }

    /// Relit un dépôt. Rend `nil` si le nom ne désigne rien — ou s'il tente de sortir du dossier.
    public static func relire(_ nom: String) -> String? {
        guard let d = dossier else { return nil }
        let propre = nomSur(nom)
        guard !propre.isEmpty else { return nil }
        return try? String(contentsOf: d.appendingPathComponent(propre), encoding: .utf8)
    }

    /// ⛔ **Le nom vient d'une URL, donc de l'extérieur.** Sans cette réduction au dernier segment,
    /// `mdviewer://fichier?nom=../../Documents/quelquechose` lirait hors de la boîte. Un nom de
    /// fichier n'a jamais de barre oblique ; on n'en discute pas, on la retire.
    static func nomSur(_ nom: String) -> String {
        let dernier = nom.components(separatedBy: "/").last ?? ""
        return dernier == ".." || dernier == "." ? "" : dernier
    }

    /// Efface les dépôts au-delà du plafond, du plus ancien au plus récent.
    private static func fairePlace(dans d: URL, sauf garde: String) {
        let fm = FileManager.default
        guard let tous = try? fm.contentsOfDirectory(at: d,
                includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        let dates = tous.map { u -> (URL, Date) in
            let t = (try? u.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast
            return (u, t)
        }.sorted { $0.1 > $1.1 }
        for (u, _) in dates.dropFirst(plafond) where u.lastPathComponent != garde {
            try? fm.removeItem(at: u)
        }
    }
}
