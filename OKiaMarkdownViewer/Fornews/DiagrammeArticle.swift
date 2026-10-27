// ─────────────────────────────────────────────────────────────────────────────────────────────
// Copie de fornews.ai — FornewsCore/Sources/FornewsFeatures/Explorer/PartageArticleIAView.swift (commit b2d8c521, 26/10/2026).
// Option Analytic (1.4) : le même algorithme que fornews. ⛔ Ne pas modifier ici : corriger dans
// fornews, puis relancer scripts/copier-fornews.sh.
// EXTRAIT : `genererDiagramme` seul, le schéma Mermaid d'un article écrit par le modèle de l'appareil ;
// sorti de la vue dans une énumération (`private func` → `static func`).
// ─────────────────────────────────────────────────────────────────────────────────────────────

import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

enum DiagrammeArticle {
    /// Génère un diagramme Mermaid **sémantique** via Foundation Models (relations entre les éléments
    /// clés). `nil` si Apple Intelligence indisponible / échec / délai.
    static func genererDiagramme(titre: String, texte: String, entites: [String], langue: String) async -> String? {
        #if canImport(FoundationModels) && !os(tvOS)
        guard DisponibiliteAppleIntelligence().messageIndisponibilite == nil else { return nil }
        let moteur = MoteurFM(instructions: """
            Tu produis UNIQUEMENT du code Mermaid valide, sans aucun texte autour ni barrières ```.
            """)
        // ⭐ Accents permis dans les libellés (04/10/2026, la fiche montre le schéma en figure : « Geometrie des
        // coquilles d'oeufs » ne se lit pas). La validation ne les touche pas : `flowchartPropre` et
        // `mindmapPropre` réécrivent identifiants et guillemets, et Mermaid lit l'Unicode.
        let prompt = """
            Choisis le type de diagramme Mermaid le PLUS pertinent pour CET article, parmi cette liste \
            fermée, puis génère-le UNIQUEMENT d'après le contenu (n'invente rien) :
            - timeline : article chronologique / « en direct » / suite d'événements datés
            - sequenceDiagram : échanges ou réactions entre 2 acteurs/organisations ou plus
            - mindmap : article thématique (un sujet central et ses sous-thèmes)
            - pie : répartitions chiffrées / pourcentages
            - flowchart : causes → conséquences, ou relations entre éléments clés (choix par défaut)

            Règles STRICTES de sortie (libellés rédigés en \(LangueHelper.nomCible(langue)), accents permis, \
            AUCUNE barrière ```, aucun texte autour) :
            - Première ligne EXACTEMENT le mot-clé du type choisi (« flowchart TD », « timeline », \
            « sequenceDiagram », « mindmap », ou « pie title ... »).
            - flowchart : nœuds A["Libelle"], relations A -->|relation courte| B ; 5 à 9 nœuds ; \
            aucune parenthèse ni caractère spécial dans les libellés.
            - timeline : lignes « Periode : evenement » (au moins 3).
            - sequenceDiagram : lignes « Acteur->>Autre: message court » (au moins 3).
            - mindmap : racine « root((Sujet)) » puis sous-thèmes indentés (au moins 4).
            - pie : lignes « "Libelle" : nombre » (au moins 3).
            - Réponds avec le code Mermaid SEUL (pas de ```, pas d'explication).

            Titre : \(titre)
            Entités : \(entites.prefix(12).joined(separator: ", "))

            Contenu :
            \(String(texte.prefix(4000)))
            """
        do {
            let contenu = try await avecDelaiMaxFond(90) { try await moteur.repondre(prompt) }
            let t = contenu.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        } catch { return nil }
        #else
        return nil
        #endif
    }
}
