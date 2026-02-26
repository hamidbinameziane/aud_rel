import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_pcm_sound/flutter_pcm_sound.dart';
import 'package:record/record.dart';

@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(AudioClientTaskHandler());
}

class AudioClientTaskHandler extends TaskHandler {
  RawDatagramSocket? _socket;
  final int _port = 4444; 
  final int _micPort = 4445; 
  AudioRecorder? _recorder; 
  StreamSubscription? _recorderSubscription;

  @override
  Future<void> onStart(DateTime timestamp, SendPort? sendPort) async {

    int bufferSize = 8000;
    bool mobileMicMode = false;
    String serverIP = "";

    final dynamic receivedData = await FlutterForegroundTask.getData(key: 'bufferSize');
    if (receivedData is int) {
      bufferSize = receivedData;
    }

    final dynamic micModeData = await FlutterForegroundTask.getData(key: 'mobileMicMode');
    if (micModeData is bool) {
      mobileMicMode = micModeData;
    }

    final dynamic ipData = await FlutterForegroundTask.getData(key: 'serverIP');
    if (ipData is String) {
      serverIP = ipData;
    }

    if (mobileMicMode) {
      sendPort?.send('Starting Mobile Mic mode...');
      _recorder = AudioRecorder();
      
      try {
        // hasPermission() can sometimes return false in background isolates
        // even if granted. We rely on the UI isolate check but keep this for safety.
        final hasPerm = await _recorder!.hasPermission();
        sendPort?.send('Background permission check: $hasPerm');
        
        if (!hasPerm) {
          sendPort?.send('Warning: hasPermission() returned false. Attempting to start anyway...');
        }
      } catch (e) {
        sendPort?.send('Error checking permission: $e');
      }

      try {
        _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
        sendPort?.send('UDP Socket bound to port ${_socket!.port}');
      } catch (e) {
        sendPort?.send('Error binding UDP socket: $e');
        return;
      }
      
      try {
        final recordStream = await _recorder!.startStream(const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 44100,
          numChannels: 1,
        ));

        final destination = InternetAddress(serverIP);
        sendPort?.send('Recording started, sending to ${destination.address}:$_micPort');
        
        int packetCount = 0;
        _recorderSubscription = recordStream.listen((data) {
          _socket?.send(data, destination, _micPort);
          packetCount++;
          if (packetCount % 100 == 0) {
            sendPort?.send('Sent $packetCount packets');
          }
        }, onError: (error) {
          sendPort?.send('Recorder stream error: $error');
        }, onDone: () {
          sendPort?.send('Recorder stream done');
        });
      } catch (e) {
        sendPort?.send('Error starting record stream: $e');
      }

    } else {
      try {
        await FlutterPcmSound.setup(sampleRate: 44100, channelCount: 1);
        await FlutterPcmSound.setFeedThreshold(bufferSize);
        FlutterPcmSound.play();

        _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, _port);
        _socket!.listen((event) {
          if (event == RawSocketEvent.read) {
            final Datagram? dg = _socket!.receive();
            if (dg != null) {
              FlutterPcmSound.feed(
                PcmArrayInt16(bytes: dg.data.buffer.asByteData()),
              );
            }
          }
        });

        sendPort?.send(
          'Client started, listening on port $_port with buffer size $bufferSize',
        );
      } catch (e) {
        sendPort?.send('Error starting client mode: $e');
      }
    }
  }

  @override
  void onData(DateTime timestamp, dynamic data) {
  }

  @override
  Future<void> onEvent(DateTime timestamp, SendPort? sendPort) async {
  }

  @override
  Future<void> onDestroy(DateTime timestamp, SendPort? sendPort) async {
    await _recorderSubscription?.cancel();
    _socket?.close();
    if (_recorder != null) {
      try {
        await _recorder!.stop();
        _recorder!.dispose();
      } catch (e) {
        sendPort?.send('Error stopping recorder: $e');
      }
    }
    FlutterPcmSound.stop();
    sendPort?.send('Task destroyed');
  }
}
