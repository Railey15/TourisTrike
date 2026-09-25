import 'package:flutter/material.dart';

/// Presentation state only; history and event delivery do not depend on routes.
final notificationRouteObserver = RouteObserver<ModalRoute<dynamic>>();
final notificationCenterVisible = ValueNotifier<bool>(false);
