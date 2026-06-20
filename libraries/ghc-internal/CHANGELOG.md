# Revision history for `ghc-internal`

## 9.1401.0 -- yyyy-mm-dd

* Introduce `dataToCodeQ` and `liftDataTyped`, typed variants of `dataToExpQ` and `liftData` respectively.
* Add new `gc_sync_elapsed_ns` counter to GHC.Internal.Stats
* Fix `GHC.Internal.IO.Encoding` not flushing partially converted input at the
  end of the stream, which produced incomplete output for some iconv-based
  encodings (e.g. `EUC-JISX0213` dropping a deferred character, `ISO-2022-JP`
  dropping its trailing `ESC ( B` reset sequence). `BufferCodec#` gains a
  `finish#` field for this; the public `BufferCodec` pattern synonym is
  unchanged and defaults it to a no-op. (#15553)

## 9.1001.0 -- 2024-05-01

* Package created containing implementation moved from `base`.
