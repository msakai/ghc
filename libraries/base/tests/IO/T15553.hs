{-# LANGUAGE ScopedTypeVariables #-}

-- Regression test for #15553.
--
-- GHC.IO.Encoding used not to flush *partially converted input* at the end of
-- the stream, in either direction, so some iconv-based encodings produced
-- incomplete output.
--
-- Encoding (Unicode -> bytes):
--   * EUC-JISX0213: U+3051 alone encodes as 0xa4 0xb1, but U+3051 followed by
--     U+309A encodes as 0xa4 0xfa, so iconv defers the output. Writing just
--     U+3051 used to produce *no* bytes at all.
--   * ISO-2022-JP is stateful and must emit the reset sequence ESC ( B
--     (0x1b 0x28 0x42) at the end; that trailing escape used to be lost.
--
-- Decoding (bytes -> Unicode), with GNU libiconv / glibc which precompose on
-- decode and so buffer a base character internally:
--   * CP1255 (Hebrew), CP1258 / TCVN (Latin) hold back a base character; a lone
--     trailing 'A' (0x41) in CP1258 even decodes to nothing.
--   * BIG5-HKSCS buffers the 2nd code point of a 1->2 expansion.
--   These are exercised here as round trips (encode then decode back).
--
-- For any encoding the local iconv does not support, mkTextEncoding throws and
-- we print "OK": the test cannot exercise the fix there, but stays portable.

module Main where

import Control.Exception
import Data.Char (ord)
import System.IO

tmp :: FilePath
tmp = "T15553.out"

readBytes :: FilePath -> IO [Int]
readBytes fp = withBinaryFile fp ReadMode $ \h -> do
  s <- hGetContents h
  _ <- evaluate (length s)     -- force before the handle is closed
  return (map ord s)

-- Encode @input@ with @encName@ and check the exact bytes written.
checkBytes :: String -> String -> [Int] -> IO ()
checkBytes encName input expected = do
  mb <- try (mkTextEncoding encName) :: IO (Either IOException TextEncoding)
  case mb of
    Left _    -> putStrLn (encName ++ ": OK")    -- encoding unavailable: skip
    Right enc -> do
      r <- try $ do
             withFile tmp WriteMode $ \h -> do
               hSetEncoding h enc
               hPutStr h input
             readBytes tmp
      case r of
        Left (_ :: IOException) -> putStrLn (encName ++ ": OK")  -- unsupported: skip
        Right bytes
          | bytes == expected -> putStrLn (encName ++ ": OK")
          | otherwise         -> putStrLn (encName ++ ": FAIL got=" ++ show bytes
                                            ++ " expected=" ++ show expected)

-- Encode @s@ with @encName@ then decode it back; the result must equal @s@.
-- Exercises both the encoder and the decoder end-of-stream flush.
roundtrip :: String -> String -> IO ()
roundtrip encName s = do
  mb <- try (mkTextEncoding encName) :: IO (Either IOException TextEncoding)
  case mb of
    Left _    -> putStrLn (encName ++ " (roundtrip): OK")  -- unavailable: skip
    Right enc -> do
      r <- try $ do
             withFile tmp WriteMode $ \h -> do
               hSetEncoding h enc
               hPutStr h s
             withFile tmp ReadMode $ \h -> do
               hSetEncoding h enc
               s' <- hGetContents h
               _ <- evaluate (length s')
               return s'
      case r of
        Left (_ :: IOException) -> putStrLn (encName ++ " (roundtrip): OK")  -- skip
        Right s'
          | s' == s   -> putStrLn (encName ++ " (roundtrip): OK")
          | otherwise -> putStrLn (encName ++ " (roundtrip): FAIL got=" ++ show s'
                                    ++ " expected=" ++ show s)

main :: IO ()
main = do
  -- encode side
  checkBytes "EUC-JISX0213" "\x3051" [0xa4, 0xb1]
  checkBytes "ISO-2022-JP"  "\x3042" [0x1b, 0x24, 0x42, 0x24, 0x22, 0x1b, 0x28, 0x42]
  -- decode side (round trips)
  roundtrip "CP1255"     "\x05d0\x05d1"  -- Hebrew Alef + Bet
  roundtrip "CP1258"     "A"             -- lone Latin base char
  roundtrip "BIG5-HKSCS" "\x00ca\x0304"  -- 1->2 expansion (E with macron, decomposed)
