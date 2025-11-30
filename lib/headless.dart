import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_novu/api/base.dart';
import 'package:flutter_novu/enums.dart';
import 'package:flutter_novu/types.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;

import 'dot.dart' as Dot;
import 'dot/inbox_notification.dart';

class HeadlessService {
  final String backendUrl;
  final String socketUrl;
  late final String applicationIdentifier;
  final String? subscriberId;
  final String? subscriberHash;
  final int? retry;
  final int retryDelay;
  final SharedPreferencesAsync prefs = SharedPreferencesAsync();
  final List<InboxTab> tabs;
  final _notificationStreamController = StreamController<Dot.Notification>();
  final _unreadStreamController = StreamController<int>();
  final _unseenStreamController = StreamController<int>();

  Stream<Dot.Notification> get onNotificationReceived => _notificationStreamController.stream.asBroadcastStream();
  Stream<int> get onUnreadCountChanged => _unreadStreamController.stream.asBroadcastStream();
  Stream<int> get onUnseenCountChanged => _unseenStreamController.stream.asBroadcastStream();

  IO.Socket? _socket;
  String? _token;
  late final Dio _client;

  HeadlessService({
    this.backendUrl = 'https://api.novu.co',
    this.socketUrl = 'https://ws.novu.co',
    required this.applicationIdentifier,
    this.subscriberId,
    this.subscriberHash,
    this.retry,
    this.retryDelay = 10000,
    this.tabs = const [],
  }) {
    var api = BaseApi(backendUrl);
    api.request(method: ApiMethod.POST, endpoint: 'inbox/session', data: {'applicationIdentifier': applicationIdentifier, 'subscriberId': subscriberId}).then((response) {
      var value = response['data'];
      prefs.setString('novu_token', value['token']);
      initializeSocket(value['token']);
      _token = value['token'];

      _client = Dio();
      _client.options.baseUrl = '$backendUrl/v1/inbox/';
      if (_token != null) {
        _client.options.headers['Authorization'] = 'Bearer $_token';
      }

        countNotifications(read: false).then((value) => _unreadStreamController.add(value));
      
    });
    // _socket = WebSocketChannel.connect(Uri.parse(socketUrl));
  }

  void initializeSocket([String? token]) async {
    if (_socket != null) {
      _socket?.close();
    }

    if (token != null) {
      _socket = IO.io(socketUrl, {
        'reconnectionDelayMax': retryDelay,
        'transports': ['websocket'],
        'query': {'token': token},
      });

        _socket!.on(WebSocketEvent.received.value, (data) {
          if (data['message'] != null) {
            _notificationStreamController.add(Dot.Notification.fromJson(data['message']!));
          }
        });
      

    
        _socket!.on(WebSocketEvent.unread.value, (data) {
         
            countNotifications(read: false).then((value) =>
                _unreadStreamController.add(value));
          
        });
      }

     
        _socket!.on(WebSocketEvent.unseen.value, (data) {
          _unseenStreamController.add(data['unseenCount']);
        });
      

      _socket!.on('connect_error', (error) {
        print('Error: $error');
      });
      // _socket = WebSocketChannel.connect(Uri.parse('${socketUrl.replaceAll('http', 'ws')}/socket.io/?token=$token&EIO=4&transport=websocket'), protocols: ['websocket']);
      //
      // await _socket!.ready;
      //
      // _socket!.stream.listen((event) {
      //   print(event);
      // });
      //
      // _socket!.sink.add('2probe');
    }
  

  Future<Dot.PaginatedResponse<InboxNotification>> getNotifications({
    bool archived = false,
    bool? read,
    int page = 0,
    int limit = 10,
    List<String> tags = const [],
  }) async {
    var response = (await _client.get<Map<String, dynamic>>(
        'notifications',
        queryParameters: {
          'offset': page * limit,
          'limit': limit,
          'archived': archived,
          if (read != null) 'read': read,
          if (tags.isNotEmpty == true) 'tags[]': tags,
        }
    )).data!;
    return Dot.PaginatedResponse<Dot.InboxNotification>(
      page: response['page'] ?? page,
      totalCount: response['totalCount'] ?? 0,
      pageSize: limit,
      hasMore: response['hasMore'],
      data: response['data'].map<InboxNotification>((var r) => InboxNotification.fromJson(r)).toList(),
    );
  }

  Future<Dot.InboxNotification> markNotificationAs(String id, MarkNotificationAs status) async {
    var response = (await _client.patch<Map<String, dynamic>>(
      'notifications/$id/${status.name}',
    )).data!;

      countNotifications(read: false).then((value) => _unreadStreamController.add(value));
    

    return Dot.InboxNotification.fromJson(response['data']);
  }

  Future<void> markAllNotificationAs(MarkAllNotificationAs status, {List<String> tags = const []}) async {
    await _client.post<Map<String, dynamic>>(
        'notifications/${status.value}',
        data: {
          if (tags.isNotEmpty == true) 'tags': tags,
        }
    );

      countNotifications(read: false).then((value) => _unreadStreamController.add(value));
    
  }

  Future<String> completeNotificationAction(String id, ButtonType action) async {
    var response = (await _client.post<Map<String, dynamic>>(
        'notifications/$id/complete',
        data: {
          'actionType': action.name,
        }
    )).data!;
    return response['data']['notificationId'];
  }

  Future<String> reverseNotificationAction(String id, ButtonType action) async {
    var response = (await _client.post<Map<String, dynamic>>(
        'notifications/$id/revert',
        data: {
          'actionType': action.name,
        }
    )).data!;
    return response['data']['notificationId'];
  }

  Future<int> countNotifications({bool? read, bool? archived, List<String> tags = const [] }) async {
    var response = (await _client.get<Map<String, dynamic>>(
        'notifications/count',
        queryParameters: {
          'filters': jsonEncode([{
            if (tags.isNotEmpty == true) 'tags': tags,
            if (read != null) 'read': read,
            if (archived != null) 'archived': archived
          }])
        }
    )).data!;

    return response['data'].first['count'];
  }

  Future<List<Dot.PreferencesResponse>> fetchPreferences({List<String> tags = const []}) async {
    var response = (await _client.get<Map<String, dynamic>>(
        'preferences',
        queryParameters: {
          if (tags.isNotEmpty == true) 'tags[]': tags,
        }
    )).data!;
    return response['data'].map<Dot.PreferencesResponse>((var r) => Dot.PreferencesResponse.fromJson(r)).toList();
  }

  /// Update global preferences
  ///
  /// [preferences] is a map of preferences to update, key of the preference (in_app, sms, push, email, chat) and value of the preference
  Future<Dot.PreferencesResponse> updateGlobalPreferences(Map<String, bool> preferences) async {
    var response = (await _client.patch<Map<String, dynamic>>(
      'preferences',
      data: preferences,
    )).data!;
    return Dot.PreferencesResponse.fromJson(response['data']);
  }

  /// Update global preferences
  ///
  /// [preferences] is a map of preferences to update, key of the preference (in_app, sms, push, email, chat) and value of the preference
  /// [workflowId] is the id of the workflow to update
  Future<Dot.PreferencesResponse> updateWorkflowPreferences(String workflowId, Map<String, bool> preferences) async {
    var response = (await _client.patch<Map<String, dynamic>>(
      'preferences/$workflowId',
      data: preferences,
    )).data!;
    return Dot.PreferencesResponse.fromJson(response['data']);
  }
}