import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:audio_stream_poc/audio_client_task_handler.dart';
import 'package:permission_handler/permission_handler.dart';

@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(AudioClientTaskHandler());
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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
        interval: 5000,
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
  final _bufferSizeController = TextEditingController();
  RawDatagramSocket? _socket;
  Process? _audioProcess;
  String? _moduleID;

  String _status = "Prêt";
  bool _isStreaming = false;
  bool _mobileMicMode = false;

  ReceivePort? _receivePort;

  @override
  void initState() {
    super.initState();
    _ipController.text = "192.168.100.103";
    _bufferSizeController.text = "8000";
    if (Platform.isAndroid) {
      _initForegroundTask();
    }
  }

  void _initForegroundTask() {
    _receivePort = FlutterForegroundTask.receivePort;
    _receivePort?.listen(_onReceiveTaskData);
  }

  void _onReceiveTaskData(dynamic data) {
    if (data is String) {
      print("Foreground Task Log: $data");
      if (mounted) {
        setState(() {
          _status = data;
        });
      }
    }
  }

  void _startServer() async {
    if (Platform.isAndroid &&
        _isStreaming &&
        await FlutterForegroundTask.isRunningService) {
      _stopAll();
      await Future.delayed(const Duration(milliseconds: 500));
    }

    if (_mobileMicMode) {
      try {
        _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 4445);
        
        final pipePath = '/tmp/virtmic_pipe';
        // Proactively unload existing module-pipe-source to avoid duplicates
        final setupCommand = 'pactl unload-module module-pipe-source 2>/dev/null; rm -f $pipePath && mkfifo $pipePath && pactl load-module module-pipe-source source_name=virtmic file=$pipePath format=s16le rate=44100 channels=1';
        
        final result = await Process.run('sh', ['-c', setupCommand]);
        
        print("PC Setup Result: STDOUT: ${result.stdout}, STDERR: ${result.stderr}");

        if (result.exitCode != 0 || result.stdout.toString().trim().isEmpty) {
          setState(() {
            _status = "Erreur setup PC: ${result.stderr}";
          });
          _socket?.close();
          return;
        }

        _moduleID = result.stdout.toString().trim();
        print("PulseAudio Module Loaded ID: $_moduleID");

        final sink = File(pipePath).openWrite();

        setState(() {
          _status = "PC en attente du micro (ID: $_moduleID)";
          _isStreaming = true;
        });

        int receivedPackets = 0;
        _socket!.listen((event) {
          if (event == RawSocketEvent.read) {
            final dg = _socket!.receive();
            if (dg != null) {
              sink.add(dg.data);
              receivedPackets++;
              if (receivedPackets % 100 == 0) {
                print("PC: Received $receivedPackets packets, latest size: ${dg.data.length}");
                if (mounted) {
                  setState(() {
                    _status = "PC reçoit: $receivedPackets paquets";
                  });
                }
              }
            }
          }
        });
      } catch (e) {
        setState(() {
          _status = "Exception: $e";
        });
        _socket?.close();
      }
    } else {
      _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 4444);
      final remoteIP = InternetAddress(_ipController.text);

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
  }

  void _startClient() async {
    if (_isStreaming && _audioProcess != null) {
      _stopAll();
      await Future.delayed(const Duration(milliseconds: 500));
    }

    if (Platform.isAndroid) {
      if (_mobileMicMode) {
        final status = await Permission.microphone.request();
        if (!status.isGranted) {
          setState(() {
            _status = "Permission micro refusée";
          });
          return;
        }
      }

      final int bufferSize = int.tryParse(_bufferSizeController.text) ?? 8000;
      
      await FlutterForegroundTask.saveData(key: 'bufferSize', value: bufferSize);
      await FlutterForegroundTask.saveData(key: 'mobileMicMode', value: _mobileMicMode);
      await FlutterForegroundTask.saveData(key: 'serverIP', value: _ipController.text);

      final startResult = await FlutterForegroundTask.startService(
        notificationTitle: _mobileMicMode ? 'Mobile Mic' : 'Audio Stream Client',
        notificationText: _mobileMicMode ? 'Sending microphone audio...' : 'Receiving audio...',
        callback: startCallback,
      );

      if (startResult) {
        setState(() {
          _status = _mobileMicMode ? "Android envoie le micro..." : "Android reçoit le son...";
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
    _audioProcess?.kill();
    _socket?.close();

    if (Platform.isAndroid && await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.stopService();
    }
    
    if (Platform.isLinux && _mobileMicMode && _moduleID != null) {
      print("Unloading module $_moduleID");
      await Process.run('pactl', ['unload-module', _moduleID!]);
      await Process.run('rm', ['/tmp/virtmic_pipe']);
      _moduleID = null;
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
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                _mobileMicMode ? Icons.mic : Icons.radar,
                size: 80,
                color: _isStreaming ? Colors.green : Colors.grey,
              ),
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Text(
                  _status,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 20),
              SwitchListTile(
                title: const Text("Mode Micro Mobile (Mobile -> PC)"),
                subtitle: const Text("Le téléphone sert de microphone au PC"),
                value: _mobileMicMode,
                onChanged: _isStreaming ? null : (val) {
                  setState(() {
                    _mobileMicMode = val;
                  });
                },
              ),
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32.0),
                child: TextField(
                  controller: _ipController,
                  decoration: InputDecoration(
                    labelText: _mobileMicMode ? "Adresse IP du PC" : "Adresse IP du client (Tel)",
                    border: const OutlineInputBorder(),
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32.0),
                child: TextField(
                  controller: _bufferSizeController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: "Taille du buffer (ex: 8000)",
                    border: OutlineInputBorder(),
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: _startServer,
                icon: const Icon(Icons.computer),
                label: Text(_mobileMicMode ? "Lancer RÉCEPTEUR MICRO (PC)" : "Lancer DIFFUSEUR SON (PC)"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                ),
              ),
              const SizedBox(height: 10),
              ElevatedButton.icon(
                onPressed: _startClient,
                icon: const Icon(Icons.phone_android),
                label: Text(_mobileMicMode ? "Lancer ENVOI MICRO (Tel)" : "Lancer RÉCEPTION SON (Tel)"),
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
      ),
    );
  }

  @override
  void dispose() {
    _ipController.dispose();
    _bufferSizeController.dispose();
    _stopAll();
    super.dispose();
  }
}
