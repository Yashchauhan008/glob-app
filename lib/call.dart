import 'package:flutter/foundation.dart';
import 'package:livekit_client/livekit_client.dart';
import 'api.dart';

/// One call per team. Lives outside any page so the call keeps running while you browse the app.
class CallService extends ChangeNotifier {
  static final CallService I = CallService();

  Room? room;
  String status = 'idle'; // idle | connecting | connected
  String error = '';
  bool mic = false;
  bool cam = false;

  bool get connected => status == 'connected';

  Future<void> join({bool video = false}) async {
    if (room != null || status == 'connecting') return;
    status = 'connecting';
    error = '';
    notifyListeners();
    Room? rm;
    try {
      final r = await Api.get('/voice/token');
      rm = Room(roomOptions: const RoomOptions(adaptiveStream: true, dynacast: true));
      rm.addListener(notifyListeners);
      await rm.connect('${r['url']}', '${r['token']}');
      room = rm;
      status = 'connected';
      try {
        await rm.localParticipant?.setMicrophoneEnabled(true);
        mic = true;
      } catch (e) {
        error = 'Microphone unavailable. Allow it in app settings.';
      }
      if (video) {
        try {
          await rm.localParticipant?.setCameraEnabled(true);
          cam = true;
        } catch (_) {}
      }
    } catch (e) {
      error = '$e';
      status = 'idle';
      room = null;
      try {
        rm?.removeListener(notifyListeners);
        await rm?.disconnect();
      } catch (_) {}
    }
    notifyListeners();
  }

  Future<void> toggleMic() async {
    final lp = room?.localParticipant;
    if (lp == null) return;
    try {
      await lp.setMicrophoneEnabled(!mic);
      mic = !mic;
      error = '';
    } catch (_) {
      error = 'Microphone unavailable. Allow it in app settings.';
    }
    notifyListeners();
  }

  Future<void> toggleCam() async {
    final lp = room?.localParticipant;
    if (lp == null) return;
    try {
      await lp.setCameraEnabled(!cam);
      cam = !cam;
      error = '';
    } catch (_) {
      error = 'Camera unavailable. Allow it in app settings.';
    }
    notifyListeners();
  }

  Future<void> leave() async {
    final rm = room;
    room = null;
    status = 'idle';
    mic = false;
    cam = false;
    notifyListeners();
    if (rm != null) {
      try {
        rm.removeListener(notifyListeners);
        await rm.disconnect();
      } catch (_) {}
    }
  }
}
