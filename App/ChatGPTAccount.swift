import SwiftUI
import AuthenticationServices
import Network
import CryptoKit
import Security

struct ChatGPTSession:Codable {
    var clientID:String;var subject:String;var email:String;var idToken:String
    var accessToken:String;var refreshToken:String;var scopes:String;var expiresAt:Date
}
struct AccountModel:Identifiable,Codable {var id:String;var name:String}
@MainActor final class ChatGPTAccount:NSObject,ObservableObject,ASWebAuthenticationPresentationContextProviding {
    @Published private(set) var session:ChatGPTSession?
    @Published private(set) var connecting=false
    @Published var message=""
    @Published private(set) var models:[AccountModel]=[]
    @Published var model=""
    private var listener:NWListener?
    private var web:ASWebAuthenticationSession?
    private var timeout:Task<Void,Never>?
    private var refreshTask:Task<ChatGPTSession,Error>?
    private var pendingState="";private var nonce="";private var verifier="";private var redirect:URL?
    private var exchanging=false
    private var hostID:String {
        if let saved=SecureVault.read("hostID"),let s=String(data:saved,encoding:.utf8) {return s}
        let id="urn:uuid:"+UUID().uuidString
        try? SecureVault.write(Data(id.utf8),account:"hostID");return id
    }
    var isConnected:Bool {session != nil && session!.scopes.split(separator:" ").contains("chatgpt.tokens.use.direct")}
    override init() {
        super.init()
        if let data=SecureVault.read("chatgptSession") {session=try? JSONDecoder().decode(ChatGPTSession.self,from:data)}
        model=UserDefaults.standard.string(forKey:"chatgptModel") ?? ""
    }
    func signIn() {
        guard !connecting else{return};connecting=true;message="فتح تسجيل الدخول الآمن…";exchanging=false
        do {
            pendingState=try random();nonce=try random();verifier=try random()
            let parameters=NWParameters.tcp
            parameters.requiredLocalEndpoint = .hostPort(host:"127.0.0.1",port:.any)
            let server=try NWListener(using:parameters);listener=server
            server.stateUpdateHandler={ [weak self] state in Task { @MainActor in
                guard let self else{return}
                switch state {
                case .ready: if let port=server.port {self.openAuthorization(port:port.rawValue)}
                case .failed: self.fail("تعذّر فتح اتصال تسجيل الدخول على هذا الجهاز")
                default:break
                }
            }}
            server.newConnectionHandler={ [weak self] connection in Task { @MainActor in self?.receive(connection) } }
            server.start(queue:.main)
            timeout=Task {try? await Task.sleep(nanoseconds:300_000_000_000);if !Task.isCancelled {self.fail("انتهت مهلة تسجيل الدخول. أعد المحاولة.")}}
        } catch {fail(error.localizedDescription)}
    }
    private func openAuthorization(port:UInt16) {
        guard connecting,web==nil else{return}
        let callback=URL(string:"http://127.0.0.1:\(port)/auth/callback")!;redirect=callback
        var url=URLComponents(string:"https://auth.openai.com/api/accounts/authorize")!
        var fields=["client_id":session?.clientID ?? "dynamic_agent_client","response_type":"code","redirect_uri":callback.absoluteString,
                    "scope":OAuthContract.scopes,"resource":OAuthContract.resource,"state":pendingState,"nonce":nonce,
                    "code_challenge_method":"S256","code_challenge":OAuthContract.base64URL(Data(SHA256.hash(data:Data(verifier.utf8)))),"ext_agent_host_id":hostID]
        if let session {fields["id_token_hint"]=session.idToken} else {fields["agent_name_hint"]="vidioi"}
        url.queryItems=fields.map {URLQueryItem(name:$0.key,value:$0.value)}
        let browser=ASWebAuthenticationSession(url:url.url!,callbackURLScheme:nil) { [weak self] _,error in Task { @MainActor in
            guard let self,!self.exchanging,self.connecting else{return}
            self.fail(error == nil ? "لم يكتمل تسجيل الدخول" : "أُغلق تسجيل الدخول")
        }}
        browser.presentationContextProvider=self;browser.prefersEphemeralWebBrowserSession=false;web=browser
        if !browser.start() {fail("تعذّر فتح نافذة تسجيل الدخول")}
    }
    private func receive(_ connection:NWConnection,buffer:Data=Data()) {
        if buffer.isEmpty {connection.start(queue:.main)}
        connection.receive(minimumIncompleteLength:1,maximumLength:16384) { [weak self] data,_,complete,error in Task { @MainActor in
            guard let self else {connection.cancel();return}
            var all=buffer;if let data {all.append(data)}
            guard all.count<=16384 else {connection.cancel();return}
            guard let request=String(data:all,encoding:.utf8),request.contains("\r\n\r\n") else {
                if complete || error != nil {connection.cancel()} else {self.receive(connection,buffer:all)};return
            }
            let first=request.components(separatedBy:"\r\n").first?.split(separator:" ") ?? []
            guard first.count>=2,first[0]=="GET",let redirect=self.redirect,
                  let url=URL(string:"http://127.0.0.1:\(redirect.port ?? 0)"+String(first[1])),url.path=="/auth/callback",!self.exchanging else {connection.cancel();return}
            let result=OAuthContract.callback(url,redirect:redirect,state:self.pendingState,clientID:self.session?.clientID)
            let body=result == nil ? "Sign-in could not be verified. Return to vidioi." : "You can return to vidioi. Completing sign-in..."
            let response="HTTP/1.1 \(result == nil ? "400 Bad Request":"200 OK")\r\nContent-Type: text/plain; charset=utf-8\r\nCache-Control: no-store\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n"+body
            connection.send(content:Data(response.utf8),completion:.contentProcessed {_ in connection.cancel()})
            guard let result else {return}
            self.exchanging=true;self.web?.cancel();self.listener?.cancel();self.message="التحقق من الحساب…"
            Task { await self.complete(code:result.code,client:result.client,redirect:redirect) }
        }}
    }
    private func complete(code:String,client:String,redirect:URL) async {
        let attempt=pendingState
        do {
            let token=try await tokenRequest(["grant_type":"authorization_code","client_id":client,"code":code,"code_verifier":verifier,"redirect_uri":redirect.absoluteString,"resource":OAuthContract.resource])
            guard let idToken=token["id_token"] as? String else {throw EditError.invalid("رمز الهوية مفقود")}
            let (jwks,response)=try await URLSession.shared.data(from:URL(string:"https://auth.openai.com/.well-known/jwks.json")!)
            guard (response as? HTTPURLResponse)?.statusCode==200 else {throw EditError.invalid("تعذّر التحقق من توقيع الحساب")}
            let identity=try OAuthContract.verifyIDToken(idToken,jwks:jwks,clientID:client,nonce:nonce)
            if let previous=session,previous.subject != identity.subject {throw EditError.invalid("الحساب مختلف. سجّل الخروج أولًا لإضافة حساب آخر.")}
            let record=try makeSession(token,client:client,identity:identity,idToken:idToken)
            guard connecting,pendingState==attempt else{return}
            try save(record);stopAttempt();message="تم تسجيل الدخول";try await loadModels()
        } catch {fail(error.localizedDescription)}
    }
    func accessToken() async throws -> String {
        guard let session,isConnected else {throw EditError.invalid("اربط حساب ChatGPT أولًا")}
        if session.expiresAt.timeIntervalSinceNow>60 {return session.accessToken}
        if let refreshTask {return try await refreshTask.value.accessToken}
        let task=Task { @MainActor in
            let token=try await self.tokenRequest(["grant_type":"refresh_token","client_id":session.clientID,"refresh_token":session.refreshToken,"resource":OAuthContract.resource])
            var record=session
            guard let access=token["access_token"] as? String,let refresh=token["refresh_token"] as? String,
                  let lifetime=token["expires_in"] as? Double else {throw EditError.invalid("أعد تسجيل الدخول لتجديد الاتصال")}
            if let id=token["id_token"] as? String {
                let (keys,_)=try await URLSession.shared.data(from:URL(string:"https://auth.openai.com/.well-known/jwks.json")!)
                let identity=try OAuthContract.verifyIDToken(id,jwks:keys,clientID:session.clientID,nonce:nil)
                guard identity.subject==session.subject else {throw EditError.invalid("هوية التجديد غير مطابقة")}
                record.idToken=id
            }
            record.accessToken=access;record.refreshToken=refresh;record.expiresAt=Date().addingTimeInterval(lifetime)
            if let scopes=token["scope"] as? String {record.scopes=scopes}
            guard record.scopes.split(separator:" ").contains("chatgpt.tokens.use.direct") else {throw EditError.invalid("الحساب لم يمنح صلاحية استخدام الخطة")}
            try Task.checkCancellation()
            guard self.session?.subject==session.subject,self.session?.clientID==session.clientID else {throw EditError.invalid("تغيّر الحساب أثناء التجديد")}
            try self.save(record);return record
        }
        refreshTask=task;defer{refreshTask=nil}
        return try await task.value.accessToken
    }
    func loadModels() async throws {
        var request=URLRequest(url:URL(string:"https://api.openai.com/v1/models")!)
        request.setValue("Bearer \(try await accessToken())",forHTTPHeaderField:"Authorization")
        let (data,response)=try await URLSession.shared.data(for:request)
        guard (response as? HTTPURLResponse)?.statusCode==200 else {throw EditError.invalid("تعذّر جلب النماذج المتاحة لحسابك")}
        let json=try JSONSerialization.jsonObject(with:data) as? [String:Any]
        models=(json?["models"] as? [[String:Any]] ?? []).filter {$0["visibility"] as? String=="list"}.compactMap { item in
            guard let slug=item["slug"] as? String else{return nil};return AccountModel(id:slug,name:item["display_name"] as? String ?? slug)
        }
        if !models.contains(where:{$0.id==model}) {model=models.first?.id ?? ""}
        UserDefaults.standard.set(model,forKey:"chatgptModel")
        guard !models.isEmpty else {throw EditError.invalid("لا توجد نماذج متاحة لهذا الحساب حاليًا")}
        message="الاتصال جاهز · \(models.count) نماذج متاحة"
    }
    func signOut() {stopAttempt();refreshTask?.cancel();refreshTask=nil;try? SecureVault.remove("chatgptSession");session=nil;models=[];model="";message="تم فصل الحساب من هذا الجهاز"}
    func cancel() {stopAttempt();message="أُلغي تسجيل الدخول"}
    private func fail(_ text:String) {stopAttempt();message=text}
    private func stopAttempt() {connecting=false;web?.cancel();web=nil;listener?.cancel();listener=nil;timeout?.cancel();timeout=nil;pendingState="";nonce="";verifier="";redirect=nil;exchanging=false}
    private func save(_ value:ChatGPTSession)throws {try SecureVault.write(JSONEncoder().encode(value),account:"chatgptSession");session=value}
    private func makeSession(_ token:[String:Any],client:String,identity:OpenAIIdentity,idToken:String)throws->ChatGPTSession {
        guard let access=token["access_token"] as? String,let refresh=token["refresh_token"] as? String,
              let lifetime=token["expires_in"] as? Double,let scopes=token["scope"] as? String,
              scopes.split(separator:" ").contains("chatgpt.tokens.use.direct") else {throw EditError.invalid("لم يُمنح إذن استخدام خطة ChatGPT. أعد الدخول ووافق على الصلاحية.")}
        return ChatGPTSession(clientID:client,subject:identity.subject,email:identity.email,idToken:idToken,accessToken:access,refreshToken:refresh,scopes:scopes,expiresAt:Date().addingTimeInterval(lifetime))
    }
    private func tokenRequest(_ fields:[String:String]) async throws->[String:Any] {
        var request=URLRequest(url:URL(string:"https://auth.openai.com/api/accounts/oauth/token")!);request.httpMethod="POST";request.timeoutInterval=30
        request.setValue("application/x-www-form-urlencoded",forHTTPHeaderField:"Content-Type")
        let safe=CharacterSet.alphanumerics.union(CharacterSet(charactersIn:"-._~"))
        request.httpBody=Data(fields.map {($0.key.addingPercentEncoding(withAllowedCharacters:safe) ?? "")+"="+($0.value.addingPercentEncoding(withAllowedCharacters:safe) ?? "")}.joined(separator:"&").utf8)
        let (data,response)=try await URLSession.shared.data(for:request)
        guard (response as? HTTPURLResponse)?.statusCode==200,let object=try JSONSerialization.jsonObject(with:data) as? [String:Any] else {throw EditError.invalid("لم يكتمل تفويض الحساب. أعد تسجيل الدخول.")}
        return object
    }
    private func random()throws->String {var bytes=[UInt8](repeating:0,count:32);guard SecRandomCopyBytes(kSecRandomDefault,bytes.count,&bytes)==errSecSuccess else{throw EditError.invalid("تعذّر إعداد جلسة آمنة")};return OAuthContract.base64URL(Data(bytes))}
    func presentationAnchor(for session:ASWebAuthenticationSession)->ASPresentationAnchor {UIApplication.shared.connectedScenes.compactMap {$0 as? UIWindowScene}.flatMap(\.windows).first {$0.isKeyWindow} ?? ASPresentationAnchor()}
}
enum SecureVault {
    private static func query(_ account:String)->[String:Any] {[kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:"app.vidioi.credentials",kSecAttrAccount as String:account]}
    static func read(_ account:String)->Data? {var q=query(account);q[kSecReturnData as String]=true;q[kSecMatchLimit as String]=kSecMatchLimitOne;var result:CFTypeRef?;guard SecItemCopyMatching(q as CFDictionary,&result)==errSecSuccess else{return nil};return result as? Data}
    static func write(_ data:Data,account:String)throws {
        let q=query(account);let update=[kSecValueData as String:data] as CFDictionary
        let status=SecItemUpdate(q as CFDictionary,update)
        if status==errSecItemNotFound {var item=q;item[kSecValueData as String]=data;item[kSecAttrAccessible as String]=kSecAttrAccessibleWhenUnlockedThisDeviceOnly;guard SecItemAdd(item as CFDictionary,nil)==errSecSuccess else{throw EditError.invalid("تعذّر حفظ الاتصال")}}
        else if status != errSecSuccess {throw EditError.invalid("تعذّر تحديث الاتصال")}
    }
    static func remove(_ account:String)throws {let status=SecItemDelete(query(account) as CFDictionary);guard status==errSecSuccess || status==errSecItemNotFound else{throw EditError.invalid("تعذّر فصل الحساب")}}
}
