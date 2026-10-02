import XCTest
import Security
@testable import VidioiCore

final class ConnectionTests:XCTestCase {
    func testCallbackBindsStatePortAndIssuedClient() {
        let redirect=URL(string:"http://127.0.0.1:12345/auth/callback")!
        let good=URL(string:"http://127.0.0.1:12345/auth/callback?code=abc&state=state&client_id=oaiapp_test")!
        XCTAssertNotNil(OAuthContract.callback(good,redirect:redirect,state:"state",clientID:nil))
        XCTAssertNil(OAuthContract.callback(good,redirect:redirect,state:"wrong",clientID:nil))
        XCTAssertNil(OAuthContract.callback(good,redirect:redirect,state:"state",clientID:"other"))
        XCTAssertNil(OAuthContract.callback(URL(string:good.absoluteString.replacingOccurrences(of:"12345",with:"12346"))!,redirect:redirect,state:"state",clientID:nil))
        XCTAssertNil(OAuthContract.callback(URL(string:good.absoluteString+"&state=other")!,redirect:redirect,state:"state",clientID:nil))
        XCTAssertNil(OAuthContract.callback(URL(string:good.absoluteString+"&error=access_denied")!,redirect:redirect,state:"state",clientID:nil))
    }
    func testReturningCallbackAllowsOmittedClientButNotDynamic() {
        let redirect=URL(string:"http://127.0.0.1:12345/auth/callback")!
        let url=URL(string:redirect.absoluteString+"?code=abc&state=s")!
        XCTAssertNotNil(OAuthContract.callback(url,redirect:redirect,state:"s",clientID:"oaiapp_issued"))
        XCTAssertNil(OAuthContract.callback(url,redirect:redirect,state:"s",clientID:nil))
        XCTAssertNil(OAuthContract.callback(url,redirect:redirect,state:"s",clientID:"dynamic_agent_client"))
    }
    func testIdentityRejectsWrongIssuerAudienceExpiryAndNonce() throws {
        let good:[String:Any]=["iss":OAuthContract.issuer,"aud":"client","exp":200.0,"iat":50.0,"sub":"subject","nonce":"n"]
        XCTAssertEqual(try OAuthContract.validateClaims(good,clientID:"client",nonce:"n",now:100).subject,"subject")
        for (field,value) in [("iss","evil" as Any),("aud","other" as Any),("exp",80.0 as Any),("nonce","other" as Any),("iat",200.0 as Any)] {
            var bad=good;bad[field]=value;XCTAssertThrowsError(try OAuthContract.validateClaims(bad,clientID:"client",nonce:"n",now:100))
        }
    }
    func testUnsignedAndForgedIDTokensRejected() throws {
        let header=OAuthContract.base64URL(Data(#"{"alg":"none","kid":"k"}"#.utf8))
        let body=OAuthContract.base64URL(Data(#"{"sub":"attacker"}"#.utf8))
        XCTAssertThrowsError(try OAuthContract.verifyIDToken(header+"."+body+".invalid",jwks:Data(#"{"keys":[]}"#.utf8),clientID:"client",nonce:"n"))
    }
    func testResponsesRequestHonorsChatGPTPlanContract() throws {
        let data=try AIContract.request(prompt:"Add a title",project:EditProject(),model:"available-model")
        let json=try XCTUnwrap(JSONSerialization.jsonObject(with:data) as? [String:Any])
        XCTAssertEqual(json["stream"] as? Bool,true);XCTAssertEqual(json["store"] as? Bool,false)
        XCTAssertNotNil(json["input"] as? [[String:Any]])
        XCTAssertNil(json["max_output_tokens"]);XCTAssertNil(json["previous_response_id"]);XCTAssertNil(json["temperature"])
    }
    func testStreamRequiresCompletedAndRejectsLateFailure() throws {
        var stream=ResponseAccumulator()
        let text=#"{"summary":"ok","operations":[]}"#
        let event:[String:Any]=["type":"response.output_text.delta","delta":text]
        try stream.consume("data: "+String(decoding:JSONSerialization.data(withJSONObject:event),as:UTF8.self))
        XCTAssertThrowsError(try stream.plan(for:EditProject()))
        XCTAssertThrowsError(try stream.consume(#"data: {"type":"response.failed"}"#))
        try stream.consume(#"data: {"type":"response.completed","response":{"status":"completed","output":[]}}"#)
        XCTAssertEqual(try stream.plan(for:EditProject()).summary,"ok")
    }
    func testRefusalNeverBecomesAPlan() throws {
        var stream=ResponseAccumulator()
        try stream.consume(#"data: {"type":"response.completed","response":{"status":"completed","output":[{"type":"message","content":[{"type":"refusal"}]}]}}"#)
        XCTAssertThrowsError(try stream.plan(for:EditProject()))
    }
}

extension ConnectionTests {
    func testValidRSAIdentityAndTamperedSignature() throws {
        let token = "eyJhbGciOiJSUzI1NiIsImtpZCI6InRlc3Qta2V5In0.eyJpc3MiOiJodHRwczovL2F1dGgub3BlbmFpLmNvbSIsImF1ZCI6InRlc3QtY2xpZW50Iiwic3ViIjoidmVyaWZpZWQtdXNlciIsImVtYWlsIjoidGVzdEBleGFtcGxlLmludmFsaWQiLCJub25jZSI6InRlc3Qtbm9uY2UiLCJpYXQiOjEwMDAwMDAwMDAsImV4cCI6NDEwMjQ0NDgwMH0.OwyLks-cQfQ8E1r0w_l0rdKulzpUtbroWHdrUmL73iQrIKA1RM6bDJnUiZgGAtGXJ3_dwXiGq5DwajGnNC8aLMFRg5tc38jl2dS8oItmpbT8xIta19lf5bY0lP6ay72qpnNW27jkSVm-ubKE0IEPsqkKfDIkFCQM-CF3A8EN9nETskaiXiwjKjrRcF7iTA7OWNt2EO32lN1XYD7deRyfW0mSI3Urtf1UJi4X6D6psG0qtKzjzW-ozWmcgRyqNUZpR63-1poEIUHvSRXZp-bbL5xrxBImCwBKfdpZR6e868eHnt8JKPyDsLvWQUsQMtHSeXS_UTTJw8CcLLwspn0B2g"
        let jwks = Data(#"{"keys":[{"kty":"RSA","kid":"test-key","alg":"RS256","use":"sig","n":"nI2ZU1IDdtALMkfWGDWtgZ7zJhAtQi66STe-i8UmuY4VBtiwjAYpg03Dn7Cr0wNmw-BzH0ddlfXayVLMxpCUXd6989WH5XsTlToAEAns5wRSWtJl_hNInt7xSGKCb-ma8YEck4zQqS8yJGTBcA7-_-JbZqBqTe9w89uWNdlXt0KkPGJJ3z4BkOP0oZgid2H4_VsO_QRWvWqqIxWlPAzzCFQady1ErLgk_iJ65O97m4cmMjk4iALeCY9wTGmhjzUcTBqHBV93oUtYw3ILTlbNpm83-7sO92n72x5v9oE5Gekd4Ta0jrWvFKhVqiWUwfgvXEtijk0Lrx31_8kikKxFRQ","e":"AQAB"}]}"#.utf8)
        XCTAssertEqual(try OAuthContract.verifyIDToken(token,jwks:jwks,clientID:"test-client",nonce:"test-nonce").subject,"verified-user")
        var parts=token.split(separator:".").map(String.init)
        parts[1]=OAuthContract.base64URL(Data(#"{"sub":"attacker"}"#.utf8))
        XCTAssertThrowsError(try OAuthContract.verifyIDToken(parts.joined(separator:"."),jwks:jwks,clientID:"test-client",nonce:"test-nonce"))
    }
}
