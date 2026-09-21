-- | Batch-ready Hurl requests. Bounded scheduling and result aggregation are
--   added by EP-4's second milestone; preparation already targets this type.
module HurlWorkbench.Run.Batch
  ( BatchCase (..),
  )
where

import Data.Generics.Labels ()
import HurlWorkbench.Hurl.Run (RunRequest)
import HurlWorkbench.Prelude

data BatchCase = BatchCase
  { name :: !Text,
    artifactStem :: !FilePath,
    request :: !RunRequest
  }
  deriving stock (Generic, Eq)

instance Show BatchCase where
  show batchCase = "BatchCase " <> show (batchCase ^. #name) <> " <redacted request>"
