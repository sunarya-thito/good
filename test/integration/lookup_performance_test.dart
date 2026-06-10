import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:goo2d/goo2d.dart';

void main() {
  if (!const bool.fromEnvironment('INTEGRATION_TEST')) {
    return;
  }
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Goo2D Lookup Scaling Benchmarks (Extreme)', () {
    // Scaling up to 100,000 objects
    final lookupCounts = [100, 1000, 10000, 50000, 100000];

    for (final n in lookupCounts) {
      testWidgets('Lookup.getComponentsInChildren ($n objects)', (
        tester,
      ) async {
        final engine = await GameEngine.create({TickerState.new});
        addTearDown(() => engine.dispose());
        final rootTag = 'root_obj_$n';
        await tester.pumpWidget(
          MaterialApp(
            home: Game(
              engine: engine,
              child: LookupStressScene(count: n, rootTag: rootTag),
            ),
          ),
        );
        await tester.pump();
        final rootObject = GameObject.findWithTag(
          tester.element(find.byType(MaterialApp).first),
          rootTag,
        )!;

        await binding.traceAction(() async {
          final _ = rootObject.getComponentsInChildren<BoxCollider>();
        }, reportKey: 'lookup_downward_$n');
      });
    }

    // Scaling up to 500 layers deep
    final pathDepths = [10, 50, 100, 250, 500];
    for (final d in pathDepths) {
      testWidgets('Lookup.findChildPath (Depth $d)', (tester) async {
        final engine = await GameEngine.create({TickerState.new});
        addTearDown(() => engine.dispose());
        final rootTag = 'path_root_$d';
        await tester.pumpWidget(
          MaterialApp(
            home: Game(
              engine: engine,
              child: PathStressScene(depth: d, rootTag: rootTag),
            ),
          ),
        );
        await tester.pump();
        final rootObject = GameObject.findWithTag(
          tester.element(find.byType(MaterialApp).first),
          rootTag,
        )!;
        final path = List.generate(d, (i) => 'child_$i').join('/');

        await binding.traceAction(() async {
          final _ = rootObject.findChild(path);
        }, reportKey: 'lookup_path_$d');
      });
    }
  });
}

class LookupStressScene extends StatelessWidget {
  final int count;
  final Object rootTag;
  const LookupStressScene({
    super.key,
    required this.count,
    required this.rootTag,
  });

  @override
  Widget build(BuildContext context) {
    return GameObjectWidget(
      tag: rootTag,
      name: 'root',
      children: [_buildWideTree(count)],
    );
  }

  // Use a wider tree to avoid hitting Flutter element depth limits while reaching high N
  Widget _buildWideTree(int total) {
    return GameObjectWidget(
      name: 'container',
      children: List.generate(
        total,
        (i) => GameObjectWidget(
          name: 'obj_$i',
          children: i % 100 == 0 ? [ComponentWidget(BoxCollider.new)] : [],
        ),
      ),
    );
  }
}

class PathStressScene extends StatelessWidget {
  final int depth;
  final Object rootTag;
  const PathStressScene({
    super.key,
    required this.depth,
    required this.rootTag,
  });

  @override
  Widget build(BuildContext context) {
    return GameObjectWidget(
      tag: rootTag,
      name: 'root',
      children: [_buildPathIterative(depth)],
    );
  }

  Widget _buildPathIterative(int n) {
    Widget current = const SizedBox.shrink();
    for (int i = n - 1; i >= 0; i--) {
      current = GameObjectWidget(name: 'child_$i', children: [current]);
    }
    return current;
  }
}
