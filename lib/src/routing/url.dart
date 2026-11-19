import 'dart:convert';

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
/// (`/orders/42` for `/orders/42/nope`), with the not-found page on top. The
/// address bar keeps the whole URL, not the prefix's, as [Url.parse] read
/// it and printed the canonical way: `/orders/42/./nope/` as
/// `/orders/42/nope`, a Latin-1 `%E9` as UTF-8 `%C3%A9`, `?q=a%20b` as
/// `?q=a+b`.
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
/// segment that is an integer in canonical form (`42`, not `042` or `+42`)
/// and within ±(2^53 - 1), which every platform represents exactly, is an
/// [int], every other segment a [String]. So patterns can read
/// `[final int id, ...]`, and each page has exactly one spelling. A `toUrl`
/// prints only ints and Strings too: an enum or a bool as a String.
///
/// Query parameters are shared by all levels: every level reads [query], and
/// each one prints only the names it owns.
final class Url {
  const Url(this.segments, {this.query = const {}});

  /// Parses the path and query of [uri]; its scheme, authority and fragment
  /// are ignored. Empty segments (a trailing slash) are dropped, and dot
  /// segments are resolved, also in a relative path (`../x` is `/x`).
  /// Percent-encoding that is not UTF-8 (`%E9` from an old Latin-1 link) is
  /// read as Latin-1 instead of failing, and printed as UTF-8.
  ///
  /// Like a const Url, the result cannot be changed: copy a list before
  /// sorting it (`[...url.all('tag')]..sort()`).
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
    final segments = <Object>[];
    for (final segment in uri.path.split('/').map(_decode)) {
      if (segment == '..') {
        if (segments.isNotEmpty) segments.removeLast();
      } else if (segment.isNotEmpty && segment != '.') {
        segments.add(_segment(segment));
      }
    }
    // every level and the router hold the same collections
    return Url(
      List.unmodifiable(segments),
      query: Map.unmodifiable({
        for (final MapEntry(:key, :value) in query.entries)
          key: List<String>.unmodifiable(value),
      }),
    );
  }

  static String _decode(String text, {bool query = false}) {
    try {
      return query ? Uri.decodeQueryComponent(text) : Uri.decodeComponent(text);
    } on FormatException {
      // not UTF-8: decode each run of escapes on its own, as Latin-1 if it
      // is not UTF-8, so the other escapes (and '+') keep their meaning
      return (query ? text.replaceAll('+', ' ') : text).replaceAllMapped(
        _escapes,
        (match) {
          final run = match[0]!;
          final bytes = [
            for (var i = 0; i < run.length; i += 3)
              int.parse(run.substring(i + 1, i + 3), radix: 16),
          ];
          try {
            return utf8.decode(bytes);
          } on FormatException {
            return latin1.decode(bytes);
          }
        },
      );
    }
  }

  static final _escapes = RegExp('(?:%[0-9A-Fa-f]{2})+');

  // the largest integer every platform represents exactly (the web's
  // doubles), so that a URL has the same segment types everywhere
  static const _maxInt = 9007199254740991;

  static Object _segment(String segment) {
    final number = int.tryParse(segment);
    return number != null &&
            -_maxInt <= number &&
            number <= _maxInt &&
            '$number' == segment
        ? number
        : segment;
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

  /// The part after the first [count] segments, for the next level. A URL
  /// with fewer segments throws [NotFound], like any other unknown URL.
  Url rest(int count) {
    if (count > segments.length) throw NotFound(this);
    return Url(List.unmodifiable(segments.sublist(count)), query: query);
  }

  /// This URL followed by [next]'s segments, with both queries. A query name
  /// without values prints nothing, so it neither collides nor wins.
  ///
  /// In debug builds, two levels printing the same query parameter with
  /// different values is an error: which one would win is arbitrary.
  Url operator +(Url next) {
    assert(() {
      for (final MapEntry(:key, :value) in next.query.entries) {
        final mine = query[key] ?? const [];
        if (mine.isNotEmpty && value.isNotEmpty && !listEquals(mine, value)) {
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
      query: {
        for (final MapEntry(:key, :value) in query.entries.followedBy(
          next.query.entries,
        ))
          if (value.isNotEmpty) key: value,
      },
    );
  }

  Uri toUri() => Uri.parse(toString());

  /// The path without the query, e.g. for page identity.
  String get path {
    assert(
      segments.every((s) => s is int || s is String),
      'Url $segments has a segment that is neither an int nor a String, '
      'which does not parse back; print it as a String first',
    );
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

  /// Urls are equal when they print the same path and the same values per
  /// query name: `Url(['42'])` equals `Url([42])`, and a name without values
  /// equals no name. The order of the names does not matter.
  @override
  bool operator ==(Object other) =>
      other is Url &&
      listEquals(other.rawSegments, rawSegments) &&
      _queryIn(other.query, query) &&
      _queryIn(query, other.query);

  @override
  int get hashCode => Object.hash(
    Object.hashAll(rawSegments),
    Object.hashAllUnordered([
      for (final MapEntry(:key, :value) in query.entries)
        if (value.isNotEmpty) Object.hash(key, Object.hashAll(value)),
    ]),
  );

  static bool _queryIn(
    Map<String, List<String>> a,
    Map<String, List<String>> b,
  ) => a.entries.every((e) => listEquals(e.value, b[e.key] ?? const []));
}
