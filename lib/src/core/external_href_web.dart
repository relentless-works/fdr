import 'dart:ui_web' as ui_web;

/// [href] as the absolute URL the browser shows for it: with the URL
/// strategy's prefix (`#` for the hash strategy) and the page's base.
String externalHref(String href) {
  final prepared = ui_web.urlStrategy?.prepareExternalUrl(href) ?? href;
  return Uri.base.resolve(prepared).toString();
}
