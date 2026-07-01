import Foundation

/// Builds standard `otpauth://totp/...` URIs for exporting accounts as QR codes.
enum OTPAuthURIBuilder {

    static func buildURI(for account: OTPAccount, secret: Data) -> String {
        let secretBase32 = Base32.encode(secret)

        let pathLabel: String
        if !account.issuer.isEmpty && !account.accountName.isEmpty {
            pathLabel = "\(account.issuer):\(account.accountName)"
        } else if !account.accountName.isEmpty {
            pathLabel = account.accountName
        } else {
            pathLabel = account.issuer
        }

        var components = URLComponents()
        components.scheme = "otpauth"
        components.host = "totp"
        components.percentEncodedPath = "/" + percentEncode(pathLabel)

        var queryItems = [URLQueryItem(name: "secret", value: secretBase32)]

        if !account.issuer.isEmpty {
            queryItems.append(URLQueryItem(name: "issuer", value: account.issuer))
        }
        if account.algorithm != .sha1 {
            queryItems.append(URLQueryItem(name: "algorithm", value: account.algorithm.rawValue))
        }
        if account.digits != 6 {
            queryItems.append(URLQueryItem(name: "digits", value: String(account.digits)))
        }
        if account.period != 30 {
            queryItems.append(URLQueryItem(name: "period", value: String(account.period)))
        }

        components.queryItems = queryItems
        return components.string ?? "otpauth://totp/\(percentEncode(pathLabel))?secret=\(secretBase32)"
    }

    private static func percentEncode(_ value: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}
