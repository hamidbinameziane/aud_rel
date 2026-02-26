import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_pcm_sound/flutter_pcm_sound.dart';

// The callback function that is executed in the background.
@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(AudioClientTaskHandler());
}

class AudioClientTaskHandler extends TaskHandler {
  RawDatagramSocket? _socket;
  final int _port = 4444; // Port to listen on

  // Called when the task is started.
  @override
  Future<void> onStart(DateTime timestamp, SendPort? sendPort) async {
    print('Foreground task onStart called.'); // Debug log

    int bufferSize = 8000; // Default buffer size
    final dynamic receivedData = await FlutterForegroundTask.getData(
      key: '',
    ); // Get data set by setData
    print('Received data from foreground task: $receivedData'); // Debug log

    if (receivedData is Map && receivedData.containsKey('bufferSize')) {
      final int? parsedBufferSize = receivedData['bufferSize'] as int?;

      if (parsedBufferSize != null) {
        bufferSize = parsedBufferSize;
      }
    }
    print('Determined bufferSize: $bufferSize'); // Debug log

    // Initialize audio playback
    await FlutterPcmSound.setup(sampleRate: 44100, channelCount: 1);
    await FlutterPcmSound.setFeedThreshold(bufferSize);
    FlutterPcmSound.play();
    print(
      'FlutterPcmSound.setFeedThreshold called with: $bufferSize',
    ); // Debug log

    // Bind UDP socket
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

    // Optionally send initial status to UI
    sendPort?.send(
      'Client started, listening on port $_port with buffer size $bufferSize',
    );
  }

  // Called when a new data is received from the main isolate.
  void onData(DateTime timestamp, dynamic data) {
    // You can use the `data` to update the foreground task.
    // For example, if you send an IP address from the UI, you could update the remoteIP here.
  }

  // Called when the task is interrupted.
  @override
  Future<void> onEvent(DateTime timestamp, SendPort? sendPort) async {
    // Added SendPort? sendPort
    // You can use the `data` to update the foreground task.
  }

  // Called when the task is terminated.
  @override
  Future<void> onDestroy(DateTime timestamp, SendPort? sendPort) async {
    // You can use the `sendPort` to send data to the main isolate.
    // sendPort?.send('onDestroy');

    _socket?.close();
    FlutterPcmSound.stop();
  }
}
