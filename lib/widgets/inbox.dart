import 'package:flutter/material.dart';
import 'package:flutter_novu/headless.dart';
import 'package:flutter_novu/screens/notifications.dart';
import 'package:flutter_novu/types.dart';

class Inbox extends StatefulWidget {
  final HeadlessService headlessService;
  final Widget? icon;
  final List<InboxTab> tabs;

  Inbox({super.key,
    String backendUrl = 'https://eu.api.novu.co',
    String socketUrl = 'https://eu.ws.novu.co',
    required String applicationIdentifier,
    required String? subscriberId,
    this.icon,
    this.tabs = const [],
  }): headlessService = HeadlessService(
          backendUrl: backendUrl,
          socketUrl: socketUrl,
          applicationIdentifier: applicationIdentifier,
          subscriberId: subscriberId,
          tabs: tabs,
        );
  Inbox.fromHeadlessService({super.key,
    required this.headlessService,
    this.icon,
  }) : tabs = headlessService.tabs;

  @override
  State<Inbox> createState() => _InboxState();
}

class _InboxState extends State<Inbox> {
  late final HeadlessService _headless = widget.headlessService;
  int unreadCount = 0;
  int unseenCount = 0;

  @override
  void initState() {
    // TODO: implement initState
    super.initState();

    
    _headless.onUnreadCountChanged.listen((count) {
      setState(() {
        unreadCount = count;
      });
    });
    _headless.onUnseenCountChanged.listen((count) {
      setState(() {
        unseenCount = count;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    var icon =  IconButton(
      icon: widget.icon ?? const Icon(Icons.notifications),
      onPressed: () {
        Navigator.push(context, MaterialPageRoute<void>(
          builder: (context) => NotificationsScreen(
            headlessService: _headless,
          ),
        ));
      },
    );
    if (unreadCount > 0) {
      return Badge(
        label: Text(unreadCount.toString()),
        offset: Offset(-4, 2),
        child: icon,
      );
    }

    return icon;
  }
}
