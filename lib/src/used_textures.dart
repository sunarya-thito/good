import 'package:flutter/widgets.dart';
import 'package:goo2d/src/asset.dart';

/// Optional InheritedWidget that hints the renderer about which [TextureGroup]
/// instances are active in a subtree.
///
/// When present, [resolveGroup] prefers groups known to this widget before
/// falling back to the full [GameTexture.textureGroups] scan. When absent,
/// the fallback scan always runs and still finds the correct group.
///
/// Usage:
/// ```dart
/// UsedTextures(
///   textures: [Sprites.player, Sprites.enemy],
///   child: MyGameSubtree(),
/// )
/// ```
class UsedTextures extends InheritedWidget {
  /// The textures whose groups should be preferred by the renderer.
  final List<GameTexture> textures;

  // Flattened set of non-disposed groups reachable from [textures].
  // Computed eagerly at construction so resolveGroup() has no allocation.
  final List<TextureGroup> _resolvedGroups;

  UsedTextures({
    super.key,
    required this.textures,
    required super.child,
  }) : _resolvedGroups = _computeGroups(textures);

  static List<TextureGroup> _computeGroups(List<GameTexture> textures) {
    final seen = <int>{}; // group ids already added
    final result = <TextureGroup>[];
    for (final tex in textures) {
      for (final g in tex.textureGroups) {
        if (!g.isDisposed && seen.add(g.id)) {
          result.add(g);
        }
      }
    }
    return result;
  }

  /// Returns the [TextureGroup] that contains [tex], or null if none.
  ///
  /// When [context] is non-null and a [UsedTextures] ancestor exists, its
  /// groups are checked first (fast path for scenes with explicit hints).
  /// Falls back to scanning [tex.textureGroups] directly when no ancestor
  /// is found, or when no hint group contains [tex].
  ///
  /// Pass [context] = null from ECS render paths that have no BuildContext.
  static TextureGroup? resolveGroup(BuildContext? context, GameTexture tex) {
    if (context != null) {
      final w = context.dependOnInheritedWidgetOfExactType<UsedTextures>();
      if (w != null) {
        for (final g in w._resolvedGroups) {
          if (!g.isDisposed && g.atlasRectFor(tex) != null) return g;
        }
      }
    }
    // Fallback: scan all groups registered on the texture.
    for (final g in tex.textureGroups) {
      if (!g.isDisposed && g.atlasRectFor(tex) != null) return g;
    }
    return null;
  }

  /// Returns the resolved group list for this [UsedTextures] ancestor,
  /// or an empty list if none is present.
  static List<TextureGroup> groupsOf(BuildContext context) {
    final w = context.dependOnInheritedWidgetOfExactType<UsedTextures>();
    return w?._resolvedGroups ?? const [];
  }

  @override
  bool updateShouldNotify(UsedTextures old) =>
      textures != old.textures ||
      _resolvedGroups.length != old._resolvedGroups.length;
}
