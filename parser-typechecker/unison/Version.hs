{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}

module Version where

import Language.Haskell.TH (runIO)
import Language.Haskell.TH.Syntax (Exp(LitE), Lit(StringL))
import Shellmet
import Data.Text

gitDescribe :: String
gitDescribe = $( fmap (LitE . StringL . unpack) . runIO $ do
  -- Outputs date of current commit; E.g. 2021-08-06
  let formatDate d = "(" <> d <> ") "
  let getDate = "git" $| ["show", "-s", "--format=%cs"]
  date <- (formatDate <$> getDate) $? pure ""
  -- Fetches a unique tag-name to represent the current commit.
  -- Uses human-readable names whenever possible.
  -- Marks version with a `'` suffix if building on a dirty worktree.
  let getTag = "git" $| ["describe", "--tags", "--always", "--dirty='"]
  tag <- getTag $? pure "unknown"
  pure (date <> tag)
  )
