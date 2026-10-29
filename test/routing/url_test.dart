import 'package:fdr/fdr.dart';
import 'package:fdr/src/routing/fdr_router.dart';
import 'package:flutter/foundation.dart';
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

    test('query parameters: the first value, or all of them', () {
      final url = _parse('/x?a=1&a=2&b=');
      expect(url['a'], '1');
      expect(url.all('a'), ['1', '2']);
      expect(url['b'], '');
      expect(url['c'], isNull);
      expect(url.all('c'), isEmpty);
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
