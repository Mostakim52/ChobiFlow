import 'package:chobiflow/smart_stacks.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('cosine', () {
    test('identical vectors score 1', () {
      expect(cosine([1, 0, 0], [1, 0, 0]), closeTo(1, 1e-9));
    });
    test('orthogonal vectors score 0', () {
      expect(cosine([1, 0], [0, 1]), closeTo(0, 1e-9));
    });
  });

  group('discoverClusters invents categories', () {
    // Two tight visual groups + one loner.
    final a1 = [1.0, 0.0, 0.0, 0.0];
    final a2 = [0.98, 0.02, 0.0, 0.0];
    final a3 = [0.97, 0.03, 0.01, 0.0];
    final b1 = [0.0, 0.0, 1.0, 0.0];
    final b2 = [0.0, 0.01, 0.98, 0.02];
    final b3 = [0.01, 0.0, 0.97, 0.03];
    final loner = [0.0, 1.0, 0.0, 0.0];

    test('finds two groups, loner stays out', () {
      final groups = discoverClusters(
        vecs: [a1, a2, a3, b1, b2, b3, loner],
        keys: const [{}, {}, {}, {}, {}, {}, {}],
        threshold: 0.9,
        minSize: 3,
      );
      expect(groups.length, 2);
      for (final g in groups) {
        expect(g.length, 3);
      }
      final flat = groups.expand((g) => g).toSet();
      expect(flat.contains(6), false);
    });

    test('keyword overlap boosts near-misses together', () {
      final x = [1.0, 0.2, 0.0, 0.0];
      final y = [0.9, 0.35, 0.0, 0.0]; // cosine ~0.97 already high; use keys
      final groups = discoverClusters(
        vecs: [x, y, loner, b1],
        keys: [
          {'boarding', 'flight'},
          {'boarding', 'gate'},
          {'meme'},
          {'receipt'}
        ],
        threshold: 0.99,
        minSize: 2,
      );
      // x,y share 'boarding' -> boosted over the bar, others excluded
      expect(groups.length, 1);
      expect(groups.first.toSet(), {0, 1});
    });
  });

  group('nameCluster', () {
    test('names from inside-words', () {
      final n = nameCluster(
        titles: ['Screenshot 20261007'],
        keys: [
          {'boarding', 'flight'},
          {'boarding', 'gate'}
        ],
        fallback: 'Smart Stack 1',
      );
      expect(n.name.toLowerCase(), contains('boarding'));
    });
    test('falls back cleanly with no words', () {
      final n = nameCluster(
        titles: ['IMG 1'],
        keys: const [{}, {}],
        fallback: 'Smart Stack 4',
      );
      expect(n.name, 'Smart Stack 4');
    });
    test('screenshot word never becomes the name', () {
      final n = nameCluster(
        titles: ['Screenshot 20261007', 'Screenshot 20261008'],
        keys: const [
          {'screenshot', 'reply'},
          {'screenshot', 'birthday'}
        ],
        fallback: 'Smart Stack 9',
      );
      expect(n.name.toLowerCase(), isNot(contains('screenshot')));
      expect(n.name.toLowerCase(), contains('reply'));
      expect(n.alt.toLowerCase(), contains('birthday'));
    });
  });

  group('refineLargeGroups', () {
    test('splits a bridged mega-cluster, keeps total', () {
      final a = [1.0, 0.0];
      final b = [0.0, 1.0];
      final bridge = [0.7071, 0.7071];
      final vecs = [
        for (var i = 0; i < 8; i++) a,
        bridge,
        for (var i = 0; i < 8; i++) b,
      ];
      final keys = List<Set<String>>.generate(17, (_) => <String>{});
      final refined = refineLargeGroups(
        groups: [
          List<int>.generate(17, (i) => i)
        ],
        vecs: vecs,
        keys: keys,
        baseThreshold: 0.65,
        maxSize: 10,
        minSize: 3,
      );
      // bridge (cos ~0.707) drops out at 0.73; A and B survive separately
      expect(refined.length, 2);
      expect(refined.expand((g) => g).length, 16);
    });
    test('leaves small groups alone', () {
      final vecs = List<List<double>>.generate(
          5, (_) => [1.0, 0.0]);
      final keys = List<Set<String>>.generate(5, (_) => <String>{});
      final refined = refineLargeGroups(
        groups: [
          [0, 1, 2, 3, 4]
        ],
        vecs: vecs,
        keys: keys,
        baseThreshold: 0.78,
      );
      expect(refined.length, 1);
      expect(refined.first.length, 5);
    });
  });
}
