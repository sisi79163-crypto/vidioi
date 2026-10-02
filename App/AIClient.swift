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

extension AIClient {
    static func chatGPT(prompt:String,project:EditProject,model:String,accessToken:String) async throws -> EditPlan {
        var request=URLRequest(url:URL(string:"https://api.openai.com/v1/responses")!)
        request.httpMethod="POST";request.timeoutInterval=180
        request.setValue("Bearer \(accessToken)",forHTTPHeaderField:"Authorization")
        request.setValue("application/json",forHTTPHeaderField:"Content-Type")
        request.setValue("text/event-stream",forHTTPHeaderField:"Accept")
        request.httpBody=try AIContract.request(prompt:prompt,project:project,model:model)
        let (bytes,response)=try await URLSession.shared.bytes(for:request)
        guard let status=(response as? HTTPURLResponse)?.statusCode,status==200 else {
            let status=(response as? HTTPURLResponse)?.statusCode ?? 0
            if status==401 {throw EditError.invalid("انتهى تفويض ChatGPT. أعد تسجيل الدخول.")}
            if status==429 {throw EditError.invalid("وصل الحساب إلى حد الاستخدام. أعد المحاولة لاحقًا.")}
            throw EditError.invalid("تعذّر الاتصال بـ ChatGPT (\(status))")
        }
        var stream=ResponseAccumulator();var size=0
        for try await line in bytes.lines {
            try Task.checkCancellation();size += line.utf8.count
            guard size<=2_000_000 else {throw EditError.invalid("استجابة AI كبيرة جدًا")}
            try stream.consume(line)
        }
        return try stream.plan(for:project)
    }
    static func testGateway(endpoint:String,token:String) async throws -> String {
        guard let base=URL(string:endpoint),base.scheme=="https",base.host != nil,!token.isEmpty else {throw EditError.invalid("أدخل رابط HTTPS ورمز الاتصال")}
        var request=URLRequest(url:base.appendingPathComponent("v1/status"));request.timeoutInterval=20
        request.setValue("Bearer \(token)",forHTTPHeaderField:"Authorization")
        let (data,response)=try await URLSession.shared.data(for:request)
        guard (response as? HTTPURLResponse)?.statusCode==200,
              let json=try JSONSerialization.jsonObject(with:data) as? [String:Any] else {throw EditError.invalid("فشل اختبار الخادم أو رمز الاتصال")}
        guard json["aiConfigured"] as? Bool==true else {throw EditError.invalid("الخادم متصل لكن مفتاح OpenAI غير مضبوط")}
        return "الخادم جاهز · \(json["model"] as? String ?? "OpenAI")"
    }
}
