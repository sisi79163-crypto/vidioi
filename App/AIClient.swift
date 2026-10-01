import Foundation
import Security

enum AIClient {
    static func plan(prompt: String, project: EditProject, endpoint: String, token: String) async throws -> EditPlan {
        guard let url = URL(string: endpoint), url.scheme == "https", url.host != nil, !token.isEmpty else {
            throw EditError.invalid("أدخل رابط خادم HTTPS ورمز الاتصال في الإعدادات")
        }
        var request = URLRequest(url: url.appendingPathComponent("v1/edit")); request.httpMethod = "POST"; request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        struct Payload: Encodable { let prompt: String; let project: EditProject }
        request.httpBody = try JSONEncoder().encode(Payload(prompt: prompt, project: project))
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw EditError.invalid("استجابة خادم غير صالحة") }
        guard http.statusCode == 200 else {
            let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            throw EditError.invalid(body?["error"] as? String ?? "فشل الاتصال: \(http.statusCode)")
        }
        let plan = try JSONDecoder().decode(EditPlan.self, from: data)
        _ = try plan.applying(to: project) // Validate before exposing the apply button.
        return plan
    }
}
enum SecureSettings {
    private static let service = "app.vidioi.gateway"
    static func token() -> String {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
            kSecAttrAccount as String: "token", kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }
    static func save(token: String) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "token"]
        SecItemDelete(query as CFDictionary)
        guard !token.isEmpty else { return }
        var item = query; item[kSecValueData as String] = Data(token.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw EditError.invalid("تعذّر حفظ رمز الاتصال") }
    }
}
