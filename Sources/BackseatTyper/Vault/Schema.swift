// Ported unchanged from Form Filler (iOS) Shared/Schema.swift.
import Foundation

enum FieldKind: String, Codable, CaseIterable {
    case text, date, email, tel, list
}

/// One kind of answer the vault can hold. Encoded with the same keys as the web version
/// (`type` for the kind) so backups move between the two.
struct FieldDef: Codable, Hashable, Identifiable {
    var key: String
    var label: String
    var group: String
    var kind: FieldKind
    var sensitive: Bool
    var custom: Bool

    var id: String { key }

    init(_ key: String, _ label: String, _ group: String, kind: FieldKind = .text, sensitive: Bool = false, custom: Bool = false) {
        self.key = key; self.label = label; self.group = group
        self.kind = kind; self.sensitive = sensitive; self.custom = custom
    }

    enum CodingKeys: String, CodingKey { case key, label, group, type, sensitive, custom }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        key = try c.decode(String.self, forKey: .key)
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? key
        group = try c.decodeIfPresent(String.self, forKey: .group) ?? "Custom"
        let t = try c.decodeIfPresent(String.self, forKey: .type) ?? "text"
        kind = FieldKind(rawValue: t) ?? .text
        sensitive = try c.decodeIfPresent(Bool.self, forKey: .sensitive) ?? false
        custom = try c.decodeIfPresent(Bool.self, forKey: .custom) ?? true
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(key, forKey: .key)
        try c.encode(label, forKey: .label)
        try c.encode(group, forKey: .group)
        try c.encode(kind.rawValue, forKey: .type)
        try c.encode(sensitive, forKey: .sensitive)
        try c.encode(custom, forKey: .custom)
    }
}

enum Schema {
    static let base: [FieldDef] = [
        FieldDef("given_name", "Given name", "Name"),
        FieldDef("middle_name", "Middle name", "Name"),
        FieldDef("family_name", "Family name", "Name"),
        FieldDef("preferred_name", "Preferred name", "Name"),
        FieldDef("dob", "Date of birth", "Personal", kind: .date),
        FieldDef("sex", "Sex", "Personal"),
        FieldDef("place_of_birth", "Place of birth", "Personal"),
        FieldDef("citizenship", "Citizenship", "Personal"),
        FieldDef("email", "Email", "Contact", kind: .email),
        FieldDef("phone", "Mobile phone", "Contact", kind: .tel),
        FieldDef("street", "Street address", "Address"),
        FieldDef("unit", "Apt or unit", "Address"),
        FieldDef("city", "City", "Address"),
        FieldDef("region", "State or province", "Address"),
        FieldDef("postal_code", "ZIP or postal code", "Address"),
        FieldDef("country", "Country", "Address"),
        FieldDef("ssn", "Social Security number", "Identity documents", sensitive: true),
        FieldDef("passport_number", "Passport number", "Identity documents", sensitive: true),
        FieldDef("passport_expiry", "Passport expiry", "Identity documents", kind: .date),
        FieldDef("drivers_license", "Driver's license number", "Identity documents", sensitive: true),
        FieldDef("dl_state", "License issuing state", "Identity documents"),
        FieldDef("employer", "Employer", "Work"),
        FieldDef("job_title", "Job title", "Work"),
        FieldDef("work_phone", "Work phone", "Work", kind: .tel),
        FieldDef("emergency_name", "Emergency contact name", "Emergency contact"),
        FieldDef("emergency_relation", "Emergency contact relationship", "Emergency contact"),
        FieldDef("emergency_phone", "Emergency contact phone", "Emergency contact", kind: .tel),
        FieldDef("blood_type", "Blood type", "Medical"),
        FieldDef("height", "Height", "Medical"),
        FieldDef("weight", "Weight", "Medical"),
        FieldDef("allergies", "Allergies", "Medical", kind: .list, sensitive: true),
        FieldDef("medications", "Current medications", "Medical", kind: .list, sensitive: true),
        FieldDef("conditions", "Medical conditions", "Medical", kind: .list, sensitive: true),
        FieldDef("surgeries", "Surgeries and procedures", "Medical", kind: .list, sensitive: true),
        FieldDef("immunizations", "Immunizations", "Medical", kind: .list, sensitive: true),
        FieldDef("physician_name", "Primary care physician", "Care team"),
        FieldDef("physician_phone", "Physician phone", "Care team", kind: .tel),
        FieldDef("pharmacy", "Pharmacy", "Care team"),
        FieldDef("insurance_provider", "Insurance company", "Insurance"),
        FieldDef("insurance_member_id", "Member ID", "Insurance", sensitive: true),
        FieldDef("insurance_group", "Group number", "Insurance"),
        FieldDef("insurance_holder", "Policy holder", "Insurance"),
    ]

    static let groupOrder = ["Name", "Personal", "Contact", "Address", "Identity documents", "Work",
                             "Emergency contact", "Medical", "Care team", "Insurance", "Custom"]
}
