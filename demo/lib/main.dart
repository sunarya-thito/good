import 'package:flutter/material.dart';

import 'demos/collision/collision_demo.dart';
import 'demos/performance/particles_demo.dart';
import 'demos/physics/particles_physics_demo.dart';

class DemoItem {
  final String id;
  final String title;
  final Widget Function() builder;

  const DemoItem({
    required this.id,
    required this.title,
    required this.builder,
  });
}

class DemoSubcategory {
  final String title;
  final List<DemoItem> items;
  const DemoSubcategory({required this.title, required this.items});
}

class DemoCategory {
  final String title;
  final List<DemoSubcategory> subcategories;
  const DemoCategory({required this.title, required this.subcategories});
}

final List<DemoCategory> _demoRegistry = [
  DemoCategory(
    title: 'Performance',
    subcategories: [
      DemoSubcategory(
        title: 'Comparison',
        items: [
          DemoItem(
            id: 'particles',
            title: 'Particles',
            builder: () => const ParticlesDemo(),
          ),
        ],
      ),
    ],
  ),
  DemoCategory(
    title: 'Collision',
    subcategories: [
      DemoSubcategory(
        title: 'Comparison',
        items: [
          DemoItem(
            id: 'collision_raining_balls',
            title: 'Raining Balls',
            builder: () => const CollisionDemo(),
          ),
        ],
      ),
    ],
  ),
  DemoCategory(
    title: 'Physics',
    subcategories: [
      DemoSubcategory(
        title: 'Comparison',
        items: [
          DemoItem(
            id: 'particles_physics',
            title: 'Physics Particles',
            builder: () => const ParticlesPhysicsDemo(),
          ),
        ],
      ),
    ],
  ),
];

void main() => runApp(const DemoApp());

class DemoApp extends StatelessWidget {
  const DemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: const DemoShell(),
    );
  }
}

class DemoShell extends StatefulWidget {
  const DemoShell({super.key});

  @override
  State<DemoShell> createState() => _DemoShellState();
}

class _DemoShellState extends State<DemoShell> {
  bool _sidebarVisible = true;
  DemoItem? _selected;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          ClipRect(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
              width: _sidebarVisible ? 240.0 : 0.0,
              child: SizedBox(
                width: 240,
                child: _Sidebar(
                  categories: _demoRegistry,
                  selected: _selected,
                  onSelect: (item) => setState(() => _selected = item),
                ),
              ),
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                _buildContent(),
                Positioned(
                  top: 4,
                  left: 4,
                  child: IconButton(
                    icon: Icon(_sidebarVisible ? Icons.menu_open : Icons.menu),
                    onPressed: () =>
                        setState(() => _sidebarVisible = !_sidebarVisible),
                    tooltip: _sidebarVisible ? 'Hide sidebar' : 'Show sidebar',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_selected == null) {
      return const Center(child: Text('Select a demo from the sidebar'));
    }
    return _selected!.builder();
  }
}

class _Sidebar extends StatelessWidget {
  final List<DemoCategory> categories;
  final DemoItem? selected;
  final void Function(DemoItem) onSelect;

  const _Sidebar({
    required this.categories,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 48, 16, 8),
          child: Text('goo2d demos', style: theme.textTheme.titleMedium),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              for (final cat in categories)
                ExpansionTile(
                  title: Text(
                    cat.title.toUpperCase(),
                    style: theme.textTheme.labelSmall?.copyWith(
                      letterSpacing: 1.2,
                    ),
                  ),
                  initiallyExpanded: true,
                  tilePadding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    for (final sub in cat.subcategories)
                      ExpansionTile(
                        title: Text(
                          sub.title,
                          style: theme.textTheme.bodyMedium,
                        ),
                        initiallyExpanded: true,
                        tilePadding: const EdgeInsets.only(left: 28, right: 16),
                        children: [
                          for (final item in sub.items)
                            ListTile(
                              contentPadding: const EdgeInsets.only(
                                left: 44,
                                right: 16,
                              ),
                              dense: true,
                              title: Text(
                                item.title,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: selected?.id == item.id
                                      ? theme.colorScheme.primary
                                      : null,
                                ),
                              ),
                              selected: selected?.id == item.id,
                              selectedTileColor: theme.colorScheme.primary
                                  .withAlpha(30),
                              onTap: () => onSelect(item),
                            ),
                        ],
                      ),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }
}
