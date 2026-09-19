{-# LANGUAGE PackageImports #-}

-- | Project-wide prelude for hurl-workbench. It re-exports the small set of
--   types and functions that nearly every module needs, plus the lens
--   operators.
--
--   It deliberately does not import @Data.Generics.Labels@: that orphan
--   @IsLabel@ instance would leak into every module. Modules that use
--   @#field@ access import @Data.Generics.Labels ()@ themselves.
module HurlWorkbench.Prelude
  ( module X,
    module Control.Lens,
  )
where

import "base" Control.Monad as X (forM, forM_, unless, void, when)
import "base" Data.Foldable as X (for_, toList, traverse_)
import "base" Data.List.NonEmpty as X (NonEmpty (..), nonEmpty)
import "base" Data.Maybe as X (catMaybes, fromMaybe, isJust, isNothing, mapMaybe)
import "base" Data.Traversable as X (for)
import "base" GHC.Generics as X (Generic)
import "containers" Data.Map.Strict as X (Map)
import "containers" Data.Set as X (Set)
import "lens" Control.Lens
import "text" Data.Text as X (Text)
