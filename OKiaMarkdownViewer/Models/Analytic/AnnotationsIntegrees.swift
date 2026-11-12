import Foundation

// Les annotations inscrites dans le document lui-même (1.5.1 ; Patrick, 12/11/2026 : « Penses-tu
// qu'il est possible de stocker les annotations dans le document ? Sur le modèle des images ? »,
// puis « Partout si possible »).
//
// Un commentaire HTML à la fin du fichier, comme les notes de l'orateur : invisible au rendu, gardé
// par tout éditeur Markdown, et hors de l'empreinte du document (`IdentiteDocument.sansMarques`) —
// l'écrire ne change pas la clé de ses annotations. Le lecteur le retire du texte dès la lecture
// (`MarkdownLoader`) : ni le rendu, ni le diaporama, ni l'analyse ne le voient.
//
// Le stockage d'Application Support reste : c'est lui que lisent la liste de toutes les annotations,
// la marque « annoté » et la synchro iCloud ; et c'est le seul pour un fichier où l'app ne peut pas
// écrire (une pièce jointe, un Word ou un PDF converti, un partage endormi). Entre les deux, le plus
// récent l'emporte (`AnnotationsStore.lire`).

enum AnnotationsIntegrees {
    struct Bloc: Codable, Equatable {
        var version = 1
        /// Quand le bloc a été écrit. Comparé à la dernière écriture du stockage local : le plus
        /// récent des deux sait ce qui a été ajouté et effacé depuis.
        var ecrit: Date
        var annotations: [Annotation]
    }

    static let entete = "<!-- md-viewer-annotations"
    /// Le bloc, avec les blancs qui le précèdent : le retirer rend le texte d'avant.
    private static let motif = #"\s*<!-- md-viewer-annotations\n([\s\S]*?)\n-->[ \t]*"#
    private static let expression = try? NSRegularExpression(pattern: motif)

    /// Le texte sans son bloc, et le bloc (nil s'il n'y en a pas, ou s'il ne se lit pas).
    static func separer(_ texte: String) -> (texte: String, bloc: Bloc?) {
        guard texte.contains(entete), let re = expression else { return (texte, nil) }
        let tout = NSRange(texte.startIndex..., in: texte)
        var bloc: Bloc?
        if let m = re.firstMatch(in: texte, range: tout), let json = Range(m.range(at: 1), in: texte) {
            bloc = try? JSONDecoder().decode(Bloc.self, from: Data(texte[json].utf8))
        }
        return (re.stringByReplacingMatches(in: texte, range: tout, withTemplate: ""), bloc)
    }

    /// Le texte sans son bloc.
    static func sans(_ texte: String) -> String { separer(texte).texte }

    /// Le bloc tel qu'il est écrit dans le texte, sans les blancs qui le précèdent.
    private static func brut(_ texte: String) -> String? {
        guard texte.contains(entete), let re = expression,
              let m = re.firstMatch(in: texte, range: NSRange(texte.startIndex..., in: texte)),
              let r = Range(m.range, in: texte) else { return nil }
        return texte[r].trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// `texte` suivi du bloc, séparé par une ligne vide.
    private static func joindre(_ texte: String, _ bloc: String) -> String {
        texte + (texte.isEmpty || texte.hasSuffix("\n") ? "" : "\n") + "\n" + bloc + "\n"
    }

    /// Le bloc qui porte `annotations`. Sans le tracé PencilKit, que rien ne relit encore : l'image
    /// de la note suffit à l'afficher, et le fichier reste léger. Les « -- » du JSON s'écrivent
    /// « -- » : un commentaire HTML ne doit pas en contenir, et le JSON les relit pareil.
    static func texteDuBloc(_ bloc: Bloc) -> String? {
        let enc = JSONEncoder()
        enc.outputFormatting = [.withoutEscapingSlashes]
        guard let d = try? enc.encode(bloc), let json = String(data: d, encoding: .utf8) else { return nil }
        return entete + "\n" + json.replacingOccurrences(of: "--", with: "-\\u002d") + "\n-->"
    }

    static func bloc(_ annotations: [Annotation], ecrit: Date = Date()) -> Bloc {
        Bloc(ecrit: ecrit, annotations: annotations.map { a in var a = a; a.trace = nil; return a })
    }

    /// `texte` (sans bloc) avec ces annotations à la fin — pour partager le Markdown annoté.
    static func avec(_ texte: String, annotations: [Annotation]) -> String {
        guard !annotations.isEmpty, let b = texteDuBloc(bloc(annotations)) else { return texte }
        return joindre(texte, b)
    }

    /// `texte` — un fichier entier que l'app réécrit (une note de l'orateur, une diapositive
    /// masquée), donc sans bloc — avec le bloc que le fichier a déjà, pour ne pas le perdre.
    static func reporter(_ texte: String, depuis url: URL) -> String {
        guard let d = try? Data(contentsOf: url), let actuel = String(data: d, encoding: .utf8),
              let b = brut(actuel) else { return texte }
        return joindre(sans(texte), b)
    }

    /// Une écriture à la fois, dans l'ordre.
    private static let file = DispatchQueue(label: "ch.ok-ia.annotations-integrees", qos: .utility)

    /// Inscrit les annotations dans le fichier du document, si l'app peut y écrire — hors du fil
    /// principal (le fichier est souvent dans iCloud Drive ou sur un partage). Rien n'est écrit si le
    /// fichier a changé depuis l'ouverture : ce n'est plus le document annoté. `ecrit` est la date de
    /// l'écriture locale qui va avec.
    @MainActor
    static func inscrire(_ annotations: [Annotation], document d: MarkdownDocument, ecrit: Date) {
        guard NotesOrateur.modifiable(d), let u = d.sourceURL else { return }
        let cle = IdentiteDocument(d).cle
        let nouveau = bloc(annotations, ecrit: ecrit)
        guard let texteBloc = texteDuBloc(nouveau) else { return }
        let racine = VaultStore.partage.resolveFolder()
        file.async {
            let fichier = u.startAccessingSecurityScopedResource()
            let coffre = racine.flatMap { r in
                u.standardizedFileURL.path.hasPrefix(r.standardizedFileURL.path + "/") && r.startAccessingSecurityScopedResource() ? r : nil
            }
            defer {
                if fichier { u.stopAccessingSecurityScopedResource() }
                coffre?.stopAccessingSecurityScopedResource()
            }
            var erreur: NSError?
            NSFileCoordinator().coordinate(writingItemAt: u, options: .forReplacing, error: &erreur) { cible in
                // Un fichier qui ne se lit pas en UTF-8 garde son encodage : on n'y touche pas.
                guard let donnees = try? Data(contentsOf: cible), let texte = String(data: donnees, encoding: .utf8),
                      IdentiteDocument.cle(fichier: u, octets: donnees) == cle else { return }
                let (reste, ancien) = separer(texte)
                if ancien == nil && annotations.isEmpty { return }
                if let ancien, ancien.annotations == nouveau.annotations { return }
                let ecrit = annotations.isEmpty ? reste : joindre(reste, texteBloc)
                try? ecrit.write(to: cible, atomically: true, encoding: .utf8)
            }
        }
    }
}
