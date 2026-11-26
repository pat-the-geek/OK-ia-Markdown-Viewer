import SwiftUI

/// 1.6 — Ouvrir le coffre aux assistants par MCP (Mac, option Analytic) : l'interrupteur, l'adresse,
/// le jeton, la configuration prête à copier pour Claude Code, Claude Desktop, Codex et VS Code, et
/// ce que les assistants ont lu.
struct ServeurMCPView: View {
    @ObservedObject private var serveur = ServeurMCPCoffre.partage
    @ObservedObject private var loc = Localization.shared
    @AppStorage(ServeurMCPCoffre.cleReglage) private var ouvert = false
    @AppStorage(CoffreExplique.cleReglage) private var coffreExplique = false
    @State private var jetonVisible = false
    @State private var renouveler = false
    @State private var copie: String?
    private let orange = Color(red: 0xE8/255, green: 0x97/255, blue: 0x2E/255)

    var body: some View {
        Form {
            Section {
                Toggle(tr("Ouvrir le coffre aux assistants"), isOn: $ouvert)
                    .onChange(of: ouvert) { _, _ in serveur.appliquerReglage() }
                if ouvert {
                    LabeledContent(tr("État")) {
                        Text(serveur.actif ? tr("En service") : (serveur.erreur ?? tr("Démarrage…")))
                            .foregroundStyle(serveur.actif ? .green : .secondary)
                    }
                }
            } footer: {
                Text(tr("Claude, Codex, Copilot ou un autre assistant lisent votre coffre par MCP : chercher, lire un document, les entités. En lecture seule, sur ce Mac seulement, avec un jeton. md Viewer n’envoie rien ; c’est l’assistant que vous branchez qui lit, tant que md Viewer est ouvert."))
            }

            if ouvert {
                Section(tr("Adresse et jeton")) {
                    ligneCopiable(tr("Adresse"), serveur.url)
                    HStack {
                        Text(tr("Jeton"))
                        Spacer()
                        Text(jetonVisible ? serveur.jeton : "mdv_••••••")
                            .font(.callout.monospaced())
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                        Button { jetonVisible.toggle() } label: {
                            Image(systemName: jetonVisible ? "eye.slash" : "eye")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(jetonVisible ? tr("Masquer le jeton") : tr("Afficher le jeton"))
                        boutonCopier(serveur.jeton)
                    }
                    Button(tr("Renouveler le jeton…"), role: .destructive) { renouveler = true }
                }

                Section {
                    ligneCopiable("Claude Code", commandeClaude, monospace: true)
                    ligneCopiable("Codex", commandeCodex, monospace: true)
                    ligneCopiable("Claude Desktop, VS Code", configurationJSON, monospace: true)
                } header: {
                    Text(tr("Brancher un assistant"))
                } footer: {
                    Text(tr("Copiez la ligne de votre assistant : elle porte l’adresse et le jeton. ChatGPT, qui demande une adresse publique sur Internet, ne peut pas se brancher sur ce Mac."))
                }

                if !coffreExplique {
                    Section {
                        Toggle(tr("Expliquer le coffre aux assistants"), isOn: $coffreExplique)
                            .onChange(of: coffreExplique) { _, actif in if actif { CoffreExplique.mettreAJour() } }
                    } footer: {
                        Text(tr("Ajoute aussi au coffre un fichier AGENTS.md et un index : utile quand un assistant ouvre le dossier lui-même."))
                    }
                }

                Section {
                    if serveur.journal.isEmpty {
                        Text(tr("Aucun assistant n’a encore lu le coffre.")).foregroundStyle(.secondary)
                    }
                    ForEach(serveur.journal.prefix(100)) { l in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(l.outil.replacingOccurrences(of: "mdviewer_", with: ""))
                                    .font(.callout.monospaced())
                                Spacer()
                                Text(l.date, style: .time).font(.caption).foregroundStyle(.secondary)
                            }
                            if let d = l.document, !d.isEmpty {
                                Text(d).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                            }
                        }
                    }
                } header: {
                    HStack {
                        Text(tr("Ce que les assistants ont lu"))
                        Spacer()
                        if !serveur.journal.isEmpty {
                            Button(tr("Effacer")) { serveur.viderJournal() }.font(.caption)
                        }
                    }
                } footer: {
                    Text(tr("L’outil et le document, jamais ce qui a été cherché. Le journal s’efface quand md Viewer se ferme."))
                }
            }
        }
        .navigationTitle(tr("Assistants (MCP)"))
        .navigationBarTitleDisplayMode(.inline)
        .tint(orange)
        .alert(tr("Renouveler le jeton ?"), isPresented: $renouveler) {
            Button(tr("Renouveler"), role: .destructive) { serveur.renouvelerJeton(); jetonVisible = true }
            Button(tr("Annuler"), role: .cancel) {}
        } message: {
            Text(tr("Les assistants déjà branchés ne pourront plus lire le coffre tant qu’ils n’auront pas reçu le nouveau jeton."))
        }
    }

    private var commandeClaude: String {
        "claude mcp add --transport http md-viewer \(serveur.url) --header \"Authorization: Bearer \(serveur.jeton)\""
    }

    private var commandeCodex: String {
        "codex mcp add md-viewer --url \(serveur.url) --bearer-token-env-var MDVIEWER_TOKEN  # export MDVIEWER_TOKEN=\(serveur.jeton)"
    }

    private var configurationJSON: String {
        """
        {"mcpServers": {"md-viewer": {"type": "http", "url": "\(serveur.url)", "headers": {"Authorization": "Bearer \(serveur.jeton)"}}}}
        """
    }

    /// Le jeton reste masqué à l'écran tant qu'on ne demande pas à le voir ; la copie le porte.
    private func ligneCopiable(_ titre: String, _ valeur: String, monospace: Bool = false) -> some View {
        let affichee = jetonVisible || serveur.jeton.isEmpty ? valeur
            : valeur.replacingOccurrences(of: serveur.jeton, with: "mdv_••••••")
        return HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text(titre)
                Text(affichee)
                    .font(monospace ? .caption.monospaced() : .callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(monospace ? 3 : 1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
            Spacer()
            boutonCopier(valeur)
        }
    }

    private func boutonCopier(_ valeur: String) -> some View {
        Button {
            UIPasteboard.general.string = valeur
            copie = valeur
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { if copie == valeur { copie = nil } }
        } label: {
            Image(systemName: copie == valeur ? "checkmark" : "doc.on.doc")
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(tr("Copier"))
    }
}
