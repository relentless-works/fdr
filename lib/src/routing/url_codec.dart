/// Bidirectional URL codecs: one declaration yields both parse and print, so
/// they cannot drift apart (Elm `Url.Parser` / purescript-routing-duplex
/// style, with records instead of currying and a user-written exhaustive
/// `switch` instead of generic deriving for sum types).
///
/// Parsing is a "list of successes" parser: every codec yields all the ways
/// it can match, lazily and in priority order, and [UrlCodec.decode] takes
/// the first one that consumed the whole path. A prefix match in an earlier
/// alternative therefore never hides a complete match in a later one.
///
/// Only the root of an app touches [Uri] (through [UrlCodec.decode] and
/// [UrlCodec.encode]); every navigator's codec works on a [Cursor] of
/// segments and query parameters relative to where its parent mounted it.
library;

import 'dart:core' as core;
import 'dart:core';

typedef Unit = ();

/// Read position inside a URL: remaining path segments plus the query map.
final class Cursor {
  const Cursor(this.segments, this.query, this.index);

  final List<String> segments;
  final Map<String, String> query;
  final int index;

  String? get head => index < segments.length ? segments[index] : null;
  Cursor get tail => Cursor(segments, query, index + 1);
  bool get atEnd => index >= segments.length;
  List<String> get remaining => segments.sublist(index);
  Cursor get consumedAll => Cursor(segments, query, segments.length);
}

final class UrlBuilder {
  final List<String> segments = [];
  final Map<String, String> query = {};

  Uri toUri() => segments.isEmpty
      ? Uri(path: '/', queryParameters: query.isEmpty ? null : query)
      : Uri(
          pathSegments: ['', ...segments],
          queryParameters: query.isEmpty ? null : query,
        );
}

typedef Parsed<T> = (T value, Cursor rest);

/// Thrown when a URL part is present but has an invalid value. Unlike "no
/// match" (try the next alternative), this aborts the whole decode: `?tab=x`
/// is an error, not `tab: null`.
final class InvalidUrlValue implements Exception {
  const InvalidUrlValue(this.where, this.raw);
  final String where;
  final String raw;
  @override
  String toString() => 'InvalidUrlValue($where: "$raw")';
}

/// A codec between a typed value and a slice of a URL.
abstract base class UrlCodec<T> {
  const UrlCodec();

  /// All matches at [c], in priority order.
  Iterable<Parsed<T>> parse(Cursor c);

  void print(T value, UrlBuilder b);

  /// Sequence two codecs; the value is a record of both.
  UrlCodec<(T, U)> and<U>(UrlCodec<U> next) => _Pair(this, next);

  /// Total isomorphism to a domain type (partiality is handled by [Case]).
  UrlCodec<U> iso<U>({
    required U Function(T) to,
    required T Function(U) from,
  }) => _Iso(this, to, from);

  /// Absent -> null, null -> prints nothing.
  UrlCodec<T?> get optional => _Optional(this);

  /// Succeeds only if no path segment remains after this codec.
  UrlCodec<T> get atEnd => _AtEnd(this);

  /// `null` means "no route matches" or "a value was invalid"; the caller
  /// decides between a not-found page and a sanitised redirect.
  T? decode(Uri uri) {
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    try {
      for (final (value, rest) in parse(
        Cursor(segments, uri.queryParameters, 0),
      )) {
        if (rest.atEnd) return value;
      }
      return null;
    } on InvalidUrlValue {
      return null;
    }
  }

  Uri encode(T value) {
    final b = UrlBuilder();
    print(value, b);
    return b.toUri();
  }
}

/// A codec whose value is known statically, so it can prefix another codec
/// without contributing to the value (`lit('books').then(Seg.int)`).
abstract base class ConstCodec<T> extends UrlCodec<T> {
  const ConstCodec(this.value);

  final T value;

  UrlCodec<U> then<U>(UrlCodec<U> next) => _Then(this, next);
}

final class _Lit extends ConstCodec<Unit> {
  const _Lit(this.segment) : super(());

  final String segment;

