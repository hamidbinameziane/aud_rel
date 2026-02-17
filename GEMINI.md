# Project Overview

This is a Flutter application that serves as a proof-of-concept for real-time audio streaming. It can function as both a server (broadcasting audio) and a client (receiving and playing audio). The primary use case appears to be streaming audio from a Linux PC to an Android device.

**Technologies Used:**

*   **Framework:** Flutter
*   **Language:** Dart
*   **Audio Playback (Client):** `flutter_pcm_sound` package
*   **Audio Capture (Server):** `parec` (pulseaudio client) command-line tool
*   **Networking:** `RawDatagramSocket` for UDP communication

**Architecture:**

The application is a single-screen mobile app with two main functions:

1.  **Server Mode (PC):**
    *   Binds to a UDP socket (port 4444).
    *   Uses the `parec` command to capture system audio as raw PCM data (16-bit, mono, 44100Hz).
    *   Streams the captured audio data over UDP to a specified client IP address.

2.  **Client Mode (Android):**
    *   Initializes the `flutter_pcm_sound` engine.
    *   Binds to a UDP socket (port 4444) to listen for incoming audio data.
    *   Feeds the received PCM data directly to the audio engine for playback.

The UI provides buttons to start the server or client, and a button to stop all activity.

# Building and Running

## Prerequisites

*   **Flutter:** Ensure the Flutter SDK is installed and configured.
*   **Linux (for Server):** The `parec` utility must be installed (usually part of the PulseAudio package).

## Running the Application

1.  **Configure the Client IP:**
    *   In `lib/main.dart`, locate the `_startServer` function.
    *   Modify the `remoteIP` variable to match the IP address of the device that will be running the client.
    *   `final remoteIP = InternetAddress("YOUR_CLIENT_IP_ADDRESS");`

2.  **Run as a Flutter App:**
    *   Connect a target device or start an emulator.
    *   Execute the standard `flutter run` command:
        ```bash
        flutter run
        ```

3.  **Operation:**
    *   **On the Server Device (PC):** Tap the "Lancer SERVEUR (PC)" button.
    *   **On the Client Device (Android):** Tap the "Lancer CLIENT (Tel)" button.
    *   To stop, use the "Tout arrêter" button.

# Development Conventions

*   **State Management:** The application uses `StatefulWidget` and `setState` for managing its simple state (status text, streaming flag).
*   **Dependencies:** Project dependencies are managed in `pubspec.yaml`.
*   **Platform-Specific Code:** The audio capture logic is specific to Linux and relies on an external command-line tool (`parec`). The audio playback is handled by a Flutter plugin.
*   **No explicit testing practices** are evident from the project structure.
