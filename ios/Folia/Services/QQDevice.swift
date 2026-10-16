import Foundation
import Security
// ios/Folia/Services/QQDevice.swift

struct QQDevice {
    var fields: [String: String]
    init(fields: [String: String]) {
        self.fields = fields
        if self.fields["androidId"] == nil {
            let id = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
            self.fields["androidId"] = String(id.prefix(16))
            self.fields["openUdid"] = id
            self.fields["imei"] = "\(Int64.random(in: 100000000000000...999999999999999))"
            self.fields["fingerprint"] = "xiaomi/iarim/sagit:10/eomam.200122.001/\(Int.random(in: 1000000...9999999)):user/release-keys"
        }
    }
    func comm(credential: [String: String], overrides: [String: Any] = [:]) -> [String: Any] {
        var body: [String: Any] = ["ct": 11, "cv": 14090008, "v": 14090008, "chid": "10003505", "tmeAppID": "qqmusic",
            "QIMEI": fields["qimei"] ?? "", "QIMEI36": fields["qimei36"] ?? "", "OpenUDID": fields["openUdid"] ?? "",
            "udid": fields["openUdid"] ?? "", "OpenUDID2": fields["openUdid"] ?? "", "aid": fields["androidId"] ?? "",
            "os_ver": "10", "phonetype": "MI 6", "devicelevel": "29", "newdevicelevel": "29", "rom": fields["fingerprint"] ?? ""]
        for key in ["uid", "sid"] { if let value = fields[key] { body[key] = value } }
        if let key = credential["musickey"] {
            body["qq"] = credential["str_musicid"] ?? credential["musicid"] ?? "0"
            body["authst"] = key
            body["tmeLoginType"] = Int(credential["loginType"] ?? "6") ?? 6
        }
        body.merge(overrides) { _, new in new }
        return body
    }
    // Port of qq-music-api 3.3.1 Android QIMEI envelope; generated identifiers are synthetic.
    func qimeiRequest() throws -> URLRequest {
        let now = Date(), timestamp = String(Int(now.timeIntervalSince1970))
        let key = String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(16)).lowercased()
        let nonce = String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(16)).lowercased()
        let formatter = ISO8601DateFormatter()
        let iso = formatter.string(from: now)
        let month = String(iso.prefix(7)) + "-01"
        let dateKeys: Set<Int> = [1,2,13,14,17,18,21,22,25,26,29,30,33,34,37,38]
        let first = Int.random(in: 100000...999999), second = Int.random(in: 100000000...999999999)
        let beacon = (1...40).map { index -> String in
            let value: String
            if dateKeys.contains(index) { value = "\(month)\(first).\(second)" }
            else if index == 3 { value = "0000000000000000" }
            else if index == 4 { value = String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(16)).replacingOccurrences(of: "0", with: "1") }
            else { value = String(Int.random(in: 0..<10000)) }
            return "k\(index):\(value)"
        }.joined(separator: ";") + ";"
        let reserved: [String: String] = ["harmony":"0", "clone":"0", "containe":"", "oz":"UhYmelwouA+V2nPWbOvLTgN2/m8jwGB+yUB5v9tysQg=",
            "oo":"Xecjt+9S1+f8Pz2VLSxgpw==", "kelong":"0", "uptimes":String(iso.prefix(19)).replacingOccurrences(of:"T",with:" "),
            "multiUser":"0", "bod":"Xiaomi", "dv":"sagit", "firstLevel":"", "manufact":"Xiaomi", "name":"MI 6", "host":"se.infra", "kernel":"Linux 5.4.0-54-generic (android-build@google.com)"]
        let payload: [String: Any] = ["androidId":fields["androidId"] ?? "", "platformId":1, "appKey":"0AND0HD6FE4HY80F", "appVersion":"14.9.0.8",
            "beaconIdSrc":beacon, "brand":"Xiaomi", "channelId":"10003505", "cid":"", "imei":fields["imei"] ?? "", "imsi":"", "mac":"", "model":"MI 6",
            "networkType":"unknown", "oaid":"", "osVersion":"Android 10,level 29", "qimei":"", "qimei36":"", "sdkVersion":"1.2.13.6",
            "targetSdkVersion":"33", "audit":"", "userId":"{}", "packageId":"com.tencent.qqmusic", "deviceType":"Phone", "sdkName":"",
            "reserved":String(decoding:try JSONSerialization.data(withJSONObject:reserved),as:UTF8.self)]
        let json = String(decoding:try JSONSerialization.data(withJSONObject:payload),as:UTF8.self)
        let encrypted = try ProtocolCrypto.aes(json,key:key,iv:key).base64EncodedString()
        let spki = Data(base64Encoded:"MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQDEIxgwoutfwoJxcGQeedgP7FG9qaIuS0qzfR8gWkrkTZKM2iWHn2ajQpBRZjMSoSf6+KJGvar2ORhBfpDXyVtZCKpqLQ+FLkpncClKVIrBwv6PHyUvuCb0rIarmgDnzkfQAqVufEtR64iazGDKatvJ9y6B9NMbHddGSAUmRTCrHQIDAQAB")!
        guard let rsa = SecKeyCreateWithData(spki.dropFirst(22) as CFData,[kSecAttrKeyType:kSecAttrKeyTypeRSA,kSecAttrKeyClass:kSecAttrKeyClassPublic,kSecAttrKeySizeInBits:1024] as CFDictionary,nil),
              let wrapped = SecKeyCreateEncryptedData(rsa,.rsaEncryptionPKCS1,Data(key.utf8) as CFData,nil) as Data? else { throw MusicError.invalidResponse }
        let rsaKey = wrapped.base64EncodedString(), extra = "{\"appKey\":\"0AND0HD6FE4HY80F\"}"
        let body: [String:Any] = ["app":0,"os":1,"qimeiParams":["key":rsaKey,"params":encrypted,"time":timestamp,"nonce":nonce,
            "sign":ProtocolCrypto.md5(rsaKey + encrypted + timestamp + "000" + nonce + "ZdJqM15EeO2zWc08" + extra),"extra":extra]]
        var request = URLRequest(url:URL(string:"https://api.tencentmusic.com/tme/trpc/proxy")!)
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject:body)
        for (name,value) in ["method":"GetQimei","service":"trpc.tme_datasvr.qimeiproxy.QimeiProxy","appid":"qimei_qq_android",
            "sign":ProtocolCrypto.md5("qimei_qq_androidpzAuCmaFAaFaHrdakPjLIEqKrGnSOOvH" + timestamp),"User-Agent":"QQMusic","timestamp":timestamp,"Content-Type":"application/json"] {
            request.setValue(value,forHTTPHeaderField:name)
        }
        return request
    }
}
