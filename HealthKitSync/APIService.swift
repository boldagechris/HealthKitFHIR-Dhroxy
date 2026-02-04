import Foundation

/// Service for sending FHIR data to the dhroxy backend
class APIService: ObservableObject {
    @Published var isSyncing = false
    @Published var lastSyncResult: SyncResult?
    @Published var serverURL: String = "http://10.0.0.100:8080"

    struct SyncResult {
        let success: Bool
        let message: String
        let resourcesAccepted: Int
        let resourcesRejected: Int
        let timestamp: Date
    }

    /// Send health data to dhroxy server
    func syncHealthData(_ dataPoints: [HealthDataPoint], deviceId: String) async {
        await MainActor.run {
            isSyncing = true
        }

        defer {
            Task { @MainActor in
                isSyncing = false
            }
        }

        let bundle = FHIRConverter.toFHIRBundle(dataPoints: dataPoints)

        guard let url = URL(string: "\(serverURL)/api/healthkit/fhir") else {
            await MainActor.run {
                lastSyncResult = SyncResult(
                    success: false,
                    message: "Ugyldig server URL",
                    resourcesAccepted: 0,
                    resourcesRejected: 0,
                    timestamp: Date()
                )
            }
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/fhir+json", forHTTPHeaderField: "Content-Type")
        request.setValue(deviceId, forHTTPHeaderField: "X-Device-Id")
        request.timeoutInterval = 30

        do {
            let jsonData = try JSONSerialization.data(withJSONObject: bundle, options: [])
            request.httpBody = jsonData

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.invalidResponse
            }

            if httpResponse.statusCode == 200 || httpResponse.statusCode == 206 {
                // Parse OperationOutcome response
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let issues = json["issue"] as? [[String: Any]],
                   let firstIssue = issues.first,
                   let diagnostics = firstIssue["diagnostics"] as? String {

                    // Parse "Processed X resources: Y accepted, Z rejected"
                    let accepted = extractNumber(from: diagnostics, pattern: "(\\d+) accepted") ?? dataPoints.count
                    let rejected = extractNumber(from: diagnostics, pattern: "(\\d+) rejected") ?? 0

                    await MainActor.run {
                        lastSyncResult = SyncResult(
                            success: httpResponse.statusCode == 200,
                            message: diagnostics,
                            resourcesAccepted: accepted,
                            resourcesRejected: rejected,
                            timestamp: Date()
                        )
                    }
                } else {
                    await MainActor.run {
                        lastSyncResult = SyncResult(
                            success: true,
                            message: "Synkronisering gennemført",
                            resourcesAccepted: dataPoints.count,
                            resourcesRejected: 0,
                            timestamp: Date()
                        )
                    }
                }
            } else {
                let errorMessage = String(data: data, encoding: .utf8) ?? "Ukendt fejl"
                await MainActor.run {
                    lastSyncResult = SyncResult(
                        success: false,
                        message: "Server fejl (\(httpResponse.statusCode)): \(errorMessage)",
                        resourcesAccepted: 0,
                        resourcesRejected: dataPoints.count,
                        timestamp: Date()
                    )
                }
            }
        } catch {
            await MainActor.run {
                lastSyncResult = SyncResult(
                    success: false,
                    message: "Netværksfejl: \(error.localizedDescription)",
                    resourcesAccepted: 0,
                    resourcesRejected: dataPoints.count,
                    timestamp: Date()
                )
            }
        }
    }

    /// Check if server is reachable
    func checkServerStatus() async -> Bool {
        guard let url = URL(string: "\(serverURL)/api/healthkit/status") else {
            return false
        }

        do {
            let (_, response) = try await URLSession.shared.data(from: url)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    private func extractNumber(from string: String, pattern: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: string, range: NSRange(string.startIndex..., in: string)),
              let range = Range(match.range(at: 1), in: string) else {
            return nil
        }
        return Int(string[range])
    }

    enum APIError: Error {
        case invalidResponse
        case serverError(Int)
    }
}