  @override
  Iterable<Parsed<Unit>> parse(Cursor c) sync* {
    if (c.head == segment) yield ((), c.tail);
  }

  @override
  void print(Unit value, UrlBuilder b) => b.segments.add(segment);
}

final class _End extends ConstCodec<Unit> {
  const _End() : super(());

  @override
  Iterable<Parsed<Unit>> parse(Cursor c) sync* {
    if (c.atEnd) yield ((), c);
  }

  @override
  void print(Unit value, UrlBuilder b) {}
}

/// One path segment converted both ways.
final class Seg<T> extends UrlCodec<T> {
  const Seg({required this.from, required this.to});

  final T? Function(String) from;
  final String Function(T) to;

  static const string = Seg<String>(from: _id, to: _id);
  static const int = Seg<core.int>(from: core.int.tryParse, to: _str);

  static Seg<E> enumOf<E extends Enum>(List<E> values) => Seg(
    from: (s) => values.where((e) => e.name == s).firstOrNull,
    to: (e) => e.name,
  );

  @override
  Iterable<Parsed<T>> parse(Cursor c) sync* {
    final head = c.head;
    if (head == null) return;
    final v = from(head);
    if (v != null) yield (v, c.tail);
  }

  @override
  void print(T value, UrlBuilder b) => b.segments.add(to(value));
}

/// One query parameter converted both ways (required unless `.optional`).
final class Query<T> extends UrlCodec<T> {
  const Query(this.name, {required this.from, required this.to});

  final String name;
  final T? Function(String) from;
  final String Function(T) to;

  static Query<String> string(String name) => Query(name, from: _id, to: _id);

  static Query<core.int> int(String name) =>
      Query(name, from: core.int.tryParse, to: _str);

  /// A whole route of another navigator inside one query parameter, e.g.
  /// `?next=%2Forders%2F42` for a login page's return target.
  static Query<R> route<R>(String name, UrlCodec<R> codec) => Query(
    name,
    from: (s) => codec.decode(Uri.parse(s)),
    to: (r) => codec.encode(r).toString(),
  );

  @override
  Iterable<Parsed<T>> parse(Cursor c) sync* {
    final raw = c.query[name];
    if (raw == null) return;
    final v = from(raw);
    // a present query parameter with a bad value is an error, not "absent"
    if (v == null) throw InvalidUrlValue('?$name', raw);
    yield (v, c);
  }

  @override
  void print(T value, UrlBuilder b) => b.query[name] = to(value);
}

/// Consumes whatever is left (segments and query) as a [Uri]; for catch-all
/// "not found" routes that keep the typed-in URL in the address bar.
final class Rest extends UrlCodec<Uri> {
  const Rest();

  @override
  Iterable<Parsed<Uri>> parse(Cursor c) sync* {
    yield (
      Uri(
        pathSegments: ['', ...c.remaining],
        queryParameters: c.query.isEmpty ? null : c.query,
      ),
      c.consumedAll,
    );
  }

  @override
  void print(Uri value, UrlBuilder b) {
    b.segments.addAll(value.pathSegments.where((s) => s.isNotEmpty));
    b.query.addAll(value.queryParameters);
  }
}

/// Prints one value; only obtainable from [Case.bind] or [LensCase.bind], so
/// a [SumCodec.select] that hands a value to the wrong case does not compile.
final class Printer {
  const Printer._(this._print);

  final void Function(UrlBuilder b) _print;
}

/// One parse alternative of a [SumCodec].
abstract interface class Alternative<T> {
  Iterable<Parsed<T>> parse(Cursor c);
}

/// Embeds a codec for a subtype [S] into the sum of the sealed supertype [T].
final class Case<T, S extends T> implements Alternative<T> {
  const Case(this.codec);

  final UrlCodec<S> codec;

  @override
  Iterable<Parsed<T>> parse(Cursor c) => codec.parse(c);

  Printer bind(S value) => Printer._((b) => codec.print(value, b));
}

