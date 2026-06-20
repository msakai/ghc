{-# LANGUAGE Trustworthy #-}
{-# LANGUAGE NoImplicitPrelude, ExistentialQuantification #-}
{-# OPTIONS_GHC -funbox-strict-fields #-}
{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE PatternSynonyms, ViewPatterns #-}
{-# LANGUAGE UnboxedTuples, MagicHash #-}

-----------------------------------------------------------------------------
-- |
-- Module      :  GHC.Internal.IO.Encoding.Types
-- Copyright   :  (c) The University of Glasgow, 2008-2009
-- License     :  see libraries/base/LICENSE
--
-- Maintainer  :  libraries@haskell.org
-- Stability   :  internal
-- Portability :  non-portable
--
-- Types for text encoding/decoding
--
-----------------------------------------------------------------------------

module GHC.Internal.IO.Encoding.Types (
    BufferCodec(.., BufferCodec, encode, recover, close, getState, setState),
    finishCodec, noFinish#,
    TextEncoding(..),
    TextEncoder, TextDecoder,
    CodeBuffer, EncodeBuffer, DecodeBuffer,
    CodingProgress(..),
    DecodeBuffer#, EncodeBuffer#,
    DecodingBuffer#, EncodingBuffer#
  ) where

import GHC.Internal.Base (String, unIO, ($))
import GHC.Internal.Classes (Eq)
import GHC.Internal.Prim (RealWorld, State#)
import GHC.Internal.Word
import GHC.Internal.Show
-- import GHC.Internal.IO
import GHC.Internal.IO.Buffer
import GHC.Internal.Types (Char, IO(..))

-- -----------------------------------------------------------------------------
-- Text encoders/decoders

data BufferCodec from to state = BufferCodec# {
  encode# :: CodeBuffer# from to,
   -- ^ The @encode@ function translates elements of the buffer @from@
   -- to the buffer @to@.  It should translate as many elements as possible
   -- given the sizes of the buffers, including translating zero elements
   -- if there is either not enough room in @to@, or @from@ does not
   -- contain a complete multibyte sequence.
   --
   -- If multiple CodingProgress returns are possible, OutputUnderflow must be
   -- preferred to InvalidSequence. This allows GHC's IO library to assume that
   -- if we observe InvalidSequence there is at least a single element available
   -- in the output buffer.
   --
   -- The fact that as many elements as possible are translated is used by the IO
   -- library in order to report translation errors at the point they
   -- actually occur, rather than when the buffer is translated.

  recover# :: Buffer from -> Buffer to -> State# RealWorld -> (# State# RealWorld, Buffer from, Buffer to #),
   -- ^ The @recover@ function is used to continue decoding
   -- in the presence of invalid or unrepresentable sequences. This includes
   -- both those detected by @encode@ returning @InvalidSequence@ and those
   -- that occur because the input byte sequence appears to be truncated.
   --
   -- Progress will usually be made by skipping the first element of the @from@
   -- buffer. This function should only be called if you are certain that you
   -- wish to do this skipping and if the @to@ buffer has at least one element
   -- of free space. Because this function deals with decoding failure, it assumes
   -- that the from buffer has at least one element.
   --
   -- @recover@ may raise an exception rather than skipping anything.
   --
   -- Currently, some implementations of @recover@ may mutate the input buffer.
   -- In particular, this feature is used to implement transliteration.
   --
   -- @since base-4.4.0.0

  close# :: IO (),
   -- ^ Resources associated with the encoding may now be released.
   -- The @encode@ function may not be called again after calling
   -- @close@.

  getState# :: IO state,
   -- ^ Return the current state of the codec.
   --
   -- Many codecs are not stateful, and in these case the state can be
   -- represented as '()'.  Other codecs maintain a state.  For
   -- example, UTF-16 recognises a BOM (byte-order-mark) character at
   -- the beginning of the input, and remembers thereafter whether to
   -- use big-endian or little-endian mode.  In this case, the state
   -- of the codec would include two pieces of information: whether we
   -- are at the beginning of the stream (the BOM only occurs at the
   -- beginning), and if not, whether to use the big or little-endian
   -- encoding.

  setState# :: state -> IO (),
   -- restore the state of the codec using the state from a previous
   -- call to 'getState'.

  finish# :: Buffer to -> State# RealWorld -> (# State# RealWorld, CodingProgress, Buffer to #)
   -- ^ The @finish@ function is called once at the very end of a series of
   -- @encode@ calls, when there is no more input.  It flushes any input that
   -- the codec has consumed but not yet fully translated, and resets any
   -- internal coding state back to its initial value, writing the resulting
   -- elements to the @to@ buffer.
   --
   -- This matters for codecs that defer output until they have seen more
   -- input (e.g. iconv\'s EUC-JISX0213, where the character U+3051 might be
   -- the start of the two-character sequence U+3051 U+309A), and for stateful
   -- output encodings that must emit a trailing reset sequence (e.g. the
   -- @ESC ( B@ that ISO-2022-JP requires at the end of the stream). Without
   -- @finish@, that trailing output would be silently lost (#15553).
   --
   -- Like @encode@, @finish@ returns 'OutputUnderflow' if the @to@ buffer is
   -- too small to hold all of the flushed output; the caller is then expected
   -- to drain the buffer and call @finish@ again. It returns 'InputUnderflow'
   -- once there is nothing left to flush.
   --
   -- Both encoders and decoders may need this. Encoders are flushed when the
   -- codec is about to be discarded (on 'GHC.Internal.IO.Handle.hClose',
   -- 'GHC.Internal.IO.Handle.hSetEncoding' or
   -- 'GHC.Internal.IO.Handle.hSetBinaryMode'). Decoders are flushed when the
   -- input device reaches EOF: GNU libiconv and glibc precompose on decode and
   -- so buffer a base character internally (e.g. CP1255, CP1258, BIG5-HKSCS),
   -- which would otherwise be lost at end of input. Stateless codecs (the
   -- native UTF-8\/16\/32, Latin1) buffer nothing and use the no-op 'noFinish#'.
   --
   -- @since base-4.24.0.0
 }

type CodeBuffer      from to = Buffer from -> Buffer to -> IO (CodingProgress, Buffer from, Buffer to)
type DecodeBuffer            = CodeBuffer Word8 Char
type EncodeBuffer            = CodeBuffer Char Word8

type CodeBuffer#     from to = Buffer from -> Buffer to -> State# RealWorld -> (# State# RealWorld, CodingProgress, Buffer from, Buffer to #)
type DecodeBuffer#           = CodeBuffer# Word8 Char
type EncodeBuffer#           = CodeBuffer# Char  Word8

type CodingBuffer#   from to = State# RealWorld -> (# State# RealWorld, CodingProgress, Buffer from, Buffer to #)
type DecodingBuffer#         = CodingBuffer# Word8 Char
type EncodingBuffer#         = CodingBuffer# Char  Word8

type TextDecoder state = BufferCodec Word8 CharBufElem state
type TextEncoder state = BufferCodec CharBufElem Word8 state

-- | A 'TextEncoding' is a specification of a conversion scheme
-- between sequences of bytes and sequences of Unicode characters.
--
-- For example, UTF-8 is an encoding of Unicode characters into a sequence
-- of bytes.  The 'TextEncoding' for UTF-8 is 'GHC.Internal.System.IO.utf8'.
data TextEncoding
  = forall dstate estate . TextEncoding  {
        textEncodingName :: String,
                   -- ^ a string that can be passed to 'GHC.Internal.System.IO.mkTextEncoding' to
                   -- create an equivalent 'TextEncoding'.
        mkTextDecoder :: IO (TextDecoder dstate),
                   -- ^ Creates a means of decoding bytes into characters: the result must not
                   -- be shared between several byte sequences or simultaneously across threads
        mkTextEncoder :: IO (TextEncoder estate)
                   -- ^ Creates a means of encode characters into bytes: the result must not
                   -- be shared between several character sequences or simultaneously across threads
  }

-- | @since base-4.3.0.0
instance Show TextEncoding where
  show te = textEncodingName te

-- | @since base-4.4.0.0
data CodingProgress = InputUnderflow  -- ^ Stopped because the input contains insufficient available elements,
                                      -- or all of the input sequence has been successfully translated.
                    | OutputUnderflow -- ^ Stopped because the output contains insufficient free elements
                    | InvalidSequence -- ^ Stopped because there are sufficient free elements in the output
                                      -- to output at least one encoded ASCII character, but the input contains
                                      -- an invalid or unrepresentable sequence
                    deriving ( Eq   -- ^ @since base-4.4.0.0
                             , Show -- ^ @since base-4.4.0.0
                             )

{-# COMPLETE BufferCodec #-}
pattern BufferCodec :: CodeBuffer from to
                    -> (Buffer from -> Buffer to -> IO (Buffer from, Buffer to))
                    -> IO ()
                    -> IO state
                    -> (state -> IO ())
                    -> BufferCodec from to state
pattern BufferCodec{encode, recover, close, getState, setState} <-
    BufferCodec# (getEncode -> encode) (getRecover -> recover) close getState setState _
  where
    BufferCodec e r c g s = BufferCodec# (mkEncode e) (mkRecover r) c g s noFinish#

-- | A 'finish#' implementation for codecs that have no partially-translated
-- input to flush at the end of the stream (decoders and stateless encoders).
-- It writes nothing and immediately reports 'InputUnderflow'.
noFinish# :: Buffer to -> State# RealWorld -> (# State# RealWorld, CodingProgress, Buffer to #)
noFinish# to st = (# st, InputUnderflow, to #)

-- | Run a codec's 'finish#' in 'IO': flush any partially-translated input and
-- reset the codec's state, writing the result to the @to@ buffer. Works for
-- both encoders and decoders. See 'finish#'.
finishCodec :: BufferCodec from to state -> Buffer to -> IO (CodingProgress, Buffer to)
finishCodec codec to = IO $ \st ->
  case finish# codec to st of (# st', prog, to' #) -> (# st', (prog, to') #)

getEncode :: CodeBuffer# from to -> CodeBuffer from to
getEncode e i o = IO $ \st ->
  let !(# st', prog, i', o' #) = e i o st in (# st', (prog, i', o') #)

getRecover :: (Buffer from -> Buffer to -> State# RealWorld -> (# State# RealWorld, Buffer from, Buffer to #))
           -> (Buffer from -> Buffer to -> IO (Buffer from, Buffer to))
getRecover r i o = IO $ \st ->
  let !(# st', i', o' #) = r i o st in (# st', (i', o') #)

mkEncode :: CodeBuffer from to -> CodeBuffer# from to
mkEncode e i o st = let !(# st', (prog, i', o') #) = unIO (e i o) st in (# st', prog, i', o' #)

mkRecover :: (Buffer from -> Buffer to -> IO (Buffer from, Buffer to))
          -> (Buffer from -> Buffer to -> State# RealWorld -> (# State# RealWorld, Buffer from, Buffer to #))
mkRecover r i o st = let !(# st', (i', o') #) = unIO (r i o) st in (# st', i', o' #)
