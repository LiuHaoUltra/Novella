import 'dart:typed_data';
import 'package:logging/logging.dart';
import 'package:msgpack_dart/msgpack_dart.dart' as msgpack;
import 'package:signalr_netcore/signalr_client.dart';
import 'package:signalr_netcore/ihub_protocol.dart';

class NovelHubProtocol implements IHubProtocol {
  @override
  String get name => 'messagepack';

  @override
  int get version => 1;

  @override
  TransferFormat get transferFormat => TransferFormat.Binary;

  final Logger _logger = Logger('NovelHubProtocol');

  @override
  List<HubMessageBase> parseMessages(Object input, Logger? logger) {
    if (input is! Uint8List && input is! List<int>) {
      throw Exception(
        'Invalid input for Binary hub protocol. Expected Uint8List or List<int>.',
      );
    }

    final bytes =
        input is Uint8List ? input : Uint8List.fromList(input as List<int>);
    final messages = <HubMessageBase>[];

    // SignalR Binary protocol uses VarInt length-prefixed framing:
    // [VarInt Length][MessagePack Payload][VarInt Length][MessagePack Payload]...

    print('[PROTOCOL] Received ${bytes.length} bytes total');

    int offset = 0;
    while (offset < bytes.length) {
      // Read VarInt length
      int length = 0;
      int bytesRead = 0;
      int shift = 0;

      while (offset + bytesRead < bytes.length) {
        final byte = bytes[offset + bytesRead];
        length |= (byte & 0x7F) << shift;
        bytesRead++;

        if ((byte & 0x80) == 0) break; // MSB is 0, last byte
        shift += 7;
        if (shift >= 35) break; // VarInt too large
      }

      if (length == 0) {
        offset += bytesRead;
        continue;
      }

      final payloadStart = offset + bytesRead;
      final payloadEnd = payloadStart + length;

      if (payloadEnd > bytes.length) {
        print(
          '[PROTOCOL] Incomplete: need $length but have ${bytes.length - payloadStart}',
        );
        break;
      }

      final payload = bytes.sublist(payloadStart, payloadEnd);
      print('[PROTOCOL] Parsing message: length=$length bytes');

      try {
        final deserialized = msgpack.deserialize(payload);
        print('[PROTOCOL] Deserialized: ${deserialized.runtimeType}');

        if (deserialized is List && deserialized.isNotEmpty) {
          _parseSingleMessage(deserialized, messages);
          print('[PROTOCOL] Message type: ${deserialized[0]}');
        }
      } catch (e) {
        print('[PROTOCOL] Error: $e');
      }

      offset = payloadEnd;
    }

    print('[PROTOCOL] Parsed ${messages.length} messages');
    return messages;
  }

  void _parseSingleMessage(dynamic input, List<HubMessageBase> messages) {
    if (input is! List) return;
    if (input.isEmpty) return;

    final typeId = input[0] as int?;
    if (typeId == null) return;

    // headers is index 1?
    // Spec:
    // 1: Invocation
    // 2: StreamItem
    // 3: Completion
    // 6: Ping
    // 7: Close

    // Convert int to MessageType enum logic if needed, or just compare ints if MessageType is enum
    // But wait, the previous error said 'int' can never be equal to 'MessageType'.
    // So typeId is int, MessageType.Invocation is enum.

    switch (typeId) {
      case 1: // MessageType.Invocation
        // [1, Headers, InvocationId, Target, Arguments, StreamIds]
        // Indicies: 0=Type, 1=Headers, 2=InvocationId, 3=Target, 4=Arguments, 5=StreamIds
        final rawHeaders = input[1];
        final Map<String, String> headers = {};
        if (rawHeaders is Map) {
          rawHeaders.forEach((k, v) => headers[k.toString()] = v.toString());
        }
        final invocationId = input[2] as String?;
        final target = input[3] as String;
        final arguments = (input[4] as List?)?.cast<Object>() ?? [];
        final streamIds = (input[5] as List?)?.cast<String>();

        messages.add(
          InvocationMessage(
            target: target,
            arguments: arguments,
            streamIds: streamIds,
            headers: null,
            invocationId: invocationId,
          ),
        );
        break;

      case 3: // MessageType.Completion
        // [3, Headers, InvocationId, ResultKind, Result/Error]
        // ResultKind: 1=Error, 2=Void (no result), 3=NonVoid (has result)
        print('[PROTOCOL] Completion raw: $input');

        // Safely extract fields with null checks
        final invocationId = input.length > 2 ? input[2]?.toString() : null;
        final resultKind = input.length > 3 ? (input[3] as int?) ?? 2 : 2;

        Object? result;
        String? error;

        // resultKind 1 = Error, 2 = Void (no result), 3 = NonVoid (has result)
        if (resultKind == 1 && input.length > 4) {
          // Error - index 4 is error message
          error = input[4]?.toString();
          print('[PROTOCOL] Completion is ERROR: $error');
        } else if (resultKind == 3 && input.length > 4) {
          // NonVoid - index 4 is result
          result = input[4];
          print('[PROTOCOL] Completion has RESULT type: ${result.runtimeType}');
        } else if (resultKind == 2) {
          // Void - no result
          print('[PROTOCOL] Completion is VOID (no result)');
        }

        print(
          '[PROTOCOL] Completion: invocationId=$invocationId, resultKind=$resultKind, hasResult=${result != null}',
        );

        messages.add(
          CompletionMessage(
            invocationId: invocationId ?? '',
            error: error,
            result: result,
            headers: null,
          ),
        );
        break;

      case 6: // MessageType.Ping
        messages.add(PingMessage());
        break;

      case 7: // MessageType.Close
        final error = input.length > 1 ? input[1] as String? : null;
        final allowReconnect = input.length > 2 ? input[2] as bool? : false;
        messages.add(
          CloseMessage(error: error, allowReconnect: allowReconnect),
        );
        break;

      case 2: // MessageType.StreamItem
        // [2, Headers, InvocationId, Item]
        final headers = (input[1] as Map?)?.cast<String, String>() ?? {};
        final invocationId = input[2] as String;
        final item = input[3];
        messages.add(
          StreamItemMessage(
            invocationId: invocationId,
            item: item,
            headers: headers as MessageHeaders?,
          ),
        );
        break;

      default:
        // Ignore unknown
        break;
    }
  }

