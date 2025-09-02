import Foundation

struct WHOOPManager {
    static let shared = WHOOPManager()

    private init() {}

    // WHOOP API Configuration
    private let baseURL = "https://api.prod.whoop.com"
    private let clientID: String
    private let redirectURI = "dosetap://oauth/callback"
    private let scope = "read:sleep read:cycles read:recovery"

    private init() {
        // Load client ID from Config.plist
        if let path = Bundle.main.path(forResource: "Config", ofType: "plist"),
           let dict = NSDictionary(contentsOfFile: path) as? [String: Any],
           let clientID = dict["WHOOP_CLIENT_ID"] as? String {
            self.clientID = clientID
        } else {
            self.clientID = "your_client_id_here" // Fallback
            print("Warning: WHOOP_CLIENT_ID not found in Config.plist")
        }
    }

    private var accessToken: String? {
        get { UserDefaults.standard.string(forKey: "whoop_access_token") }
        set { UserDefaults.standard.set(newValue, forKey: "whoop_access_token") }
    }

    // Start OAuth flow
    func authorize() {
        let authURL = "\(baseURL)/oauth/oauth2/auth?response_type=code&client_id=\(clientID)&redirect_uri=\(redirectURI)&scope=\(scope)"
        if let url = URL(string: authURL) {
            UIApplication.shared.open(url)
        }
    }

    // Handle OAuth callback
    func handleCallback(url: URL) {
        guard url.scheme == "dosetap", url.host == "oauth", url.path == "/callback",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value else { return }

        exchangeCodeForToken(code: code)
    }

    private func exchangeCodeForToken(code: String) {
        let tokenURL = "\(baseURL)/oauth/oauth2/token"
        var request = URLRequest(url: URL(string: tokenURL)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = "grant_type=authorization_code&code=\(code)&redirect_uri=\(redirectURI)&client_id=\(clientID)"
        request.httpBody = body.data(using: .utf8)

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let data = data,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let token = json["access_token"] as? String {
                self.accessToken = token
                print("WHOOP token obtained")
            }
        }.resume()
    }

    // Fetch sleep history
    func fetchSleepHistory() async -> [NightSummary] {
        guard let token = accessToken else { return [] }

        let sleepURL = "\(baseURL)/v2/activity/sleep?limit=30"
        var request = URLRequest(url: URL(string: sleepURL)!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            if let records = json?["records"] as? [[String: Any]] {
                return parseSleepRecords(records)
            }
        } catch {
            print("WHOOP sleep fetch error: \(error)")
        }
        return []
    }

    private func parseSleepRecords(_ records: [[String: Any]]) -> [NightSummary] {
        var summaries: [NightSummary] = []
        for record in records {
            if let start = record["start"] as? String,
               let end = record["end"] as? String,
               let stageSummary = record["stage_summary"] as? [String: Any],
               let light = stageSummary["light"] as? [String: Any],
               let deep = stageSummary["deep"] as? [String: Any],
               let rem = stageSummary["rem"] as? [String: Any],
               let awake = stageSummary["awake"] as? [String: Any] {
                
                // Calculate TTFW: time from start to first awake
                if let awakeStart = awake["start"] as? String,
                   let startDate = ISO8601DateFormatter().date(from: start),
                   let awakeDate = ISO8601DateFormatter().date(from: awakeStart) {
                    let minutes = Int(awakeDate.timeIntervalSince(startDate) / 60)
                    if minutes >= 150 && minutes <= 240 {
                        summaries.append(NightSummary(minutesToFirstWake: minutes, disturbancesScore: nil))
                    }
                }
            }
        }
        return summaries
    }
}
