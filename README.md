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
- A FHIR R4 compatible server (e.g., [dhroxy](https://github.com/jkiddo/dhroxy))

## Installation

1. Clone the repository:
```bash
git clone https://github.com/boldagechris/HealthKitSync.git
```

2. Open `HealthKitSync.xcodeproj` in Xcode

3. Configure your server URL in `APIService.swift`:
```swift
@Published var serverURL: String = "http://YOUR_SERVER_IP:8080"
```

4. Build and run on a physical iOS device (HealthKit is not available in the simulator)

## Usage

1. Launch the app and grant HealthKit permissions when prompted
2. Select the number of days of data to sync
3. Tap "Sync" to send your health data to the configured FHIR server

## Server Compatibility

This app is designed to work with [dhroxy](https://github.com/jkiddo/dhroxy) with the Apple HealthKit integration enabled. The server provides the following endpoints:

- `POST /api/healthkit/fhir` - Receives FHIR Bundle with health observations
- `GET /api/healthkit/observations` - Retrieves stored observations
- `GET /api/healthkit/status` - Server status and statistics

## Privacy

All health data is read locally from HealthKit and transmitted directly to your configured server. No data is sent to third parties.

## License

MIT License
