import SwiftUI

/// Convertir le rapport ouvert en présentation (1.3) : on choisit le nombre de diapositives, le
/// modèle de l'appareil écrit, l'app assemble et vérifie, et le résultat s'ouvre au diaporama.
/// Le moteur est `ConvertisseurPresentation` ; cet écran ne fait que le piloter et le montrer.
struct PresentationConverterView: View {
    let document: MarkdownDocument
    let titreAffiche: String
    /// Reçoit la présentation à ouvrir au diaporama. Le lecteur l'ouvre une fois cette feuille
    /// refermée : deux présentations modales ne se chevauchent pas.
    var onPresenter: (MarkdownDocument) -> Void

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var loc = Localization.shared
    @StateObject private var conversion = ConversionEnCours()
    /// Un palier, ou 0 pour « Autre ».
    @State private var choix = 10
    @State private var libre = 12
    /// Calculé une fois : un rapport de plusieurs millions de caractères ne se redécoupe pas à
    /// chaque rafraîchissement de l'écran.
    @State private var maximum = 60

    private static let paliers = [5, 10, 15, 20, 25]
    private let orange = Color(red: 0xE8/255, green: 0x97/255, blue: 0x2E/255)

    private var demande: Int { min(choix == 0 ? libre : choix, maximum) }

