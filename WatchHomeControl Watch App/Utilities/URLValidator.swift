import Foundation

/// Validates user-entered Base_URL strings for the setup flow.
///
/// Accepts only syntactically valid absolute `http`/`https` URLs that carry a
/// host. Any string lacking a scheme, lacking a host, or using a non-http(s)
/// scheme is rejected with ``SetupError/invalidURL`` (Req 1.8, Property 14).
enum URLValidator {
    /// Returns the parsed `URL` for a valid absolute http(s) URL with a host,
    /// otherwise `.failure(.invalidURL)`.
    static func validate(_ raw: String) -> Result<URL, SetupError> {
        guard let components = URLComponents(string: raw) else {
            return .failure(.invalidURL)
        }

        // Scheme must be present and http/https (case-insensitive).
        guard let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return .failure(.invalidURL)
        }

        // A host must be present and non-empty.
        guard let host = components.host, !host.isEmpty else {
            return .failure(.invalidURL)
        }

        guard let url = components.url else {
            return .failure(.invalidURL)
        }

        return .success(url)
    }
}
