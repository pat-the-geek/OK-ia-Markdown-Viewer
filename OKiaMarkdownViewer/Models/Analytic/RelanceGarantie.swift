// Le `RelanceGarantie` de md Viewer : jamais disponible. Le `GardeFousIA` copié de fornews le consulte
// après cinq délais dépassés d'Apple Intelligence, pour quitter et se faire relancer par launchd — ce
// que fait fornews en mode serveur. md Viewer ne quitte jamais de lui-même.
enum RelanceGarantie {
    static let disponible = false
    static func quitterPourRelance() {}
}
