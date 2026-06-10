import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:goo2d/goo2d.dart';

void main() {
  if (!const bool.fromEnvironment('INTEGRATION_TEST')) {
    return;
  }
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Goo2D Transform Scaling Benchmarks (Profiler)', () {
    final depths = [5, 10, 25, 50, 75, 100, 125, 150];
    for (final d in depths) {
      testWidgets('Transform.worldMatrixDeep (Depth $d)', (tester) async {
        final engine = await GameEngine.create({TickerState.new});
        addTearDown(() => engine.dispose());
        final rootTag = 'root_obj_$d';
        final leafTag = 'leaf_obj_$d';

        await tester.pumpWidget(
          MaterialApp(
            home: Game(
              engine: engine,
              child: WorldMatrixStressScene(
                depth: d,
                rootTag: rootTag,
                leafTag: leafTag,
              ),
            ),
          ),
        );
        await tester.pump();

        final context = tester.element(find.byType(MaterialApp).first);
        final rootObject = GameObject.findWithTag(context, rootTag)!;
        final leafObject = GameObject.findWithTag(context, leafTag)!;
        final rootTransform = rootObject.getComponent<ObjectTransform>();
        final leafTransform = leafObject.getComponent<ObjectTransform>();

        await binding.traceAction(() async {
          rootTransform.localPosition = Vector2(
            rootTransform.localPosition.x + 0.1,
            0,
          );
          final _ = leafTransform.worldMatrix;
        }, reportKey: 'transform_depth_$d');
      });
    }
  });
}

class WorldMatrixStressScene extends StatelessWidget {
  final int depth;
  final Object rootTag;
  final Object leafTag;
  const WorldMatrixStressScene({
    super.key,
    required this.depth,
    required this.rootTag,
    required this.leafTag,
  });

  @override
  Widget build(BuildContext context) {
    return _buildDepth(depth, 0);
  }

  Widget _buildDepth(int max, int current) {
    final bool isRoot = current == 0;
    final bool isLeaf = current == max;
    return GameObjectWidget(
      tag: isRoot ? rootTag : (isLeaf ? leafTag : null),
      name: isRoot ? 'root' : (isLeaf ? 'leaf' : 'd_$current'),
      children: [
        ComponentWidget(ObjectTransform.new),
        if (!isLeaf) _buildDepth(max, current + 1),
      ],
    );
  }
}
