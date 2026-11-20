import 'dart:async';

import 'package:cupertino_ui/cupertino_ui.dart'
    show CupertinoPageTransition, CupertinoRouteTransitionMixin;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:material_ui/material_ui.dart'
    show
        DialogRoute,
        MaterialLocalizations,
        MaterialRouteTransitionMixin,
        Theme;
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart'
    show UrlLauncherPlatform;

import '../routing/url.dart';
import 'external_href.dart'
    if (dart.library.js_interop) 'external_href_web.dart';

part 'declarative_navigator.dart';
part 'flat_page.dart';
part 'nav_entry.dart';
part 'nav_host.dart';
part 'nav_scope.dart';
part 'page_mapper.dart';
part 'page_stack.dart';
part 'pages.dart';
part 'route_link.dart';
part 'routing_scope.dart';
part 'stateful_navigator.dart';
part 'stateless_navigator.dart';
part 'tabs_page.dart';
