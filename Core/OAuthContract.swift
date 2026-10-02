import Foundation
import Security

struct OpenAIIdentity { let subject:String; let email:String }
enum OAuthContract {
    static let issuer = "https://auth.openai.com"
    static let resource = "https://api.openai.com/v1"
    static let scopes = "openid profile email offline_access resource.invoke chatgpt.tokens.use.direct"
    static func decodeBase64URL(_ input:String)->Data? {
        let s=input.replacingOccurrences(of:"-",with:"+").replacingOccurrences(of:"_",with:"/")
        return Data(base64Encoded:s + String(repeating:"=",count:(4-s.count%4)%4))
    }
    static func base64URL(_ data:Data)->String {data.base64EncodedString().replacingOccurrences(of:"+",with:"-").replacingOccurrences(of:"/",with:"_").replacingOccurrences(of:"=",with:"")}
    static func callback(_ url:URL,redirect:URL,state:String,clientID:String?)->(code:String,client:String)? {
        guard url.scheme==redirect.scheme,url.host==redirect.host,url.port==redirect.port,url.path==redirect.path,
              let parts=URLComponents(url:url,resolvingAgainstBaseURL:false) else {return nil}
        let pairs=parts.queryItems ?? []
        guard Set(pairs.map(\.name)).count==pairs.count else {return nil}
        let values=Dictionary(uniqueKeysWithValues:pairs.map {($0.name,$0.value ?? "")})
        guard values["state"]==state,values["error"]==nil,let code=values["code"],!code.isEmpty else {return nil}
        let issued=values["client_id"] ?? clientID ?? ""
        guard !issued.isEmpty,issued != "dynamic_agent_client",clientID==nil || clientID==issued else {return nil}
        return (code,issued)
    }
    static func validateClaims(_ claims:[String:Any],clientID:String,nonce:String?,now:Double=Date().timeIntervalSince1970)throws->OpenAIIdentity {
        let audiences=(claims["aud"] as? [String]) ?? (claims["aud"] as? String).map {[$0]} ?? []
        guard claims["iss"] as? String==issuer,audiences.contains(clientID),
              let exp=claims["exp"] as? Double,exp>now-5,
              let iat=claims["iat"] as? Double,iat<=now+5,
              let sub=claims["sub"] as? String,!sub.isEmpty else {throw EditError.invalid("تعذّر التحقق من هوية ChatGPT")}
        if audiences.count>1,claims["azp"] as? String != clientID {throw EditError.invalid("جمهور تسجيل الدخول غير صالح")}
        if let nbf=claims["nbf"] as? Double,nbf>now+5 {throw EditError.invalid("رمز الدخول غير صالح بعد")}
        if let nonce,claims["nonce"] as? String != nonce {throw EditError.invalid("فشل التحقق من جلسة الدخول")}
        return OpenAIIdentity(subject:sub,email:claims["email"] as? String ?? "ChatGPT")
    }
    static func verifyIDToken(_ token:String,jwks:Data,clientID:String,nonce:String?)throws->OpenAIIdentity {
        let parts=token.split(separator:".").map(String.init)
        guard parts.count==3,let headerData=decodeBase64URL(parts[0]),let body=decodeBase64URL(parts[1]),let signature=decodeBase64URL(parts[2]),
              let header=try JSONSerialization.jsonObject(with:headerData) as? [String:Any],header["alg"] as? String=="RS256",
              let kid=header["kid"] as? String,
              let keySet=try JSONSerialization.jsonObject(with:jwks) as? [String:Any],let keys=keySet["keys"] as? [[String:Any]],
              let jwk=keys.first(where:{$0["kid"] as? String==kid && $0["kty"] as? String=="RSA"}),
              let n=(jwk["n"] as? String).flatMap(decodeBase64URL),let e=(jwk["e"] as? String).flatMap(decodeBase64URL),n.count>=256,
              (jwk["alg"] as? String ?? "RS256")=="RS256",(jwk["use"] as? String ?? "sig")=="sig" else {throw EditError.invalid("توقيع هوية غير مدعوم")}
        let der=asn1(0x30,asn1Integer(n)+asn1Integer(e))
        let attributes:[String:Any]=[kSecAttrKeyType as String:kSecAttrKeyTypeRSA,kSecAttrKeyClass as String:kSecAttrKeyClassPublic]
        guard let key=SecKeyCreateWithData(der as CFData,attributes as CFDictionary,nil),
              SecKeyVerifySignature(key,.rsaSignatureMessagePKCS1v15SHA256,Data((parts[0]+"."+parts[1]).utf8) as CFData,signature as CFData,nil),
              let claims=try JSONSerialization.jsonObject(with:body) as? [String:Any] else {throw EditError.invalid("توقيع ChatGPT غير صالح")}
        return try validateClaims(claims,clientID:clientID,nonce:nonce)
    }
    private static func asn1Integer(_ bytes:Data)->Data {
        var clean=bytes
        while clean.count>1 && clean.first==0 {clean.removeFirst()}
        if let first=clean.first,first & 0x80 != 0 {clean.insert(0,at:0)}
        return asn1(0x02,clean)
    }
    private static func asn1(_ tag:UInt8,_ value:Data)->Data {
        var length=[UInt8]();var n=value.count
        if n<128 {length=[UInt8(n)]} else {while n>0 {length.insert(UInt8(n & 0xff),at:0);n >>= 8};length.insert(0x80|UInt8(length.count),at:0)}
        return Data([tag]+length)+value
    }
}
