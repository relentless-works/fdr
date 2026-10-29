import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/link.dart';

import '../routing/url.dart';
import 'external_href.dart'
    if (dart.library.js_interop) 'external_href_web.dart';

part 'declarative_navigator.dart';
part 'flat_page.dart';
part 'hot_reload.dart';
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