/// A parse-only alternative (legacy URL, shortcut): it is never printed, so
/// canonical URLs replace it in the address bar.
Alternative<T> alias<T, A>(UrlCodec<A> codec, T Function(A) to) =>
    _Alias<T, A>(codec, to);

final class _Alias<T, A> implements Alternative<T> {
  const _Alias(this.codec, this.to);

  final UrlCodec<A> codec;
  final T Function(A) to;

  @override
  Iterable<Parsed<T>> parse(Cursor c) =>
      codec.parse(c).map((r) => (to(r.$1), r.$2));
}

/// Sum type: parse yields the matches of all cases in order; print goes
/// through `select`, which the user writes as an exhaustive switch over the
/// sealed class, so a forgotten case is a compile error.
final class SumCodec<T> extends UrlCodec<T> {
  const SumCodec({required this.cases, required this.select});

  final List<Alternative<T>> cases;
  final Printer Function(T value) select;

  @override
  Iterable<Parsed<T>> parse(Cursor c) sync* {
    for (final alternative in cases) {
      yield* alternative.parse(c);
    }
  }

  @override
  void print(T value, UrlBuilder b) => select(value)._print(b);
}

final class _Pair<A, B> extends UrlCodec<(A, B)> {
  const _Pair(this.first, this.second);

  final UrlCodec<A> first;
  final UrlCodec<B> second;

  @override
  Iterable<Parsed<(A, B)>> parse(Cursor c) sync* {
    for (final (a, afterA) in first.parse(c)) {
      for (final (b, afterB) in second.parse(afterA)) {
        yield ((a, b), afterB);
      }
    }
  }

  @override
  void print((A, B) value, UrlBuilder b) {
    first.print(value.$1, b);
    second.print(value.$2, b);
  }
}

final class _Then<P, T> extends UrlCodec<T> {
  const _Then(this.prefix, this.next);

  final ConstCodec<P> prefix;
  final UrlCodec<T> next;

  @override
  Iterable<Parsed<T>> parse(Cursor c) sync* {
    for (final (_, afterPrefix) in prefix.parse(c)) {
      yield* next.parse(afterPrefix);
    }
  }

  @override
  void print(T value, UrlBuilder b) {
    prefix.print(prefix.value, b);
    next.print(value, b);
  }
}

final class _Iso<T, U> extends UrlCodec<U> {
  const _Iso(this.inner, this.to, this.from);

  final UrlCodec<T> inner;
  final U Function(T) to;
  final T Function(U) from;

  @override
  Iterable<Parsed<U>> parse(Cursor c) =>
      inner.parse(c).map((r) => (to(r.$1), r.$2));

  @override
  void print(U value, UrlBuilder b) => inner.print(from(value), b);
}

final class _Optional<T> extends UrlCodec<T?> {
  const _Optional(this.inner);

  final UrlCodec<T> inner;

  @override
  Iterable<Parsed<T?>> parse(Cursor c) sync* {
    yield* inner.parse(c);
    yield (null, c);
  }

  @override
  void print(T? value, UrlBuilder b) {
    if (value != null) inner.print(value, b);
  }
}

final class _AtEnd<T> extends UrlCodec<T> {
  const _AtEnd(this.inner);

  final UrlCodec<T> inner;

  @override
  Iterable<Parsed<T>> parse(Cursor c) =>
      inner.parse(c).where((r) => r.$2.atEnd);

  @override
  void print(T value, UrlBuilder b) => inner.print(value, b);
}

ConstCodec<Unit> lit(String segment) => _Lit(segment);
const ConstCodec<Unit> end = _End();

String _id(String s) => s;
String _str(Object o) => o.toString();

/// A [SumCodec] case built from a lens: parse embeds the child route, print
/// is bound to the child value the parent's `select` extracted.
final class LensCase<P, C> implements Alternative<P> {
  const LensCase(this.codec, this.embed);

  final UrlCodec<C> codec;
  final P Function(C) embed;

  @override
  Iterable<Parsed<P>> parse(Cursor c) =>
      codec.parse(c).map((r) => (embed(r.$1), r.$2));

  Printer bind(C child) => Printer._((b) => codec.print(child, b));
}
