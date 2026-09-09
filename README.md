# Flutter Boilerplate 🚀

![Flutter](https://img.shields.io/badge/Flutter-%2302569B.svg?style=for-the-badge&logo=Flutter&logoColor=white)
![Dart](https://img.shields.io/badge/dart-%230175C2.svg?style=for-the-badge&logo=dart&logoColor=white)
![License](https://img.shields.io/badge/license-MIT-blue.svg?style=for-the-badge)
![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg?style=for-the-badge)

A robust and scalable Flutter Boilerplate designed to jumpstart your mobile application development. This project comes pre-configured with essential libraries, a clean architecture, and best practices to save you time and effort.

---

## ✨ Features

*   **State Management**: Built with [Provider](https://pub.dev/packages/provider) for efficient and scalable state management.
*   **Networking**: Powerful HTTP client using [Dio](https://pub.dev/packages/dio) with interceptors and error handling.
*   **Environment Management**: Ready-to-use Flavors schemes (**Dev**, **Stage**, **Prod**) for different environments.
*   **Dependency Injection**: Decoupled architecture using [GetIt](https://pub.dev/packages/get_it).
*   **Local Storage**: [Shared Preferences](https://pub.dev/packages/shared_preferences) for persistent data storage.
*   **Code Generation**: Automated JSON serialization and model generation using `json_serializable` and `build_runner`.
*   **Utilities**:
    *   Connectivity checks with `connectivity_plus`.
    *   Media handling with `image_picker` and `file_picker`.
    *   Device information via `device_info_plus`.
*   **Linting**: strict linting rules using `flutter_lints` for code quality.

---

## 📂 Project Structure

The project follows a clean separation of concerns:

```
lib/
├── dev/                 # Development environment entry point
├── prod/                # Production environment entry point
├── stage/               # Staging environment entry point
└── src/
    ├── apis/            # Network data sources and API clients
    ├── base/            # Base helper classes, mixins, and core logic
    ├── controllers/     # Business logic and view controllers
    ├── models/          # Data models
    ├── providers/       # State providers
    ├── ui/              # Screens, pages, and UI components
    └── widgets/         # Reusable common widgets
    └── main.dart        # Main app entry logic
```

---

## 🛠 Getting Started

## Prerequisites

| Dependency | Version    |
| ---------- | ---------- |
| **Flutter** | `v3.38.4` |
| **Dart** | `>=3.10.0 < 4.0.0` |


### Installation

1.  **Clone the repository**:
    ```bash
    git clone https://github.com/your-username/flutter-boilerplate.git
    cd flutter-boilerplate
    ```

2.  **Install Dependencies**:
    ```bash
    flutter pub get
    ```

3.  **Generate Code** (required for models/JSON):
    ```bash
    dart pub run build_runner build --delete-conflicting-outputs
    ```

---

## 🚀 Running the App

This project uses **Flavors** to manage environments. You **must** specify a flavor and the corresponding entry file to run the app.

### Development
```bash
flutter run --flavor development -t lib/dev/main_dev.dart
```

### Staging
```bash
flutter run --flavor stage -t lib/stage/main_stage.dart
```

### Production
```bash
flutter run --flavor production -t lib/prod/main_prod.dart
```

---

### Command to build application for the particular environment

To make build for a particular environment just replace the `<flavor>` with an appropriate env name
`flutter build apk --flavor <flavor> -t lib/<flavor>/main_<flavor>.dart`

---

### Android

## Dev Build

`flutter build apk --flavor development -t lib/dev/main_dev.dart`

## Stage Build

`flutter build apk --flavor stage -t lib/stage/main_stage.dart`

## Production Build

`flutter build apk --flavor production -t lib/prod/main_prod.dart`

## Production (App Bundle)

`flutter build appbundle --flavor production -t lib/prod/main_prod.dart android-arm,android-arm64,android-x64`

### IOS

## Dev Build

`flutter build ios --flavor development -t lib/dev/main_dev.dart`

## Stage Build

`flutter build ios --flavor stage -t lib/stage/main_stage.dart`

## Production Build

`flutter build ios --flavor production -t lib/prod/main_prod.dart`


## Command to start build_runner

`dart run build_runner watch --delete-conflicting-outputs`

## Command to install pods

`cd ios && rm -rf Pods && rm -rf Podfile.lock && rm -rf .symlinks && pod install --repo-update`

---

## 🚀 Preparing for Play Store

### 1. Update Version
Update the `version` in `pubspec.yaml` before building a release.
```yaml
version: 1.0.0+1  # versionName + versionCode
```

### 2. Code Obfuscation (Proguard)
To shrink and obfuscate your code, create a `proguard-rules.pro` file in `android/app/`.
Then, in `android/app/build.gradle`, enable it:
```gradle
buildTypes {
    release {
        // ...
        minifyEnabled true
        shrinkResources true
        proguardFiles getDefaultProguardFile('proguard-android.txt'), 'proguard-rules.pro'
    }
}
```

### 3. Signing the App
Create a `key.properties` file in `android/` with your keystore details. **Do not commit this file.**
```properties
storePassword=your_store_password
keyPassword=your_key_password
keyAlias=your_key_alias
storeFile=../upload-keystore.jks
```

### 4. Build App Bundle (AAB)
Google Play requires App Bundles (.aab) for new apps.
```bash
flutter build appbundle --flavor production -t lib/prod/main_prod.dart android-arm,android-arm64,android-x64
```
