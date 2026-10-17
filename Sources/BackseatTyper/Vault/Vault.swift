import Foundation
import Observation
import Contacts

/// Your form answers, encrypted at rest (see Storage.swift). What Form Filler keeps on the iPhone, kept here on the Mac.
@Observable final class Vault {
    static let shared = Vault()
    var data: VaultData
    var loadError: String?
    private var plainTest = false   // --e2e only: a plain JSON vault that is never written back

    init() {
        do { data = try VaultFile.load() ?? VaultData() } catch { data = VaultData(); loadError = error.localizedDescription }
    }
    func save() { guard !plainTest else { return }; do { try VaultFile.save(data) } catch { loadError = error.localizedDescription } }
    func loadPlain(path: String) {
        guard let d = FileManager.default.contents(atPath: path), let v = try? JSONDecoder().decode(VaultData.self, from: d) else { return }
        data = v; plainTest = true
    }
    func importBackup(url: URL, passphrase: String) throws {
        data = try Backup.open(try Data(contentsOf: url), passphrase: passphrase); save()
    }
    func erase() { data = VaultData(); VaultFile.erase() }
    var isEmpty: Bool { data.profiles.allSatisfy { $0.values.isEmpty } }
}

extension Vault {
    /// Fills the empty fields of a profile from the macOS Contacts "me" card; adds custom fields for what the
    /// schema lacks (work email, work address, website). Returns the keys it set.
    func importMeCard(into pid: String) async throws -> [String] {
        let store = CNContactStore()
        guard try await store.requestAccess(for: .contacts) else { throw NSError(domain: "BackseatTyper", code: 1, userInfo: [NSLocalizedDescriptionKey: "Contacts access was not allowed."]) }
        let keys: [CNKeyDescriptor] = [CNContactGivenNameKey, CNContactMiddleNameKey, CNContactFamilyNameKey, CNContactNicknameKey, CNContactBirthdayKey,
                                       CNContactEmailAddressesKey, CNContactPhoneNumbersKey, CNContactPostalAddressesKey, CNContactOrganizationNameKey,
                                       CNContactJobTitleKey, CNContactUrlAddressesKey] as [CNKeyDescriptor]
        let me = try store.unifiedMeContactWithKeys(toFetch: keys)
        var set: [String] = []
        func put(_ key: String, _ v: String?) {
            guard let v = v?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty, data.value(pid, key).isEmpty else { return }
            data.setValue(pid, key, v); set.append(key)
        }
        func custom(_ label: String, _ v: String?) {
            guard let v, !v.isEmpty else { return }
            let key = data.custom.first { $0.label == label }?.key ?? data.addCustomField(label: label, kind: .text, sensitive: false)
            put(key, v)
        }
        put("given_name", me.givenName); put("middle_name", me.middleName); put("family_name", me.familyName); put("preferred_name", me.nickname)
        if let b = me.birthday, let y = b.year, let m = b.month, let d = b.day { put("dob", String(format: "%04d-%02d-%02d", y, m, d)) }
        put("employer", me.organizationName); put("job_title", me.jobTitle)
        let phones = me.phoneNumbers
        let mobile = phones.first { [CNLabelPhoneNumberMobile, CNLabelPhoneNumberiPhone, CNLabelPhoneNumberMain].contains($0.label ?? "") } ?? phones.first { $0.label != CNLabelWork } ?? phones.first
        put("phone", mobile?.value.stringValue)
        put("work_phone", phones.first { $0.label == CNLabelWork && $0 != mobile }?.value.stringValue)
        let emails = me.emailAddresses
        let personal = emails.first { $0.label != CNLabelWork } ?? emails.first
        put("email", personal.map { String($0.value) })
        custom("Work email", emails.first { $0.label == CNLabelWork && $0 != personal }.map { String($0.value) })
        let addrs = me.postalAddresses
        if let home = addrs.first(where: { $0.label == CNLabelHome }) ?? addrs.first(where: { $0.label != CNLabelWork }) ?? addrs.first {
            let lines = home.value.street.split(separator: "\n").map(String.init)
            put("street", lines.first); put("unit", lines.count > 1 ? lines[1] : nil)
            put("city", home.value.city); put("region", home.value.state); put("postal_code", home.value.postalCode); put("country", home.value.country)
        }
        if let work = addrs.first(where: { $0.label == CNLabelWork }), addrs.count > 1 {
            custom("Work address", CNPostalAddressFormatter.string(from: work.value, style: .mailingAddress).replacingOccurrences(of: "\n", with: ", "))
        }
        custom("Website", me.urlAddresses.first.map { String($0.value) })
        if set.isEmpty == false { save() }
        return set
    }
}
