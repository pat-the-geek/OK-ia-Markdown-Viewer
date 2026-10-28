// ─────────────────────────────────────────────────────────────────────────────────────────────
// Copie de fornews.ai — FornewsCore/Sources/FornewsServices/Flux/ImageMarkdown.swift (commit fda62384, 28/10/2026).
// Option Analytic (1.4) : le même algorithme que fornews. ⛔ Ne pas modifier ici : corriger dans
// fornews, puis relancer scripts/copier-fornews.sh.
// Seule retouche : les `import Fornews…` retirés.
// ─────────────────────────────────────────────────────────────────────────────────────────────

import Foundation

/// **La règle d'image des documents Markdown** — une seule, pour tous les producteurs.
///
/// ## Pourquoi ce fichier existe
///
/// La règle vivait dans `RapportHistoire` (rapport d'histoire, dossier d'entité) et son
/// dédoublonnage dans `CleImage`, tous deux dans `FornewsFeatures`. Le générateur de dossiers
/// (`ServiceRapports`, dans `FornewsPipeline`) ne peut pas les atteindre — la dépendance va dans
/// l'autre sens.
///
/// ⚠️ La tentation était d'en réécrire une copie. C'est exactement ce que l'en-tête de
/// `DossierEntite` interdit : deux formateurs se ressemblent le premier mois, puis divergent sur
/// un détail à la première correction — et le lecteur voit deux qualités de document dans la même
/// app. La règle descend donc d'un étage, et les deux appelants s'y branchent.
public enum ImageMarkdown {

    /// Une URL d'image **utilisable dans un `.md`**, y compris par md Viewer : `http(s)` seulement.
    ///
    /// ⚠️ Un `data:` ou un chemin local rendrait un cadre vide chez le lecteur — pire qu'une
    /// absence d'image, parce que ça ressemble à une panne.
    public static func affichable(_ url: String?) -> String? {
        guard let u = url?.trimmingCharacters(in: .whitespacesAndNewlines), !u.isEmpty,
              let comps = URLComponents(string: u), let scheme = comps.scheme?.lowercased(),
              scheme == "http" || scheme == "https", comps.host?.isEmpty == false else { return nil }
        // Les parenthèses et les espaces casseraient la syntaxe `![](url)`.
        return u.contains(")") || u.contains(" ") ? nil : u
    }

    /// Clé de dédoublonnage : hôte + chemin, sans la requête.
    ///
    /// 🔑 Deux CDN rendent la même photo sous deux URL qui ne diffèrent que par `?w=800` ou un
    /// jeton de signature. Sans cette clé, la même image apparaît deux fois en trois écrans.
    public static func cle(_ url: String) -> String {
        let brut = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let c = URLComponents(string: brut), let hote = c.host else { return brut.lowercased() }
        let chemin = c.path.hasSuffix("/") ? String(c.path.dropLast()) : c.path
        return (hote + chemin).lowercased()
    }
}
