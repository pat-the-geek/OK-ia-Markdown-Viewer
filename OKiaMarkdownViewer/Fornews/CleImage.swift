// ─────────────────────────────────────────────────────────────────────────────────────────────
// Copie de fornews.ai — FornewsCore/Sources/FornewsFeatures/Components/CleImage.swift (commit fda62384, 28/10/2026).
// Option Analytic (1.4) : le même algorithme que fornews. ⛔ Ne pas modifier ici : corriger dans
// fornews, puis relancer scripts/copier-fornews.sh.
// Seule retouche : les `import Fornews…` retirés.
// ─────────────────────────────────────────────────────────────────────────────────────────────

import Foundation

/// **Clé d'identité d'une image**, pour ne jamais la montrer deux fois dans un même document.
///
/// ⚠️ Comparer les URL brutes ne suffit pas, et c'est ce qui laissait passer des doublons dans les
/// rapports md (signalé le 29/07). La même photo revient sous plusieurs adresses : paramètres de
/// redimensionnement du CDN (`?width=1200` puis `?width=640`), horodatage de cache, `http` contre
/// `https`, hôte en capitales. Trois `![]()` de la même image dans un rapport de dix écrans donnent
/// l'impression d'un document mal assemblé — exactement ce qu'un rapport doit éviter.
///
/// La clé retenue est **hôte + chemin**, en minuscules, sans requête ni fragment : deux images
/// réellement différentes ne partagent quasiment jamais ce couple, alors que les variantes d'une
/// même image ne diffèrent que par la requête.
enum CleImage {
    static func cle(_ url: String) -> String {
        // ⚠️ Règle DÉPLACÉE dans `ImageMarkdown` (FornewsServices) — même raison que
        // `RapportHistoire.imageAffichable` : le générateur de dossiers doit dédoublonner pareil.
        ImageMarkdown.cle(url)
    }

    /// Retire les doublons d'une liste d'URL d'images **en gardant la première occurrence** (et donc
    /// la variante que l'appelant a jugée la meilleure), et en écartant celles déjà montrées.
    static func dedupliquer(_ urls: [String], deja: inout Set<String>) -> [String] {
        urls.filter { deja.insert(cle($0)).inserted }
    }
}
