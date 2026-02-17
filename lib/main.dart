import 'dart:async'; // Added
import 'dart:io';
import 'dart:isolate';
// Added
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart'; // Added
import 'package:audio_stream_poc/audio_client_task_handler.dart'; // Added

// The callback function that is executed in the background.
// This is necessary for FlutterForegroundTask
@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(AudioClientTaskHandler());
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Only initialize foreground task for Android
  if (Platform.isAndroid) {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'foreground_service_channel_id',
        channelName: 'Foreground Service Notification',
        channelDescription:
            'This notification appears when the foreground service is running.',
        iconData: const NotificationIconData(
          resType: ResourceType.mipmap,
          resPrefix: ResourcePrefix.ic,
          name: 'launcher',
        ),
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: true,
        playSound: false,
      ),
      foregroundTaskOptions: const ForegroundTaskOptions(
        interval: 5000, // Not really used for audio stream, but required
        autoRunOnBoot: true,
        allowWifiLock: true,
      ),
    );
  }
  runApp(
    MaterialApp(
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData.dark(),
      home: const AudioRelayClone(),
    ),
  );
}

class AudioRelayClone extends StatefulWidget {
  const AudioRelayClone({super.key});

  @override
  State<AudioRelayClone> createState() => _AudioRelayCloneState();
}

class _AudioRelayCloneState extends State<AudioRelayClone> {
  final _ipController = TextEditingController();
  RawDatagramSocket? _socket; // This is only for the server now
  Process? _audioProcess;

  String _status = "Prêt";
  bool _isStreaming = false;

  ReceivePort? _receivePort; // Added for communication with foreground service

  @override
  void initState() {
    super.initState();
    _ipController.text = "192.168.100.103"; // Default IP
    if (Platform.isAndroid) {
      _initForegroundTask(); // Initialize foreground task communication
    }
  }

  // New method to initialize foreground task communication
  void _initForegroundTask() {
    // Communication with foreground service can be handled via AudioClientTaskHandler
    // If you need to receive updates, implement a callback mechanism in AudioClientTaskHandler
  }

  // --- CONFIGURATION SERVEUR (LINUX) ---
  void _startServer() async {
    // If client is running, stop it first
    if (Platform.isAndroid &&
        _isStreaming &&
        await FlutterForegroundTask.isRunningService) {
      _stopAll();
      await Future.delayed(
        const Duration(milliseconds: 500),
      ); // Give it a moment to stop
    }

    _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 4444);

    // IP de destination entrée par l'utilisateur
    final remoteIP = InternetAddress(_ipController.text);

    // Capture du son système via parec
    _audioProcess = await Process.start('parec', [
      '--format=s16le',
      '--channels=1',
      '--rate=44100',
      '--latency-msec=20',
    ]);

    setState(() {
      _status = "PC diffuse vers ${remoteIP.address}";
      _isStreaming = true;
    });

    _audioProcess!.stdout.listen((data) {
      _socket?.send(data, remoteIP, 4444);
    });
  }

  // --- CONFIGURATION CLIENT (ANDROID) ---
  void _startClient() async {
    // If server is running, stop it first
    if (_isStreaming && _audioProcess != null) {
      _stopAll();
      await Future.delayed(
        const Duration(milliseconds: 500),
      ); // Give it a moment to stop
    }

    // Start foreground service only on Android
    if (Platform.isAndroid) {
      final startResult = await FlutterForegroundTask.startService(
        notificationTitle: 'Audio Stream Client',
        notificationText: 'Receiving audio...',
        callback: startCallback,
      );

      if (startResult) {
        setState(() {
          _status = "Android reçoit le son...";
          _isStreaming = true;
        });
      } else {
        setState(() {
          _status = "Failed to start client service.";
          _isStreaming = false;
        });
      }
    } else {
      setState(() {
        _status = "Client mode not supported on this platform.";
        _isStreaming = false;
      });
    }
  }

  void _stopAll() async {
    // Made async
    _audioProcess?.kill();
    _socket?.close();

    // Stop foreground service if running, only on Android
    if (Platform.isAndroid && await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.stopService();
    }

    setState(() {
      _status = "Arrêté";
      _isStreaming = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Flutter Audio Stream")),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.radar,
              size: 80,
              color: _isStreaming ? Colors.green : Colors.grey,
            ),
            const SizedBox(height: 20),
            Text(
              _status,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 40),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32.0),
              child: TextField(
                controller: _ipController,
                decoration: const InputDecoration(
                  labelText: "Adresse IP du client",
                  border: OutlineInputBorder(),
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _startServer,
              icon: const Icon(Icons.computer),
              label: const Text("Lancer SERVEUR (PC)"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 10),
            ElevatedButton.icon(
              onPressed: _startClient,
              icon: const Icon(Icons.phone_android),
              label: const Text("Lancer CLIENT (Tel)"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 20),
            TextButton(
              onPressed: _stopAll,
              child: const Text(
                "Tout arrêter",
                style: TextStyle(color: Colors.red),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _ipController.dispose();
    _receivePort?.close(); // Added
    _stopAll();
    super.dispose();
  }
}
