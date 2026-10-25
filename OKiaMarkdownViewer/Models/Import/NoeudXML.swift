import Foundation

/// Option Analytic (1.4) — un arbre XML minimal, pour lire les parties d'un `.docx` ou d'un `.pptx`.
/// Les noms gardent leur préfixe (`w:p`, `a:t`, `p:sp`) : les espaces de noms d'Office sont
/// toujours écrits avec les mêmes préfixes, et c'est sous cette forme qu'on les connaît.
final class NoeudXML {
    let nom: String
    let attributs: [String: String]
    private(set) var enfants: [NoeudXML] = []
    /// Le texte porté directement par l'élément (celui de `w:t`, `a:t`).
    fileprivate(set) var texte = ""

    init(nom: String, attributs: [String: String]) {
        self.nom = nom
        self.attributs = attributs
    }

    fileprivate func ajouter(_ n: NoeudXML) { enfants.append(n) }

    subscript(attribut: String) -> String? { attributs[attribut] }

    /// Le premier enfant direct de ce nom.
    func enfant(_ nom: String) -> NoeudXML? { enfants.first { $0.nom == nom } }

    func enfants(_ nom: String) -> [NoeudXML] { enfants.filter { $0.nom == nom } }

    /// Le premier descendant de ce nom, en profondeur d'abord.
    func descendant(_ nom: String) -> NoeudXML? {
        for e in enfants {
            if e.nom == nom { return e }
            if let d = e.descendant(nom) { return d }
        }
        return nil
    }

    /// Tous les descendants de ce nom, dans l'ordre du document.
    func descendants(_ nom: String) -> [NoeudXML] {
        var r: [NoeudXML] = []
        for e in enfants {
            if e.nom == nom { r.append(e) }
            r += e.descendants(nom)
        }
        return r
    }

    /// L'arbre d'un document XML ; nil s'il est illisible.
    static func lire(_ donnees: Data) -> NoeudXML? {
        let constructeur = Constructeur()
        let p = XMLParser(data: donnees)
        p.delegate = constructeur
        p.shouldProcessNamespaces = false
        guard p.parse() else { return nil }
        return constructeur.racine
    }

    static func lire(_ texte: String) -> NoeudXML? { lire(Data(texte.utf8)) }

    private final class Constructeur: NSObject, XMLParserDelegate {
        var racine: NoeudXML?
        private var pile: [NoeudXML] = []

        func parser(_ parser: XMLParser, didStartElement nom: String, namespaceURI: String?,
                    qualifiedName: String?, attributes: [String: String] = [:]) {
            let n = NoeudXML(nom: nom, attributs: attributes)
            if let parent = pile.last { parent.ajouter(n) } else { racine = n }
            pile.append(n)
        }

        func parser(_ parser: XMLParser, didEndElement nom: String, namespaceURI: String?, qualifiedName: String?) {
            _ = pile.popLast()
        }

        func parser(_ parser: XMLParser, foundCharacters chaine: String) {
            pile.last?.texte += chaine
        }
    }
}
