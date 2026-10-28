// Ce que l'import PDF emprunte au reste de l'app, réduit au nécessaire pour le banc.
import Foundation

func tr(_ fr: String, _ args: CVarArg...) -> String { args.isEmpty ? fr : String(format: fr, arguments: args) }


enum KeywordMatcher {
    static func normalize(_ s: String) -> String {
        s.replacingOccurrences(of: "\u{2019}", with: "'")
            .folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: nil)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
