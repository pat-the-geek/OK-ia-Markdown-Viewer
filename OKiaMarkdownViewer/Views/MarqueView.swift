import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

/// Option Analytic (1.6) — régler le thème « à vos couleurs » (`ThemeMarque`) : un logo, le fond,
/// l'accent et la police, avec un aperçu d'une diapositive.
struct MarqueView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var theme = ThemeMarque.actuel ?? ThemeMarque()
    @State private var existe = ThemeMarque.actuel != nil
    @State private var logo = ThemeMarque.logo
    @State private var choixPhoto: PhotosPickerItem?
    @State private var choixFichier = false
    @ObservedObject private var loc = Localization.shared
    private let orange = Color(red: 0xE8/255, green: 0x97/255, blue: 0x2E/255)

    var body: some View {
        NavigationStack {
            Form {
                Section { apercu.listRowInsets(EdgeInsets()) }
                Section(tr("Logo")) {
                    if let logo, let image = UIImage(data: logo) {
                        Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 60)
                        Button(tr("Retirer le logo"), role: .destructive) { self.logo = nil }
                    }
                    PhotosPicker(selection: $choixPhoto, matching: .images) {
                        Label(tr("Choisir dans Photos…"), systemImage: "photo")
                    }
                    Button { choixFichier = true } label: { Label(tr("Choisir un fichier…"), systemImage: "folder") }
                }
                Section(tr("Couleurs")) {
                    ColorPicker(tr("Fond"), selection: liaison(\.fond), supportsOpacity: false)
                    ColorPicker(tr("Accent (titres, liens)"), selection: liaison(\.accent), supportsOpacity: false)
                }
                Section(tr("Police")) {
                    Picker(tr("Police"), selection: $theme.police) {
                        ForEach(ThemeMarque.polices, id: \.self) { p in Text(p).font(.custom(p, size: 17)).tag(p) }
                    }
                    .pickerStyle(.navigationLink)
                }
                Section {
                    Toggle(tr("Pour tous les diaporamas"), isOn: $theme.defaut)
                } footer: {
                    Text(tr("Sinon, « Ma marque » est un thème parmi d’autres, dans le menu du diaporama. L’export PowerPoint reprend le logo, les couleurs et la police."))
                }
                if existe {
                    Section {
                        Button(tr("Supprimer le thème"), role: .destructive) {
                            ThemeMarque.actuel = nil
                            ThemeMarque.logo = nil
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(tr("Thème à vos couleurs"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(tr("Annuler")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(tr("Enregistrer")) {
                        ThemeMarque.logo = logo
                        ThemeMarque.actuel = theme
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .tint(orange)
            .onChange(of: choixPhoto) { _, item in
                Task {
                    if let d = try? await item?.loadTransferable(type: Data.self), let png = ThemeMarque.preparerLogo(d) { logo = png }
                }
            }
            .fileImporter(isPresented: $choixFichier, allowedContentTypes: [.image]) { r in
                guard case .success(let url) = r else { return }
                let s = url.startAccessingSecurityScopedResource()
                defer { if s { url.stopAccessingSecurityScopedResource() } }
                if let d = try? Data(contentsOf: url), let png = ThemeMarque.preparerLogo(d) { logo = png }
            }
        }
    }

    private func liaison(_ cle: WritableKeyPath<ThemeMarque, String>) -> Binding<Color> {
        Binding(get: { ThemeMarque.couleur(theme[keyPath: cle]) },
                set: { theme[keyPath: cle] = ThemeMarque.hex($0) })
    }

    /// Une diapositive d'exemple : le fond, un titre à la police choisie souligné de l'accent, du
    /// texte, le logo dans le coin.
    private var apercu: some View {
        let texte = ThemeMarque.couleur(theme.texte)
        return ZStack(alignment: .bottomTrailing) {
            ThemeMarque.couleur(theme.fond)
            VStack(alignment: .leading, spacing: 10) {
                Text(tr("Titre de la diapositive"))
                    .font(.custom(theme.police, size: 24).weight(.bold))
                    .foregroundStyle(texte)
                Rectangle().fill(ThemeMarque.couleur(theme.accent)).frame(width: 70, height: 4)
                (Text(tr("Le texte de la diapositive, à la police choisie,")).foregroundStyle(texte.opacity(0.85))
                 + Text(" ")
                 + Text(tr("et un lien à la couleur d’accent.")).foregroundStyle(ThemeMarque.couleur(theme.accent)).underline())
                    .font(.custom(theme.police, size: 15))
                Spacer(minLength: 0)
            }
            .padding(22)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            if let logo, let image = UIImage(data: logo) {
                Image(uiImage: image).resizable().scaledToFit().frame(maxWidth: 80, maxHeight: 34).padding(12)
            }
        }
        .aspectRatio(16 / 9, contentMode: .fit)
    }
}
