/// How assets are prepared for a build.
///
/// Shared by `good build` and `good assets pack` rather than owned by either:
/// the build passes them through to the pack, and a value that lives in one
/// command's file is one the other has to import across the tree.
library;

/// Loose files or a packed bundle.
///
/// The two modes want opposite things. Development wants the shortest path
/// from a changed file to seeing it: no packing, no compression, no
/// decryption, and a file you can replace on disk. Release wants the pack -
/// fewer files, smaller, and not trivially extractable.
enum AssetMode {
  /// Loose files, exactly as `good assets compact` wrote them.
  development,

  /// Compressed, encrypted and chunked - see `good assets pack`.
  release,
}

enum AssetEncryption { none, aes }

enum AssetCompressionLevel { none, fast, normal, best }
