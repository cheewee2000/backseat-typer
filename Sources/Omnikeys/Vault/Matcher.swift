// Ported from Form Filler (one change, marked) (iOS) Shared/Matcher.swift.
import Foundation

/// On-device label matching. No network. Mirrors the web version's rules.
enum Matcher {
    private static let raw: [(String, String)] = [
        (#"emergency.*(phone|tel|number|cell)"#, "{P.emergency_phone}"),
        (#"emergency.*relat|relationship"#, "{P.emergency_relation}"),
        (#"emergency|in case of"#, "{P.emergency_name}"),
        (#"allerg"#, "{P.allergies}"),
        (#"medication|medicine|\bmeds\b|prescription"#, "{P.medications}"),
        (#"immuni[sz]|vaccin"#, "{P.immunizations}"),
        (#"surger|operations?\b|procedures|hospitali[sz]"#, "{P.surgeries}"),
        (#"(medical|health|chronic|current|existing)\s*(conditions?|problems)|diagnos|medical history|illness"#, "{P.conditions}"),
        (#"blood\s*(type|group)"#, "{P.blood_type}"),
        (#"height"#, "{P.height}"),
        (#"weight"#, "{P.weight}"),
        (#"pharmacy"#, "{P.pharmacy}"),
        (#"(physician|doctor|\bpcp\b).*(phone|tel|number)"#, "{P.physician_phone}"),
        (#"physician|doctor|\bpcp\b|primary care"#, "{P.physician_name}"),
        (#"(member|subscriber|policy|insurance)\s*(id|no\.?|number|#)"#, "{P.insurance_member_id}"),
        (#"group\s*(id|no\.?|number|#)"#, "{P.insurance_group}"),
        (#"(policy\s*holder|subscriber|insured)('?s)?(\s*name)?"#, "{P.insurance_holder}"),
        (#"insurance|insurer|health plan"#, "{P.insurance_provider}"),
        (#"e-?mail"#, "{P.email}"),
        (#"(work|office|business)\s*(phone|tel)"#, "{P.work_phone}"),
        (#"(middle)\s*initial|\bm\.?i\.?$"#, "{P.middle_name|initial}"),
        (#"middle"#, "{P.middle_name}"),
        (#"(first|given|fore)\s*name|^first$"#, "{P.given_name}"),
        (#"(last|family)\s*name|surname|^last$"#, "{P.family_name}"),
        (#"preferred|nickname"#, "{P.preferred_name}"),
        (#"(full|legal|complete|applicant'?s?|your|print(ed)?)\s*name|^name\b|name of (applicant|student|patient|child)"#, "{P.given_name} {P.family_name}"),
        (#"date of birth|birth\s*date|\bd\.?o\.?b\b|birthday"#, "{P.dob|MM/DD/YYYY}"),
        (#"place of birth|birth\s*place|city of birth"#, "{P.place_of_birth}"),
        (#"citizen|nationality"#, "{P.citizenship}"),
        (#"\bsex\b|gender"#, "{P.sex}"),
        (#"social security|\bssn\b|\bss#"#, "{P.ssn}"),
        (#"passport.*(exp)"#, "{P.passport_expiry|MM/DD/YYYY}"),
        (#"passport"#, "{P.passport_number}"),
        (#"licen[cs]e.*state|issuing state"#, "{P.dl_state}"),
        (#"driver|licen[cs]e\s*(no|num|#)|\bdl\b"#, "{P.drivers_license}"),
        (#"mobile|cell|phone|telephone|\btel\b"#, "{P.phone}"),
        (#"apt|apartment|suite|unit|address (line )?2"#, "{P.unit}"),
        (#"\bzip|postal|post\s*code"#, "{P.postal_code}"),
        (#"\bcity\b|\btown\b"#, "{P.city}"),
        (#"\bstate\b|province|region"#, "{P.region}"),
        (#"country"#, "{P.country}"),
        (#"street|address"#, "{P.street}"),
        (#"employer|company|organi[sz]ation|business name"#, "{P.employer}"),
        (#"job|title|occupation|position"#, "{P.job_title}"),
        (#"^date$|today|date signed|signature date"#, "{today|MM/DD/YYYY}"),
    ]
    private static let rules: [(NSRegularExpression, String)] = raw.map {
        (try! NSRegularExpression(pattern: $0.0, options: [.caseInsensitive]), $0.1)
    }

    /// HTML autocomplete tokens, the most reliable signal on web forms.
    private static let autocomplete: [String: String] = [
        "given-name": "{P.given_name}", "additional-name": "{P.middle_name}", "family-name": "{P.family_name}",
        "name": "{P.given_name} {P.family_name}", "nickname": "{P.preferred_name}",
        "email": "{P.email}", "tel": "{P.phone}", "tel-national": "{P.phone}",
        "street-address": "{P.street}", "address-line1": "{P.street}", "address-line2": "{P.unit}",
        "address-level2": "{P.city}", "address-level1": "{P.region}", "postal-code": "{P.postal_code}",
        "country-name": "{P.country}", "country": "{P.country}", "bday": "{P.dob}", "sex": "{P.sex}",
        "organization": "{P.employer}", "organization-title": "{P.job_title}",
    ]

    private static func norm(_ s: String) -> String {
        s.lowercased().replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    static func match(_ text: String, pid: String, vault: VaultData) -> String {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return "" }
        let n = norm(t)
        for c in vault.custom where !norm(c.label).isEmpty && n.contains(norm(c.label)) {
            return "{\(pid).\(c.key)\(c.kind == .date ? "|MM/DD/YYYY" : c.kind == .list ? "|lines" : "")}"   // Omnikeys: learned textareas keep their lines
        }
        let range = NSRange(location: 0, length: (t as NSString).length)
        for (re, tpl) in rules where re.firstMatch(in: t, range: range) != nil {
            var out = tpl.replacingOccurrences(of: "{P.", with: "{\(pid).")
            if out.contains("|MM/DD/YYYY") {
                if t.range(of: #"dd\s*/\s*mm"#, options: [.regularExpression, .caseInsensitive]) != nil {
                    out = out.replacingOccurrences(of: "MM/DD/YYYY", with: "DD/MM/YYYY")
                } else if t.range(of: #"yyyy\s*-\s*mm"#, options: [.regularExpression, .caseInsensitive]) != nil {
                    out = out.replacingOccurrences(of: "MM/DD/YYYY", with: "YYYY-MM-DD")
                }
            }
            return out
        }
        return ""
    }

    /// Matching for a web form field: autocomplete attribute first, then label, then the field's name.
    static func matchWeb(label: String, name: String, autocomplete ac: String, pid: String, vault: VaultData) -> String {
        let tokens = ac.lowercased().split(separator: " ").map(String.init)
        for tok in tokens.reversed() {
            if let tpl = autocomplete[tok] { return tpl.replacingOccurrences(of: "{P.", with: "{\(pid).") }
        }
        let byLabel = match(label, pid: pid, vault: vault)
        if !byLabel.isEmpty { return byLabel }
        let human = name.replacingOccurrences(of: "[_.\\[\\]\\-0-9]+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression)
        return match(human, pid: pid, vault: vault)
    }
}
