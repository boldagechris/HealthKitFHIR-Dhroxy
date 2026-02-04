import SwiftUI

struct ContentView: View {
    @StateObject private var healthKitManager = HealthKitManager()
    @StateObject private var apiService = APIService()

    @State private var healthData: [HealthDataPoint] = []
    @State private var isLoading = false
    @State private var selectedDays = 7
    @State private var showSettings = false
    @State private var serverStatus: Bool?

    private let deviceId = UIDevice.current.identifierForVendor?.uuidString ?? "unknown"

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Status header
                statusHeader

                if !healthKitManager.isAuthorized {
                    authorizationView
                } else {
                    dataListView
                }
            }
            .navigationTitle("HealthKit Sync")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gear")
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                settingsView
            }
        }
        .task {
            await checkServerStatus()
        }
    }

    // MARK: - Views

    private var statusHeader: some View {
        HStack {
            Circle()
                .fill(serverStatusColor)
                .frame(width: 10, height: 10)
            Text(serverStatusText)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            if let result = apiService.lastSyncResult {
                Text("Sidst synk: \(result.timestamp.formatted(date: .omitted, time: .shortened))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(.systemGray6))
    }

    private var authorizationView: some View {
        VStack(spacing: 20) {
            Image(systemName: "heart.text.square")
                .font(.system(size: 80))
                .foregroundColor(.red)

            Text("HealthKit Adgang")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Denne app har brug for adgang til dine sundhedsdata for at synkronisere dem til din sundhedsagent.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal)

            if let error = healthKitManager.lastError {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
                    .padding()
            }

            Button {
                Task {
                    await healthKitManager.requestAuthorization()
                    if healthKitManager.isAuthorized {
                        await loadHealthData()
                    }
                }
            } label: {
                Label("Giv Adgang", systemImage: "checkmark.shield")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            .padding(.horizontal, 40)
        }
        .padding()
    }

    private var dataListView: some View {
        VStack {
            // Controls
            HStack {
                Picker("Periode", selection: $selectedDays) {
                    Text("1 dag").tag(1)
                    Text("7 dage").tag(7)
                    Text("30 dage").tag(30)
                }
                .pickerStyle(.segmented)
                .onChange(of: selectedDays) { _, _ in
                    Task { await loadHealthData() }
                }

                Button {
                    Task { await loadHealthData() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(isLoading)
            }
            .padding()

            if isLoading {
                ProgressView("Henter data...")
                    .padding()
            } else if healthData.isEmpty {
                ContentUnavailableView(
                    "Ingen data",
                    systemImage: "heart.slash",
                    description: Text("Ingen sundhedsdata fundet for de sidste \(selectedDays) dage")
                )
            } else {
                List {
                    Section {
                        ForEach(groupedData.keys.sorted().reversed(), id: \.self) { date in
                            DisclosureGroup {
                                ForEach(groupedData[date] ?? []) { dataPoint in
                                    dataRow(dataPoint)
                                }
                            } label: {
                                HStack {
                                    Text(date.formatted(date: .abbreviated, time: .omitted))
                                        .fontWeight(.medium)
                                    Spacer()
                                    Text("\(groupedData[date]?.count ?? 0) målinger")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    } header: {
                        Text("\(healthData.count) datapunkter")
                    }
                }
            }

            // Sync button
            syncButton
        }
    }

    private func dataRow(_ dataPoint: HealthDataPoint) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(dataPoint.displayName)
                    .font(.subheadline)
                Text(dataPoint.date.formatted(date: .omitted, time: .shortened))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Text(dataPoint.formattedValue)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.blue)
        }
        .padding(.vertical, 2)
    }

    private var syncButton: some View {
        VStack {
            Button {
                Task { await syncData() }
            } label: {
                HStack {
                    if apiService.isSyncing {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    } else {
                        Image(systemName: "arrow.up.circle.fill")
                    }
                    Text(apiService.isSyncing ? "Synkroniserer..." : "Synkroniser til Server")
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
                .background(healthData.isEmpty ? Color.gray : Color.blue)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .disabled(healthData.isEmpty || apiService.isSyncing)
            .padding()

            if let result = apiService.lastSyncResult {
                HStack {
                    Image(systemName: result.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(result.success ? .green : .red)
                    Text(result.message)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
        }
    }

    private var settingsView: some View {
        NavigationStack {
            Form {
                Section("Server") {
                    TextField("Server URL", text: $apiService.serverURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)

                    Button("Test forbindelse") {
                        Task { await checkServerStatus() }
                    }

                    HStack {
                        Text("Status")
                        Spacer()
                        if let status = serverStatus {
                            Image(systemName: status ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundColor(status ? .green : .red)
                            Text(status ? "Forbundet" : "Ikke forbundet")
                        } else {
                            Text("Ukendt")
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Section("Enhed") {
                    LabeledContent("Device ID", value: String(deviceId.prefix(8)) + "...")
                    LabeledContent("Model", value: UIDevice.current.model)
                    LabeledContent("iOS", value: UIDevice.current.systemVersion)
                }

                Section("Om") {
                    LabeledContent("Version", value: "1.0.0")
                    Text("Synkroniserer dine HealthKit data som FHIR R4 til din sundhedsagent backend.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Indstillinger")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Luk") {
                        showSettings = false
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private var groupedData: [Date: [HealthDataPoint]] {
        Dictionary(grouping: healthData) { dataPoint in
            Calendar.current.startOfDay(for: dataPoint.date)
        }
    }

    private var serverStatusColor: Color {
        guard let status = serverStatus else { return .gray }
        return status ? .green : .red
    }

    private var serverStatusText: String {
        guard let status = serverStatus else { return "Tjekker server..." }
        return status ? "Server online" : "Server offline"
    }

    // MARK: - Actions

    private func loadHealthData() async {
        isLoading = true
        healthData = await healthKitManager.fetchHealthData(days: selectedDays)
        isLoading = false
    }

    private func syncData() async {
        await apiService.syncHealthData(healthData, deviceId: deviceId)
    }

    private func checkServerStatus() async {
        serverStatus = await apiService.checkServerStatus()
    }
}

#Preview {
    ContentView()
}
