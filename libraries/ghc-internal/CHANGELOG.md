# Revision history for `ghc-internal`

## 9.1401.0 -- yyyy-mm-dd

* Introduce `dataToCodeQ` and `liftDataTyped`, typed variants of `dataToExpQ` and `liftData` respectively.
* Add new `gc_sync_elapsed_ns` counter to GHC.Internal.Stats
* Fix `GHC.Internal.IO.Encoding` not flushing partially converted input at the
  end of the stream, which produced incomplete output for some iconv-based
  encodings, in both directions:
  - encoding: `EUC-JISX0213` dropped a deferred character and `ISO-2022-JP`
    dropped its trailing `ESC ( B` reset sequence;
  - decoding: GNU libiconv / glibc precompose on decode and buffer a base
    character, so `CP1255`, `CP1258`, `TCVN` and `BIG5-HKSCS` dropped the final
    decoded character at EOF.
  This is fixed both for text `Handle`s and for C string marshalling
  (`Foreign.C.String.with/peek/newCString`, and hence `charIsRepresentable` —
  `mkTextEncoding "CP1258"` previously failed with "unknown encoding" because
  its round-trip check lost the buffered character). `BufferCodec#` gains a
  `finish#` field for this; the public `BufferCodec` pattern synonym is
  unchanged and defaults it to a no-op. (#15553)

## 9.1001.0 -- 2024-05-01

* Package created containing implementation moved from `base`.
