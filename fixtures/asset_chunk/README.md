# The asset chunk golden

`chunk_v1_aes_gzip.dat` is one chunk, version 1, gzip-compressed and sealed
with AES-256-GCM. It belongs to neither package on purpose.

## Why it exists

The chunk format has two implementations. `good_cli` writes chunks;
`packages/good/lib/src/asset_pack.dart` reads them. The duplication is
deliberate - a shipped game must not depend on the build tool, which carries
`package:analyzer` and an ffmpeg downloader - but duplication that nothing
compares is duplication waiting to drift.

Both suites are self-consistent without this file. `good_cli` could seal chunks
in a layout `good` cannot read and both would stay green, because each was only
ever tested against its own idea of the format. The failure would land at run
time, in a release build, on the first asset load.

So: `good_cli` checks that its packer still produces these exact bytes, and
`good` checks that its reader still gets the members back out of them. A change
to either half that the other did not follow breaks one of those two tests.

## What is in it

Sealed with `compression: normal` and a key of `List.generate(32, (i) => i * 7 % 256)` -
not a secret, and not an example to copy; a real key comes from a project's
generated `asset_key.dart`. It holds two members:

| logical path      | bytes           |
| ----------------- | --------------- |
| `assets/a.webp`   | `texture bytes` |
| `assets/b.ogg`    | `audio bytes`   |

Sealing is deterministic - the nonce is a hash of the compressed body - so the
same inputs always produce the same file. That is what lets `good_cli` compare
bytes instead of round-trip.

## Regenerating it

```
cd packages/good_cli
dart run test/write_chunk_golden.dart
```

Only when the format is *meant* to change, and bump `chunkVersion` in the same
commit. Regenerating to quiet a failing test throws away the only thing holding
the two implementations together.