  @override
  Object writeMessage(HubMessageBase message) {
    // Serialize HubMessage to MsgPack (Uint8List)
    final List<dynamic> payload = [];

    if (message is InvocationMessage) {
      // [1, Headers, InvocationId, Target, Arguments, StreamIds]
      payload.add(1); // Invocation
      // Convert headers to plain Map<String, dynamic> for serialization
      payload.add(_toSerializableMap(message.headers));
      payload.add(message.invocationId);
      payload.add(message.target);
      // Convert arguments for serialization
      final args = _toSerializableList(message.arguments);
      payload.add(args);
      payload.add(message.streamIds);

      // Debug: show what we're sending
      if (message.target == 'SaveReadPosition') {
        print('[PROTOCOL] SaveReadPosition args: $args');
      }
    } else if (message is CompletionMessage) {
      // [3, Headers, InvocationId, ResultKind, Result]
      payload.add(3); // Completion
      payload.add(_toSerializableMap(message.headers));
      payload.add(message.invocationId);

      if (message.error != null) {
        payload.add(3); // Error
        payload.add(message.error);
      } else if (message.result != null) {
        payload.add(2); // NonVoid
        payload.add(message.result);
      } else {
        payload.add(1); // Void
      }
    } else if (message is PingMessage) {
      payload.add(6);
    }
    // Add other types as needed

    // Serialize using msgpack_dart
    final serialized = msgpack.serialize(payload) as Uint8List;

    // SignalR Binary protocol requires VarInt length prefix
    final lengthBytes = _writeVarInt(serialized.length);
    final result = Uint8List(lengthBytes.length + serialized.length);
    result.setAll(0, lengthBytes);
    result.setAll(lengthBytes.length, serialized);

    print(
      '[PROTOCOL] writeMessage: type=${payload.isNotEmpty ? payload[0] : "?"}, payload=${serialized.length} bytes, total=${result.length} bytes',
    );

    return result;
  }

  /// Write a VarInt to bytes
  Uint8List _writeVarInt(int value) {
    final bytes = <int>[];
    while (value > 0x7F) {
      bytes.add((value & 0x7F) | 0x80);
      value >>= 7;
    }
    bytes.add(value & 0x7F);
    return Uint8List.fromList(bytes);
  }

  /// Convert MessageHeaders to a serializable Map
  Map<String, dynamic>? _toSerializableMap(dynamic headers) {
    if (headers == null) return null;
    if (headers is Map) {
      // Return empty map as typed Map<String, dynamic>
      final Map<String, dynamic> result = {};
      headers.forEach((key, value) {
        result[key.toString()] = value;
      });
      return result.isEmpty ? <String, dynamic>{} : result;
    }
    return <String, dynamic>{};
  }

  /// Convert arguments list, ensuring Maps are serializable
  List<dynamic>? _toSerializableList(List<dynamic>? args) {
    if (args == null) return null;
    return args.map((item) {
      if (item is Map) {
        final Map<String, dynamic> result = {};
        item.forEach((key, value) {
          result[key.toString()] = value;
        });
        return result;
      }
      return item;
    }).toList();
  }
}
