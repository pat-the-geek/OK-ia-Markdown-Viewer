// ─────────────────────────────────────────────────────────────────────────────────────────────
// Copie de fornews.ai — FornewsCore/Sources/FornewsModels/PatronymeLieu.swift (commit fda62384, 28/10/2026).
// Option Analytic (1.4) : le même algorithme que fornews. ⛔ Ne pas modifier ici : corriger dans
// fornews, puis relancer scripts/copier-fornews.sh.
// Seule retouche : les `import Fornews…` retirés.
// ─────────────────────────────────────────────────────────────────────────────────────────────

import Foundation

/// **Un lieu qui n'est en réalité que le patronyme d'une personne.**
///
/// Cas fondateur (retour Patrick, 21/07/2026) : un article sur « Gabriel Brenna », directeur général
/// de Raiffeisen Suisse, produisait une entité **« Brenna » de type `gpe`** — enrichie par Wikidata
/// en `Q244138`, « commune italienne de la province de Côme » — et donc **épinglée en Italie sur la
/// carte du monde**. Le détecteur d'entités étiquette les jetons indépendamment : sur un patronyme
/// rare, il hésite entre nom de personne et nom de lieu, et rien ne l'oblige à rester cohérent avec
/// le fait que « Gabriel Brenna » a été reconnu comme personne **dans la même phrase**.
/// L'enrichissement Wikidata vient ensuite *confirmer* l'erreur en trouvant un vrai lieu homonyme.
///
/// La règle vit **ici**, dans `FornewsModels`, pour être appliquée aux **deux bouts** — comme
/// [[PaireDePays]] et [[TermesGeneriquesNER]] :
/// 1. **à la création**, par `FiltreEntitesNER` (FornewsAI) ;
/// 2. **rétroactivement**, par `NettoyageEntites` (FornewsServices, qui ne peut pas dépendre de
///    FornewsAI) — sans quoi les entités créées AVANT le filtre restent sur la carte, ce qui a
///    précisément été constaté le 22/07 : « Brenna » toujours présente, liée à un article du 20/07.
public enum PatronymeLieu {

    /// Vrai si `valeurLieu` doit être écarté : c'est un jeton d'un des `nomsPersonnes` **et** il
    /// n'apparaît nulle part dans `texte` en dehors de ces noms complets.
    ///
    /// **Garde-fou anti-faux-positif** — c'est lui qui rend la règle sûre : « Washington » reste un
    /// lieu si l'article en parle vraiment, même s'il cite aussi « George Washington ». Sans texte
    /// source, on ne tranche pas (on garde) : mieux vaut une épingle douteuse qu'un lieu légitime
    /// supprimé.
    ///
    /// - Parameters:
    ///   - valeurLieu: valeur de l'entité `gpe`/`loc` candidate.
    ///   - nomsPersonnes: noms des personnes détectées **dans le même article**.
    ///   - texte: texte de l'article (titre + résumé + contenu suffisent).
    public static func estComposantDeNom(
        valeurLieu: String, nomsPersonnes: [String], texte: String?
    ) -> Bool {
        let lieu = normaliser(valeurLieu)
        // Un lieu en plusieurs mots n'est pas un patronyme isolé (« New York » ne se confond pas
        // avec le nom de famille d'une personne détectée).
        guard !lieu.isEmpty, !lieu.contains(" ") else { return false }

        // Seuls les noms COMPLETS (≥ 2 jetons) font foi : une personne détectée sous son seul
        // patronyme ne prouve rien — c'est justement le cas ambigu.
        let complets = nomsPersonnes
            .map(normaliser)
            .filter { $0.split(separator: " ").count >= 2 }
        let porteurs = complets.filter { $0.split(separator: " ").map(String.init).contains(lieu) }
        guard !porteurs.isEmpty else { return false }

        guard let texte, !texte.isEmpty else { return false }   // pas de texte → on ne tranche pas
        var reste = normaliser(texte)
        for nom in porteurs { reste = reste.replacingOccurrences(of: nom, with: " ") }
        // Subsiste-t-il comme mot isolé hors des noms complets ? Si oui, c'est un vrai lieu.
        return !" \(reste) ".contains(" \(lieu) ")
    }

    /// Minuscules, sans diacritiques, apostrophes unifiées, espaces compactés — cohérente avec
    /// `FiltreEntitesNER.normaliser`, `ListeNoireEntites.normaliser` et `KeywordMatcher.normalize`.
    public static func normaliser(_ s: String) -> String {
        s.replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{2018}", with: "'")
            .replacingOccurrences(of: "\u{02BC}", with: "'")
            .folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: nil)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
