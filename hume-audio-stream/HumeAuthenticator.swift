import Foundation

struct HumeAuthenticator {
    let apiKey: String
    let secretKey: String
    let host: String

    init(apiKey: String, secretKey: String, host: String = "api.hume.ai") {
        self.apiKey = apiKey
        self.secretKey = secretKey
        self.host = host
    }

    func fetchAccessToken(completion: @escaping (Result<String, Error>) -> Void) {
        let credentials = "\(apiKey):\(secretKey)"
        guard let credentialsData = credentials.data(using: .utf8) else {
            completion(.failure(NSError(domain: "AuthenticatorError", code: 0, userInfo: [NSLocalizedDescriptionKey: "Credentials encoding failed"])))
            return
        }

        let encodedCredentials = credentialsData.base64EncodedString()
        let url = URL(string: "https://\(host)/oauth2-cc/token")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Basic \(encodedCredentials)", forHTTPHeaderField: "Authorization")
        request.addValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = "grant_type=client_credentials".data(using: .utf8)

        let session = URLSession.shared
        let task = session.dataTask(with: request) { data, response, error in
            guard let data = data, error == nil else {
                completion(.failure(error ?? NSError(domain: "NetworkError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Network request failed"])))
                return
            }

            do {
                if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any], let accessToken = json["access_token"] as? String {
                    completion(.success(accessToken))
                } else {
                    throw NSError(domain: "AuthenticatorError", code: 2, userInfo: [NSLocalizedDescriptionKey: "Access token not found"])
                }
            } catch {
                completion(.failure(error))
            }
        }
        task.resume()
    }
}
