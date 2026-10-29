import 'package:flutter/foundation.dart';

/// A route: the address of what a navigator shows.
///
/// Each navigator has a sealed route type extending this class. A route
/// prints only its own level ([toUrl]); a parent that contains a child route
/// prints its own segments and appends the child's:
///
/// ```dart
/// Url toUrl() => switch (this) {
///   OrdersTab(:final route) => Url(['orders']) + route.toUrl(),
///   SettingsTab(:final route) => Url(['settings']) + route.toUrl(),
/// };
/// ```
///
/// The way back is a static `fromUrl` on the same type, which the root's is
/// handed to the router as `FdrRouter(fromUrl: ShopRoute.fromUrl)`.
abstract class NavRoute {
  const NavRoute();

  /// This level's part of the URL, including the parts of contained routes.
  Url toUrl();
}

/// Thrown by a `fromUrl` that does not know the rest of the URL it was given:
///
/// ```dart
/// static OrderRoute fromUrl(Url url) => switch (url.segments) {
///   [] => const OrderOverview(),
///   ['items', final int item] => OrderItem(item),
///   _ => throw NotFound(url),
/// };
/// ```
///
/// The router then shows the longest prefix of the URL that does parse
/// (`/orders/42` for `/orders/42/nope`), with the not-found page on top; the
/// address bar keeps the URL as typed.
class NotFound implements Exception {
  NotFound(this.url);

  /// The part of the URL the throwing level did not know.
  final Url url;

  @override
  String toString() => 'NotFound: no route for $url';
}

/// A parsed URL, or the part of it one level of routes works on.
///
/// [segments] are the path segments still to be read by this level: a
/// segment that is an integer in canonical form (`42`, not `042` or `+42`) is
/// an [int], every other segment a [String]. So patterns can read
/// `[final int id, ...]`, and each page has exactly one spelling.
///
/// Query parameters are shared by all levels: every level reads [query], and
/// each one prints only the names it owns.
final class Url {
  const Url(this.segments, {this.query = const {}});

  /// Parses the path and query of [uri]; empty segments (a trailing slash)
  /// are dropped. Percent-encoding that is not UTF-8 (`%E9` from an old
  /// Latin-1 link) is kept as typed instead of failing.
  factory Url.parse(Uri uri) {
    final query = <String, List<String>>{};
    for (final pair in uri.query.split('&')) {
      if (pair.isEmpty) continue;
      final equals = pair.indexOf('=');
      final name = equals < 0 ? pair : pair.substring(0, equals);
      final value = equals < 0 ? '' : pair.substring(equals + 1);
      query
          .putIfAbsent(_decode(name, query: true), () => [])
          .add(_decode(value, query: true));
    }
    return Url([
      for (final segment in uri.path.split('/'))
        if (segment.isNotEmpty) _segment(_decode(segment)),
    ], query: query);
  }

  static String _decode(String text, {bool query = false}) {
    try {
      return query ? Uri.decodeQueryComponent(text) : Uri.decodeComponent(text);
    } on FormatException {
      return text;
    }
  }

  static Object _segment(String segment) {
    final number = int.tryParse(segment);
    return number != null && '$number' == segment ? number : segment;
  }

  final List<Object> segments;
  final Map<String, List<String>> query;

  /// The path segments as strings, for levels whose ids may look like
  /// numbers but are strings (`[final String sku]` does not match `123`).
  List<String> get rawSegments => [for (final s in segments) '$s'];

  /// The first value of query parameter [name], like the browser's
  /// `URLSearchParams.get`.
  String? operator [](String name) => query[name]?.firstOrNull;

  /// All values of query parameter [name].
  List<String> all(String name) => query[name] ?? const [];

  /// The part after the first [count] segments, for the next level.
  Url rest(int count) => Url(segments.sublist(count), query: query);

  /// This URL followed by [next]'s segments, with both queries.
  ///
  /// In debug builds, two levels printing the same query parameter with
  /// different values is an error: which one would win is arbitrary.
  Url operator +(Url next) {
    assert(() {
      for (final MapEntry(:key, :value) in next.query.entries) {
        final mine = query[key];
        if (mine != null && !listEquals(mine, value)) {
          throw FlutterError(
            'The query parameter "$key" is printed twice, as $mine by '
            '$this and as $value by $next. Only one level may own a '
            'query parameter.',
          );
        }
      }
      return true;
    }());
    return Url(
      [...segments, ...next.segments],
      query: {...query, ...next.query},
    );
  }

  Uri toUri() => Uri.parse(toString());

  /// The path without the query, e.g. for page identity.
  String get path {
    assert(
      segments.every((s) => s != '' && s != '.' && s != '..'),
      'Url $segments has an empty or dot segment, which does not parse back',
    );
    return '/${segments.map((s) => Uri.encodeComponent('$s')).join('/')}';
  }

  @override
  String toString() {
    if (query.isEmpty) return path;
    final pairs = [
      for (final MapEntry(:key, :value) in query.entries)
        for (final v in value)
          '${Uri.encodeQueryComponent(key)}=${Uri.encodeQueryComponent(v)}',
    ];
    return pairs.isEmpty ? path : '$path?${pairs.join('&')}';
  }

  @override
  bool operator ==(Object other) =>
      other is Url &&
      listEquals(other.segments, segments) &&
      _queryEquals(other.query, query);

  @override
  int get hashCode => Object.hash(
    Object.hashAll(segments),
    Object.hashAllUnordered([
      for (final MapEntry(:key, :value) in query.entries)
        Object.hash(key, Object.hashAll(value)),
    ]),
  );

  static bool _queryEquals(
    Map<String, List<String>> a,
    Map<String, List<String>> b,
  ) {
    if (a.length != b.length) return false;
    for (final MapEntry(:key, :value) in a.entries) {
      final other = b[key];
      if (other == null || !listEquals(other, value)) return false;
    }
    return true;
  }
}
