-- | Bounded generation of scenario inputs. No generated data enters errors.
module HurlWorkbench.Parameter.Generate
  ( GeneratorEnvironment (..),
    defaultGeneratorEnvironment,
    generateValue,
    validateGenerator,
    generatorName,
    uuid4Bytes,
    uuid7Bytes,
    formatUuid,
    encodeTypeId,
  )
where

import Control.Exception (IOException, try)
import Data.Bifunctor (first)
import Data.Bits (shiftR, (.&.), (.|.))
import Data.ByteString qualified as BS
import Data.Text qualified as Text
import Data.Time (UTCTime, defaultTimeLocale, formatTime, getCurrentTime)
import Data.Time.Clock.POSIX (utcTimeToPOSIXSeconds)
import Data.Word (Word8)
import HurlWorkbench.Prelude
import HurlWorkbench.Workspace.Types
import Numeric (showHex)
import System.IO (IOMode (ReadMode), withBinaryFile)

data GeneratorEnvironment = GeneratorEnvironment
  { currentTime :: IO UTCTime,
    entropyBytes :: Int -> IO BS.ByteString
  }

defaultGeneratorEnvironment :: GeneratorEnvironment
defaultGeneratorEnvironment = GeneratorEnvironment getCurrentTime $ \count ->
  if count < 0 || count > 16384
    then ioError (userError "invalid entropy request")
    else withBinaryFile "/dev/urandom" ReadMode $ \handle ->
      let readExactly remaining chunks
            | remaining == 0 = pure (BS.concat (reverse chunks))
            | otherwise = do
                bytes <- BS.hGet handle remaining
                if BS.null bytes
                  then ioError (userError "entropy EOF")
                  else readExactly (remaining - BS.length bytes) (bytes : chunks)
       in readExactly count []

generatorName :: Generator -> Text
generatorName = \case
  Uuid4 -> "Uuid4"
  Uuid7 -> "Uuid7"
  TypeId _ -> "TypeId"
  Rfc3339Now -> "Rfc3339Now"
  RandomAlphanumeric _ -> "RandomAlphanumeric"

validateGenerator :: Generator -> Either Text ()
validateGenerator = \case
  TypeId (TypeIdOptions prefix)
    | Text.length prefix > 63
        || not (Text.all (\c -> letter c || c == '_') prefix)
        || (not (Text.null prefix) && (not (letter (Text.head prefix)) || not (letter (Text.last prefix)))) ->
        Left "TypeId prefix must be empty or at most 63 lowercase ASCII letters/underscores, starting and ending with a letter"
  RandomAlphanumeric (RandomOptions count) | count < 1 || count > 4096 -> Left "RandomAlphanumeric length must be between 1 and 4096"
  _ -> Right ()
  where
    letter c = c >= 'a' && c <= 'z'

-- | Synchronous IO failures are redacted; cancellation propagates normally.
generateValue :: GeneratorEnvironment -> Generator -> IO (Either Text HurlValueLiteral)
generateValue env generator = case validateGenerator generator of
  Left err -> pure (Left err)
  Right () -> do
    result <- try @IOException generate
    pure $ case result of
      Left _ -> Left "generation failed"
      Right (Left _) -> Left "generation failed"
      Right (Right value) -> first (const "generated value is not a Hurl literal") (mkHurlValueLiteral value)
  where
    draw count = do
      bytes <- entropyBytes env count
      if BS.length bytes == count then pure bytes else ioError (userError "short entropy read")
    uuid7 = do
      now <- currentTime env
      bytes <- BS.unpack <$> draw 16
      pure (uuid7Bytes (floor (utcTimeToPOSIXSeconds now * 1000)) bytes)
    generate = case generator of
      Uuid4 -> fmap (fmap formatUuid . uuid4Bytes . BS.unpack) (draw 16)
      Uuid7 -> fmap (fmap formatUuid) uuid7
      TypeId (TypeIdOptions prefix) -> fmap (fmap (\bytes -> (if Text.null prefix then "" else prefix <> "_") <> encodeTypeId bytes)) uuid7
      Rfc3339Now -> do
        now <- currentTime env
        let millis = (floor (utcTimeToPOSIXSeconds now * 1000) :: Integer) `mod` 1000
            digits = show millis
        pure (Right (Text.pack (formatTime defaultTimeLocale "%Y-%m-%dT%H:%M:%S" now <> "." <> replicate (3 - length digits) '0' <> digits <> "Z")))
      RandomAlphanumeric (RandomOptions count) -> sample (fromIntegral count) (fromIntegral count * 32 + 128) []
    -- Rejection sampling has a finite entropy budget, including a broken source
    -- that supplies only rejected bytes. No modulo bias or unbounded loop.
    sample remaining budget chunks
      | remaining == 0 = pure (Right (Text.concat (reverse chunks)))
      | budget <= 0 = pure (Left "entropy rejection budget exhausted")
      | otherwise = do
          let count = min budget (max 32 (min 4096 (remaining * 2)))
          bytes <- draw count
          let accepted = take remaining [Text.index alphabet (fromIntegral byte `mod` 62) | byte <- BS.unpack bytes, byte < 248]
          sample (remaining - length accepted) (budget - count) (Text.pack accepted : chunks)
    alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"

uuid4Bytes :: [Word8] -> Either Text [Word8]
uuid4Bytes = setVersion 4

setVersion :: Word8 -> [Word8] -> Either Text [Word8]
setVersion version bytes
  | length bytes /= 16 = Left "UUID requires 16 bytes"
  | otherwise = Right [if index == 6 then (byte .&. 15) .|. (version * 16) else if index == 8 then (byte .&. 63) .|. 128 else byte | (index, byte) <- zip [0 :: Int ..] bytes]

uuid7Bytes :: Integer -> [Word8] -> Either Text [Word8]
uuid7Bytes millis bytes
  | millis < 0 || millis >= 2 ^ (48 :: Int) = Left "UUID7 timestamp outside 48-bit range"
  | length bytes /= 16 = Left "UUID requires 16 bytes"
  | otherwise = setVersion 7 ([fromIntegral (millis `shiftR` bits) | bits <- [40, 32 .. 0]] <> drop 6 bytes)

formatUuid :: [Word8] -> Text
formatUuid bytes = Text.pack (concat [separator index <> hex byte | (index, byte) <- zip [0 :: Int ..] bytes])
  where
    separator index = if index `elem` [4, 6, 8, 10] then "-" else ""
    hex byte = let digits = showHex byte "" in replicate (2 - length digits) '0' <> digits

-- | TypeID v0.3: mori://jetify-com/typeid, spec/README.md (artifact URI pending).
encodeTypeId :: [Word8] -> Text
encodeTypeId bytes = Text.pack [alphabet !! fromIntegral ((value `shiftR` bits) .&. 31) | bits <- [125, 120 .. 0]]
  where
    value = foldl (\acc byte -> acc * 256 + fromIntegral byte) (0 :: Integer) bytes
    alphabet = "0123456789abcdefghjkmnpqrstvwxyz"
