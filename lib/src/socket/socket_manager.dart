import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_boilerplate/src/base/dependencyinjection/locator.dart';
import 'package:flutter_boilerplate/src/base/utils/constants/preference_key_constant.dart';
import 'package:flutter_boilerplate/src/base/utils/dialog_utils.dart';
import 'package:flutter_boilerplate/src/base/utils/navigation_utils.dart';
import 'package:flutter_boilerplate/src/base/utils/preference_utils.dart';
import 'package:flutter_boilerplate/src/socket/socket_constant.dart';
import 'package:socket_io_client/socket_io_client.dart';

StreamController<Map<String, dynamic>> onGroupMessageStream =
    StreamController<Map<String, dynamic>>.broadcast();
StreamController<Map<String, dynamic>> onJoinRoomStream =
    StreamController<Map<String, dynamic>>.broadcast();
StreamController<Map<String, dynamic>> onLeaveRoomStream =
    StreamController<Map<String, dynamic>>.broadcast();

Socket? _socketInstance;

Socket? get socketInstance => _socketInstance;

void initSocketManager() {
  if (_socketInstance == null) {
    _socketInstance = io(
        dotenv.env['BASE_URL'] ?? "",
        OptionBuilder()
            .setExtraHeaders(
                {"Authorization": "Bearer ${getString(prefkeyToken)}"})
            .setTransports(['websocket'])
            .enableReconnection()
            .enableAutoConnect()
            .enableForceNew()
            .build());
    _socketInstance!.connect();
    socketGlobalListeners();
  }
}

void reInitializeAndConnectSocket() {
  deInitialize();
  closeStreams();
  initSocketManager();
}

void deInitializeAndCloseStreamSocket() {
  deInitialize();
  closeStreams();
}

void closeStreams() {
  onGroupMessageStream.close();
  onGroupMessageStream = StreamController<Map<String, dynamic>>.broadcast();
  onJoinRoomStream.close();
  onJoinRoomStream = StreamController<Map<String, dynamic>>.broadcast();
  onLeaveRoomStream.close();
  onLeaveRoomStream = StreamController<Map<String, dynamic>>.broadcast();
}

void deInitialize() {
  disconnectSocket();
  _socketInstance = null;
}

void disconnectSocket() async {
  _socketInstance?.clearListeners();
  _socketInstance?.disconnect();
}

void socketGlobalListeners() {
  _socketInstance?.on(onSocketConnected, onConnect);
}

bool isSocketConnected() {
  if (_socketInstance != null) {
    return _socketInstance!.connected;
  }
  return false;
}

bool emit(String event, Map<String, dynamic> data) {
  debugPrint("********* $event *********");
  debugPrint("$data");
  _socketInstance?.emit(event, jsonDecode(json.encode(data)));
  return _socketInstance!.connected;
}

bool roomEmit(String event, int roomId) {
  debugPrint("********* $event: $roomId *********");
  _socketInstance?.emit(event, roomId);
  return _socketInstance!.connected;
}

Future<dynamic> emitWithAck(String event, Map<String, dynamic> data) async {
  Completer<dynamic> completer = Completer();
  debugPrint("********* $event *********");
  debugPrint("$data");
  _socketInstance?.emitWithAck(event, jsonDecode(json.encode(data)),
      ack: (data) {
    if (data["status"] == 200) {
      completer.complete(data);
    } else {
      if (data["type"] == "inquiry") {
        locator<NavigationUtils>().pop();
      }
      showAlertDialog(
          message: data["error"] ?? data["message"], isCancelEnable: false);
      completer.complete(data);
    }
  });
  return completer.future;
}

dynamic on(String event, Function(dynamic) fn) {
  _socketInstance?.on(event, fn);
}

void onConnect(dynamic _) {
  debugPrint("********* Connected Socket *********");
}

void onDisconnect(dynamic _) {
  debugPrint("********* Disconnected Socket *********");
}

void onConnectError(dynamic data) {
  debugPrint("********* ConnectError Socket *********");
  debugPrint("$data");
}

void onThrowError(dynamic data) {
  debugPrint("********* ThrowError Function Socket *********");
  debugPrint("$data");
  showAlertDialog(message: data["error"], isCancelEnable: false);
}

void handleOnGroupMessageStream(dynamic data) {
  debugPrint("********* On Group Message *********");
  debugPrint("$data");
  onGroupMessageStream.add(data);
}

void handleOnJoinRoomStream(dynamic data) {
  debugPrint("********* On Join Room *********");
  debugPrint("$data");
  onJoinRoomStream.add(data);
}

void handleOnLeaveRoomStream(dynamic data) {
  debugPrint("********* On Leave Room *********");
  debugPrint("$data");
  onLeaveRoomStream.add(data);
}

class ChatSocketListener {
  void listen(Function(dynamic) onMessage) {
    socketInstance?.on(onPrivateMessage, onMessage);
  }

  void remove(Function(dynamic) onMessage) {
    socketInstance?.off(onPrivateMessage, onMessage);
  }
}
