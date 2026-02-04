# HealthKitSync

iOS app for syncing Apple HealthKit data to FHIR-compatible servers.

## Features

- **HealthKit Integration**: Reads health data directly from Apple HealthKit
- **FHIR R4 Compliance**: Converts HealthKit data to FHIR R4 Observation resources
- **Configurable Server**: Connect to any FHIR-compatible backend
- **Multiple Data Types**: Supports a wide range of health metrics

## Supported Health Data Types

### Vital Signs
- Heart Rate
- Blood Pressure (Systolic/Diastolic)
- Oxygen Saturation
- Respiratory Rate
- Body Temperature

### Activity
- Step Count
- Distance (Walking/Running)
- Active Energy Burned
- Flights Climbed

### Body Measurements
- Weight
- Height
- BMI

### Other
- Sleep Analysis
- Blood Glucose

## Requirements

- iOS 14.0+
- Xcode 14.0+
- Swift 5.0+
- A physical iOS device (HealthKit is not available in the simulator)
- A FHIR R4 compatible server (e.g., [dhroxy](https://github.com/jkiddo/dhroxy))

## Setting Up Your iOS Device for Development

Since HealthKit requires a physical device, you'll need to enable Developer Mode on your iPhone:

### Enable Developer Mode (iOS 16+)

1. Connect your iPhone to your Mac and open Xcode
2. On your iPhone, go to **Settings** > **Privacy & Security**
3. Scroll down and tap **Developer Mode**
4. Toggle **Developer Mode** on
5. Your device will prompt you to restart - tap **Restart**
6. After restart, tap **Turn On** when prompted and enter your passcode

### Trust Your Developer Certificate

1. Open Xcode and connect your iPhone
2. Go to **Window** > **Devices and Simulators**
3. Select your device and wait for Xcode to prepare it for development
4. On your iPhone, go to **Settings** > **General** > **VPN & Device Management**
5. Under "Developer App", tap your Apple ID and tap **Trust**

## Installation

1. Clone the repository:
```bash
git clone https://github.com/boldagechris/HealthKitSync.git
```

2. Open `HealthKitSync.xcodeproj` in Xcode

3. Select your development team in **Signing & Capabilities**

4. Build and run on your physical iOS device

## Configuring dhroxy Server Connection

This app is designed to work with [dhroxy](https://github.com/jkiddo/dhroxy) - a FHIR proxy server for Danish health data.

### 1. Start the dhroxy server

```bash
cd dhroxy
./gradlew bootJar
java -jar build/libs/dhroxy-0.1.0-SNAPSHOT.jar
```

The server will start on port 8080 by default.

### 2. Find your Mac's IP address

```bash
ipconfig getifaddr en0
```

This will output something like `192.168.1.100`.

### 3. Configure the iOS app

Update the server URL in `HealthKitSync/APIService.swift`:

```swift
@Published var serverURL: String = "http://YOUR_MAC_IP:8080"
```

Replace `YOUR_MAC_IP` with your actual IP address (e.g., `http://192.168.1.100:8080`).

### 4. Network Requirements

- Your iPhone and Mac must be on the **same Wi-Fi network**
- The app uses HTTP (not HTTPS) for local development. The `Info.plist` includes the necessary App Transport Security exceptions for local networking.

### 5. Verify Connection

Once the server is running, you can verify the HealthKit endpoints are active:

```bash
curl http://localhost:8080/api/healthkit/status
```

You should see:
```json
{"status":"operational","resourceCounts":{},"totalResources":0,"supportedResourceTypes":["Observation","DiagnosticReport","Condition","MedicationStatement","Immunization","AllergyIntolerance","Procedure"]}
```

## Usage

1. Launch the app and grant HealthKit permissions when prompted
2. Select the number of days of data to sync
3. Tap "Sync" to send your health data to the configured FHIR server
4. View synced data via the dhroxy API:

```bash
curl http://localhost:8080/api/healthkit/observations
```

## dhroxy Server Endpoints

The dhroxy server with HealthKit integration provides:

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/healthkit/fhir` | POST | Receives FHIR Bundle with health observations |
| `/api/healthkit/submit` | POST | Custom submission format with device metadata |
| `/api/healthkit/observations` | GET | Retrieves stored observations |
| `/api/healthkit/status` | GET | Server status and statistics |
| `/api/healthkit/metadata` | GET | FHIR CapabilityStatement |

## Troubleshooting

### "Server Offline" Error

1. Verify dhroxy is running: `curl http://localhost:8080/api/healthkit/status`
2. Check your Mac's firewall settings allow incoming connections on port 8080
3. Ensure both devices are on the same network
4. Verify you're using the correct IP address (not `localhost`)

### HealthKit Permission Denied

1. Go to **Settings** > **Health** > **Data Access & Devices**
2. Find HealthKitSync and enable all data types

### Build Errors in Xcode

1. Ensure you have a valid Apple Developer account
2. Check that HealthKit capability is enabled in Signing & Capabilities
3. Clean build folder: **Product** > **Clean Build Folder**

## Privacy

All health data is read locally from HealthKit and transmitted directly to your configured server. No data is sent to third parties.

## License

MIT License
