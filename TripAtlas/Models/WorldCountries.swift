import Foundation

/// Часть света для группировки стран.
enum Continent: String, CaseIterable, Identifiable {
    case europe, asia, africa, northAmerica, southAmerica, oceania, other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .europe: "Европа"
        case .asia: "Азия"
        case .africa: "Африка"
        case .northAmerica: "Северная Америка"
        case .southAmerica: "Южная Америка"
        case .oceania: "Океания"
        case .other: "Другие"
        }
    }

    var symbol: String {
        switch self {
        case .europe, .africa: "globe.europe.africa.fill"
        case .asia, .oceania: "globe.asia.australia.fill"
        case .northAmerica, .southAmerica: "globe.americas.fill"
        case .other: "globe"
        }
    }
}

struct WorldCountry: Identifiable, Hashable {
    let code: String
    let name: String
    let continent: Continent
    /// Входит в «195 стран мира» (члены ООН + Ватикан и Палестина).
    /// Остальное — территории вроде Гонконга или Пуэрто-Рико; они попадают в список,
    /// только если вы там были.
    let isSovereign: Bool

    var id: String { code }
    var flag: String { Geo.flag(for: code) }
}

enum WorldCountries {
    /// 193 члена ООН + 2 государства-наблюдателя.
    static let sovereignCodes: Set<String> = [
        "AF", "AL", "DZ", "AD", "AO", "AG", "AR", "AM", "AU", "AT", "AZ", "BS", "BH", "BD", "BB", "BY",
        "BE", "BZ", "BJ", "BT", "BO", "BA", "BW", "BR", "BN", "BG", "BF", "BI", "CV", "KH", "CM", "CA",
        "CF", "TD", "CL", "CN", "CO", "KM", "CG", "CD", "CR", "CI", "HR", "CU", "CY", "CZ", "DK", "DJ",
        "DM", "DO", "EC", "EG", "SV", "GQ", "ER", "EE", "SZ", "ET", "FJ", "FI", "FR", "GA", "GM", "GE",
        "DE", "GH", "GR", "GD", "GT", "GN", "GW", "GY", "HT", "HN", "HU", "IS", "IN", "ID", "IR", "IQ",
        "IE", "IL", "IT", "JM", "JP", "JO", "KZ", "KE", "KI", "KP", "KR", "KW", "KG", "LA", "LV", "LB",
        "LS", "LR", "LY", "LI", "LT", "LU", "MG", "MW", "MY", "MV", "ML", "MT", "MH", "MR", "MU", "MX",
        "FM", "MD", "MC", "MN", "ME", "MA", "MZ", "MM", "NA", "NR", "NP", "NL", "NZ", "NI", "NE", "NG",
        "MK", "NO", "OM", "PK", "PW", "PA", "PG", "PY", "PE", "PH", "PL", "PT", "QA", "RO", "RU", "RW",
        "KN", "LC", "VC", "WS", "SM", "ST", "SA", "SN", "RS", "SC", "SL", "SG", "SK", "SI", "SB", "SO",
        "ZA", "SS", "ES", "LK", "SD", "SR", "SE", "CH", "SY", "TJ", "TZ", "TH", "TL", "TG", "TO", "TT",
        "TN", "TR", "TM", "TV", "UG", "UA", "AE", "GB", "US", "UY", "UZ", "VU", "VE", "VN", "YE", "ZM",
        "ZW", "VA", "PS",
    ]

    static var total: Int { sovereignCodes.count }

    /// Часть света по данным Unicode CLDR, встроенным в iOS.
    static func continent(for code: String) -> Continent {
        let region = Locale.Region(code)
        // Сначала субрегион: Америки делим на Северную (с Центральной и Карибами) и Южную.
        switch region.containingRegion?.identifier {
        case "005": return .southAmerica
        case "013", "021", "029": return .northAmerica
        default: break
        }
        switch region.continent?.identifier {
        case "150": return .europe
        case "142": return .asia
        case "002": return .africa
        case "009": return .oceania
        case "019": return .northAmerica
        default: return .other
        }
    }

    /// Все страны мира + посещённые территории, которых нет среди 195 стран.
    static func list(including visited: Set<String>) -> [WorldCountry] {
        sovereignCodes.union(visited)
            .map { code in
                WorldCountry(code: code,
                             name: Geo.countryName(for: code),
                             continent: continent(for: code),
                             isSovereign: sovereignCodes.contains(code))
            }
            .sorted { $0.name.compare($1.name, locale: .current) == .orderedAscending }
    }
}
