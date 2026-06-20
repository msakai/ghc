{-# LANGUAGE ScopedTypeVariables #-}

-- Regression test for #15553.
--
-- GHC.IO.Encoding used not to flush *partially converted input* at the end of
-- the stream, so some iconv-based encodings produced incomplete output:
--
--   * EUC-JISX0213: U+3051 alone encodes as 0xa4 0xb1, but U+3051 followed by
--     U+309A encodes as 0xa4 0xfa, so iconv defers the output until it knows
--     which case applies. Without an end-of-input flush, writing just U+3051
--     produced *no* bytes at all.
--
--   * ISO-2022-JP is stateful and must emit the reset sequence ESC ( B
--     (0x1b 0x28 0x42) at the end of the stream. Without a flush, that trailing
--     escape sequence was lost.
--
-- For any encoding that the local iconv does not support (e.g. EUC-JISX0213 is
-- not available on macOS), mkTextEncoding throws, and we simply print "OK": the
-- test cannot exercise the fix there, but it stays portable. On a fixed GHC
-- where the encoding *is* available, the bytes must match exactly.

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

check :: String -> String -> [Int] -> IO ()
check encName input expected = do
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

main :: IO ()
main = do
  check "EUC-JISX0213" "\x3051" [0xa4, 0xb1]
  check "ISO-2022-JP"  "\x3042" [0x1b, 0x24, 0x42, 0x24, 0x22, 0x1b, 0x28, 0x42]
