import 'package:fdr/fdr.dart';
import 'package:fdr/src/routing/fdr_router.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'example_app.dart';

Url _parse(String url) => Url.parse(Uri.parse(url));

void main() {
  group('Url', () {
    test('only integers in canonical form become ints', () {
      expect(
        _parse('/orders/42/-1/007/+42/0x2A/12345678901234567890/a%20b/')
            .segments,
        ['orders', 42, -1, '007', '+42', '0x2A', '12345678901234567890', 'a b'],
      );
    });

    test('integers beyond 2^53 - 1 stay strings on every platform', () {
      expect(_parse('/9007199254740991/-9007199254740991').segments, [
        9007199254740991,
        -9007199254740991,
      ]);
      for (final segment in [
        '9007199254740992',
        '-9007199254740992',
        '9223372036854775807', // an int on the VM only
        '-9223372036854775808',
        '9223372036854776000', // an int on the web only
        '100000000000000000000',
      ]) {
        expect(_parse('/$segment').segments, [segment]);
      }
    });

    test('dot segments are resolved, also in a relative path', () {
      // Uri removes them from absolute paths only
      for (final (input, segments) in [
        ('../x', ['x']),
        ('.', <Object>[]),
        ('..', <Object>[]),
        ('a/..', <Object>[]),
        ('../../orders/42', ['orders', 42]),
        ('%2E%2E/a/%2e/b', ['a', 'b']),
        ('/a/../b/./c', ['b', 'c']),
      ]) {
        final url = _parse(input);
        expect(url.segments, segments, reason: input);
        expect(_parse('$url'), url, reason: input);
      }
    });

    test('an escape that is not UTF-8 is read as Latin-1, on its own', () {
      for (final (input, segment, value, printed) in [
        ('/caf%E9', 'café', null, '/caf%C3%A9'),
        // the other escapes and '+' in the same component still decode
        ('/a%20b%E9', 'a bé', null, '/a%20b%C3%A9'),
        ('/x?q=a+b%E9', 'x', 'a bé', '/x?q=a+b%C3%A9'),
        ('/x?q=%2B%E9%20', 'x', '+é ', '/x?q=%2B%C3%A9+'),
        ('/%C3/%C3%A9', 'Ã', null, '/%C3%83/%C3%A9'),
      ]) {
        final url = _parse(input);
        expect(url.segments.first, segment, reason: input);
        expect(url['q'], value, reason: input);
        expect('$url', printed, reason: input);
        expect(_parse(printed), url, reason: input);
      }
    });

    test('query parameters: the first value, or all of them', () {
      final url = _parse('/x?a=1&a=2&b=');
      expect(url['a'], '1');
      expect(url.all('a'), ['1', '2']);
      expect(url['b'], '');
      expect(url['c'], isNull);
      expect(url.all('c'), isEmpty);
    });

    test('rawSegments are the segments as strings', () {
      final url = _parse('/sku/123/007/a%20b');
      expect(url.segments, ['sku', 123, '007', 'a b']);
      expect(url.rawSegments, ['sku', '123', '007', 'a b']);
      // a level with string ids matches ids that look like numbers too
      final id = switch (url.rawSegments) {
        ['sku', final String id, ...] => id,
        _ => null,
      };
      expect(id, '123');
    });

    test('equality ignores the order of query parameters, not of values', () {
      final url = _parse('/a/1?x=1&y=2&y=3');
      final reordered = _parse('/a/1?y=2&x=1&y=3');
      expect(reordered, url);
      expect(reordered.hashCode, url.hashCode);
      expect({url, reordered}, hasLength(1));

      expect(_parse('/a/1?x=1&y=3&y=2'), isNot(url));
      expect(_parse('/a/1?x=1&y=2'), isNot(url));
      expect(_parse('/a/1?x=1&y=2&y=3&z='), isNot(url));
      expect(_parse('/a/2?x=1&y=2&y=3'), isNot(url));
      expect(_parse('/a/1'), const Url(['a', 1]));
      expect(_parse('/a/1'), isNot(const Url(['a', '1'])));
    });

    test('a segment that is neither an int nor a String is an error', () {
      // they would not parse back, and a double prints differently per
      // platform
      for (final segment in <Object>[42.5, true, TextDirection.ltr]) {
        expect(() => Url([segment]).toString(), throwsAssertionError);
      }
    });

    test('scheme, authority and fragment are not part of a Url', () {
      expect('${_parse('https://shop.example/x?a=1#frag')}', '/x?a=1');
      expect('${_parse('/x#frag?a=1')}', '/x');
    });

    test('rest hands the remainder and the query to the next level', () {
      final rest = _parse('/a/b/c?q=1').rest(1).rest(1);
      expect(rest.segments, ['c']);
      expect(rest['q'], '1');
    });

    test('prints encoded, with query parameters in order', () {
      const url = Url(
        ['orders', 42, 'a b'],
        query: {
          'q': ['x y', 'z'],
          'empty': [],
        },
      );
      expect('$url', '/orders/42/a%20b?q=x+y&q=z');
      expect(url.path, '/orders/42/a%20b');
      expect(const Url([]).toString(), '/');
    });

    test('rest past the end is not found', () {
      final url = _parse('/a/b?q=1');
      expect(url.rest(2).segments, isEmpty);
      expect(url.rest(2)['q'], '1');
      expect(
        () => url.rest(3),
        throwsA(isA<NotFound>().having((e) => e.url, 'url', url)),
      );
    });

    test('a parsed Url, like a const one, cannot be changed', () {
      final url = _parse('/a/b?x=1');
      final rest = url.rest(1);
      expect(() => url.segments.add('c'), throwsUnsupportedError);
      expect(() => url.query.remove('x'), throwsUnsupportedError);
      expect(() => url.all('x').add('2'), throwsUnsupportedError);
      expect(() => rest.segments.add('c'), throwsUnsupportedError);
      expect(() => rest.query['y'] = [], throwsUnsupportedError);
      expect(() => rest.all('x').sort(), throwsUnsupportedError);
      expect('$url', '/a/b?x=1');
    });

    test('+ appends segments and merges the queries', () {
      final url =
          const Url(
            ['a'],
            query: {
              'x': ['1'],
            },
          ) +
          const Url(
            [2],
            query: {
              'y': ['2'],
            },
          );
      expect(
        url,
        const Url(
          ['a', 2],
          query: {
            'y': ['2'],
            'x': ['1'],
          },
        ),
      );
    });

    test('+ with a query name without values: no collision, no winner', () {
      const value = Url(
        [],
        query: {
          'a': ['1'],
        },
      );
      const none = Url(['x'], query: {'a': []});
      expect('${value + none}', '/x?a=1');
      expect('${none + value}', '/x?a=1');
      expect((value + none).query, {
        'a': ['1'],
      });
    });

    test('Urls that print the same are equal', () {
      void same(Url a, Url b) {
        expect('$a', '$b');
        expect(a, b);
        expect(a.hashCode, b.hashCode);
      }

      // a string id that looks like a number parses back as an int
      same(_parse('${const Url(['42'])}'), const Url(['42']));
      same(const Url(['42']), const Url([42]));
      // a name without values prints nothing
      same(
        const Url(
          ['x'],
          query: {
            'a': [],
            'b': ['1'],
          },
        ),
        const Url(
          ['x'],
          query: {
            'b': ['1'],
            'c': [],
          },
        ),
      );
      expect(
        const Url(
          [],
          query: {
            'a': ['1', '2'],
          },
        ),
        isNot(
          const Url(
            [],
            query: {
              'a': ['2', '1'],
            },
          ),
        ),
      );
      expect(const Url(['x']), isNot(const Url(['x', 'y'])));
    });

    test('two levels printing one query parameter differently is an error', () {
      expect(
        () =>
            const Url(
              ['a'],
              query: {
                'page': ['1'],
              },
            ) +
            const Url(
              [],
              query: {
                'page': ['2'],
              },
            ),
        throwsA(
          isA<FlutterError>().having(
            (e) => e.message,
            'message',
            contains('"page" is printed twice'),
          ),
        ),
      );
      // the same value twice is fine
      expect(
        '${const Url(['a'], query: {
              'page': ['1'],
            }) + const Url([], query: {
              'page': ['1'],
            })}',
        '/a?page=1',
      );
    });
  });

  group('the path and query routed for an incoming URI', () {
    String route(String uri) =>
        '${FdrRouteInformationParser.appPath(Uri.parse(uri))}';

    test('a path keeps its query and drops the fragment', () {
      expect(route('/orders/42?x=1&x=2#top'), '/orders/42?x=1&x=2');
      expect(route(''), '/');
      expect(route('https://shop.example'), '/');
      expect(route('https://shop.example/orders?x=1'), '/orders?x=1');
      expect(route('http://shop.example:8080/orders'), '/orders');
    });

    test('a custom scheme has its host as the first segment', () {
      expect(route('myapp://orders/42?x=1'), '/orders/42?x=1');
      // lowercased, like every host
      expect(route('myapp://Orders/42'), '/orders/42');
      expect(route('myapp:/orders/42'), '/orders/42');
      expect(route('myapp://'), '/');
      expect(route('myapp://orders#/settings'), '/orders');
    });

    test('a web link with the hash URL strategy is routed by the fragment', () {
      expect(route('https://shop.example/#/orders/42?x=1'), '/orders/42?x=1');
      expect(route('http://shop.example#/orders'), '/orders');
      expect(route('https://shop.example/#/'), '/');
      // a fragment that is no path, or one after a path, is no route
      expect(route('https://shop.example/#top'), '/');
      expect(route('https://shop.example/app#/orders'), '/app');
    });
  });

  group('URLs that do not parse completely', () {
    final parser = FdrRouteInformationParser(fromUrl: AppRoute.fromUrl);

    (String?, String?) resolve(String url) {
      final (route, missing) = parser.resolve(_parse(url));
      return (route?.toUrl().toString(), missing?.toString());
    }

    test('fall back to the longest prefix that parses', () {
      expect(resolve('/orders/42'), ('/orders/42', null));
      expect(resolve('/orders/42/nope'), ('/orders/42', '/orders/42/nope'));
      expect(resolve('/orders/abc?x=1'), ('/orders', '/orders/abc?x=1'));
      expect(resolve('/orders/42/items/3/x'), (
        '/orders/42/items/3',
        '/orders/42/items/3/x',
      ));
      expect(resolve('/settings/x/y'), ('/settings', '/settings/x/y'));
      expect(resolve('/nope'), ('/orders', '/nope'));
    });

    test('a relative location with dot segments prints back', () async {
      // e.g. the hash URL http://host/#../x
      final snapshot = await parser.parseRouteInformation(
        RouteInformation(uri: Uri.parse('../x')),
      );
      expect('${snapshot.missing}', '/x');
      expect('${parser.restoreRouteInformation(snapshot)!.uri}', '/x');
    });

    test('a level that reads past the end of the URL is not a bug', () {
      final errors = <FlutterErrorDetails>[];
      final previous = FlutterError.onError;
      FlutterError.onError = errors.add;
      addTearDown(() => FlutterError.onError = previous);

      // skips a prefix without a list pattern
      final skipping = FdrRouteInformationParser<AppRoute>(
        fromUrl: (url) => AppRoute.fromUrl(url.rest(1)),
      );
      final (route, missing) = skipping.resolve(_parse('/'));
      expect(route, isNull);
      expect('$missing', '/');
      expect(errors, isEmpty);
    });

    test('a fromUrl that fails otherwise is reported as a bug', () {
      final errors = <FlutterErrorDetails>[];
      final previous = FlutterError.onError;
      FlutterError.onError = errors.add;
      addTearDown(() => FlutterError.onError = previous);

      final broken = FdrRouteInformationParser<AppRoute>(
        fromUrl: (url) => throw StateError('bug'),
      );
      final (route, missing) = broken.resolve(_parse('/orders'));
      expect(route, isNull);
      expect('$missing', '/orders');
      expect(errors.single.exception, isA<StateError>());
    });
  });
}