    var body: some View {
        NavigationStack {
            Form {
                switch conversion.etat {
                case .reglage: reglage
                case .enCours(let etape, let total, let section): avancement(etape, total, section)
                case .fini(let r): resultat(r)
                case .echec(let message): echec(message)
                }
            }
            .navigationTitle(tr("Convertir en présentation"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr("Fermer")) { conversion.annuler(); dismiss() }
                }
            }
        }
        .tint(orange)
        .task {
            let md = document.text, nom = titreAffiche
            maximum = await Task.detached {
                PlanDiapositives.maximumUtile(RapportDecoupe(markdown: md, titreParDefaut: nom))
            }.value
        }
    }

    // MARK: Les quatre états

    @ViewBuilder private var reglage: some View {
        Section {
            Picker(tr("Nombre de diapositives"), selection: $choix) {
                ForEach(Self.paliers, id: \.self) { Text("\($0)").tag($0) }
                Text(tr("Autre")).tag(0)
            }
            .pickerStyle(.segmented)
            if choix == 0 {
                Stepper(tr("%d diapositives", libre), value: $libre, in: 5...max(5, maximum))
            }
        } header: {
            Text(tr("Nombre de diapositives"))
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                // Mesuré au banc : environ deux secondes et demie par diapositive.
                Text(tr("Environ %d secondes, calculées sur l’appareil.", Int(Double(demande) * 2.5) + 5))
                if (choix == 0 ? libre : choix) > maximum {
                    Text(tr("Ce rapport donne au plus %d diapositives : la conversion s’arrêtera là.", maximum))
                        .foregroundStyle(orange)
                }
            }
        }
        Section {
            Button {
                conversion.lancer(markdown: document.text, titre: titreAffiche, diapositives: demande)
            } label: {
                Label(tr("Convertir"), systemImage: "sparkles")
            }
        } footer: {
            Text(tr("Tout se calcule sur l’appareil, avec Apple Intelligence : le rapport ne quitte pas l’appareil."))
        }
    }

    private func avancement(_ etape: Int, _ total: Int, _ section: String) -> some View {
        Section {
            ProgressView(value: Double(max(etape - 1, 0)), total: Double(max(total, 1)))
            VStack(alignment: .leading, spacing: 4) {
                Text(tr("Étape %d sur %d", max(etape, 1), max(total, 1)))
                    .font(.subheadline.weight(.semibold))
                Text(section.isEmpty ? tr("Ouverture et conclusion") : section)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Button(tr("Annuler"), role: .cancel) { conversion.annuler() }
        }
    }

    @ViewBuilder private func resultat(_ r: ConversionEnCours.Fini) -> some View {
        Section {
            Label(tr("%d diapositives prêtes", r.diapositives), systemImage: "checkmark.circle")
            Button {
                onPresenter(r.document)
                dismiss()
            } label: {
                Label(tr("Lancer le diaporama"), systemImage: "play.rectangle")
            }
            if let url = r.document.sourceURL {
                ShareLink(item: url) {
                    Label(tr("Enregistrer le fichier .md"), systemImage: "square.and.arrow.down")
                }
            }
        }
        if !r.omissions.isEmpty {
            Section(tr("Laissé de côté")) {
                ForEach(r.omissions, id: \.self) { Text($0).font(.footnote) }
            }
        }
        if r.ecartees > 0 {
            Section {
                Text(tr("Puces écartées faute d’un chiffre présent dans le rapport : %d", r.ecartees))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        Section {
            Button(tr("Recommencer")) { conversion.reinitialiser() }
        }
    }

    private func echec(_ message: String) -> some View {
        Section {
            Text(message).foregroundStyle(.secondary)
            Button(tr("Réessayer")) {
                conversion.lancer(markdown: document.text, titre: titreAffiche, diapositives: demande)
            }
        }
    }
}

/// L'état de la conversion, tenu hors de la vue : la tâche survit aux rafraîchissements, et
/// l'avancement arrive d'un fil d'exécution qui n'est pas celui de l'interface.
@MainActor
final class ConversionEnCours: ObservableObject {
    struct Fini {
        let document: MarkdownDocument
        let diapositives: Int
        let omissions: [String]
        let ecartees: Int
    }

    enum Etat {
        case reglage
        case enCours(etape: Int, total: Int, section: String)
        case fini(Fini)
        case echec(String)
    }

    @Published private(set) var etat: Etat = .reglage
    private var tache: Task<Void, Never>?

    func lancer(markdown: String, titre: String, diapositives: Int) {
        tache?.cancel()
        etat = .enCours(etape: 0, total: 1, section: "")
        #if canImport(FoundationModels)
        // L'avancement arrive d'un autre fil : on le ramène sur celui de l'interface, sans jamais
        // retenir l'écran au-delà de sa fermeture.
        let suivi: @Sendable (ConvertisseurPresentation.Avancement) -> Void = { [weak self] a in
            guard let moi = self else { return }
            Task { @MainActor in moi.suivre(a) }
        }
        tache = Task { [weak self] in
            do {
                let r = try await ConvertisseurPresentation().convertir(
                    markdown: markdown, titreParDefaut: titre, diapositives: diapositives, avancement: suivi)
                let document = Self.enregistrer(r)
                self?.etat = .fini(Fini(document: document, diapositives: r.diapositives,
                                        omissions: r.omissions.map(Self.texte), ecartees: r.pucesEcartees.count))
            } catch is CancellationError {
                // Annulée par le lecteur : l'écran est déjà revenu au réglage.
            } catch ConvertisseurPresentation.Echec.modeleIndisponible {
                self?.etat = .echec(tr("Apple Intelligence n’est pas disponible sur cet appareil."))
            } catch ConvertisseurPresentation.Echec.rapportVide {
                self?.etat = .echec(tr("Ce document n’a pas de section à présenter."))
            } catch {
                self?.etat = .echec(tr("La conversion a échoué (%@).", error.localizedDescription))
            }
        }
        #else
        etat = .echec(tr("Apple Intelligence n’est pas disponible sur cet appareil."))
        #endif
    }

    /// Une annulation arrivée entre-temps l'emporte : l'avancement ne rouvre pas l'écran de travail.
    private func suivre(_ a: ConvertisseurPresentation.Avancement) {
        guard case .enCours = etat else { return }
        etat = .enCours(etape: a.etape, total: a.total, section: a.section)
    }

    func annuler() {
        tache?.cancel()
        tache = nil
        etat = .reglage
    }

    func reinitialiser() { etat = .reglage }

    #if canImport(FoundationModels)
    /// Ce qui a été laissé de côté, dit dans la langue de l'app. Ce que le modèle écrit d'une
    /// section reste, lui, dans la langue du rapport.
    private static func texte(_ o: ConvertisseurPresentation.Omission) -> String {
        switch o {
        case .sectionEntiere(let t):       return tr("%@ — toute la section, faute de place", t)
        case .partielle(let t, let manque): return "\(t) — \(manque)"
        case .nonConvertie(let t):         return tr("%@ — non convertie : le modèle l’a refusée", t)
        }
    }

    /// La présentation devient un vrai fichier, dans le dossier temporaire : le diaporama l'ouvre
    /// comme n'importe quel document, et « Enregistrer » le propose à l'app Fichiers.
    private static func enregistrer(_ r: ConvertisseurPresentation.Resultat) -> MarkdownDocument {
        let sur = r.titre.components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>\n")).joined(separator: " ")
        let nom = String(sur.prefix(80)).trimmingCharacters(in: .whitespaces) + " — " + tr("présentation") + ".md"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(nom)
        try? r.markdown.write(to: url, atomically: true, encoding: .utf8)
        return MarkdownDocument(filename: nom, text: r.markdown, sourceURL: url)
    }
    #endif
}
