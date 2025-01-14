{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ViewPatterns #-}

module Unison.CommandLine.InputPattern
  ( InputPattern (..),
    Argument,
    ArgumentType (..),
    ArgumentDescription,
    Arguments,
    argType,
    FZFResolver (..),
    IsOptional (..),
    Visibility (..),

    -- * Currently Unused
    minArgs,
    maxArgs,
    unionSuggestions,
    suggestionFallbacks,
  )
where

import Control.Lens
import Data.List.Extra qualified as List
import System.Console.Haskeline qualified as Line
import Unison.Auth.HTTPClient (AuthenticatedHttpClient)
import Unison.Codebase (Codebase)
import Unison.Codebase.Editor.Input (Input (..))
import Unison.Codebase.Editor.StructuredArgument (StructuredArgument)
import Unison.Codebase.Path as Path
import Unison.CommandLine.FZFResolvers (FZFResolver (..))
import Unison.Prelude
import Unison.Util.ColorText qualified as CT
import Unison.Util.Monoid (foldMapM)
import Unison.Util.Pretty qualified as P

-- InputPatterns accept some fixed number of Required arguments of various
-- types, followed by a variable number of a single type of argument.
data IsOptional
  = Required -- 1, at the start
  | Optional -- 0 or 1, at the end
  | ZeroPlus -- 0 or more, at the end
  | OnePlus -- 1 or more, at the end
  deriving (Show, Eq)

data Visibility = Hidden | Visible
  deriving (Show, Eq, Ord)

-- | An argument to a command is either a string provided by the user which
-- needs to be parsed or a numbered argument that doesn’t need to be parsed, as
-- we’ve preserved its representation (although the numbered argument could
-- still be of the wrong type, which should result in an error).
type Argument = Either String StructuredArgument

type Arguments = [Argument]

-- | Argument description
-- It should fit grammatically into sentences like "I was expecting an argument for the <argDesc>"
-- e.g. "namespace to merge", "definition to delete", "remote target to push to" etc.
type ArgumentDescription = Text

data InputPattern = InputPattern
  { patternName :: String,
    aliases :: [String],
    visibility :: Visibility, -- Allow hiding certain commands when debugging or work-in-progress
    args :: [(ArgumentDescription, IsOptional, ArgumentType)],
    help :: P.Pretty CT.ColorText,
    parse :: Arguments -> Either (P.Pretty CT.ColorText) Input
  }

data ArgumentType = ArgumentType
  { typeName :: String,
    -- | Generate completion suggestions for this argument type
    suggestions ::
      forall m v a.
      (MonadIO m) =>
      String ->
      Codebase m v a ->
      AuthenticatedHttpClient ->
      Path.Absolute -> -- Current path
      m [Line.Completion],
    -- | If an argument is marked as required, but not provided, the fuzzy finder will be triggered if
    -- available.
    fzfResolver :: Maybe FZFResolver
  }

instance Show ArgumentType where
  show at = "ArgumentType " <> typeName at

-- `argType` gets called when the user tries to autocomplete an `i`th argument (zero-indexed).
-- todo: would be nice if we could alert the user if they try to autocomplete
-- past the end.  It would also be nice if
argInfo :: InputPattern -> Int -> Maybe (ArgumentDescription, ArgumentType)
argInfo InputPattern {args, patternName} i = go (i, args)
  where
    -- Strategy: all of these input patterns take some number of arguments.
    -- If it takes no arguments, then don't autocomplete.
    go :: (Int, [(Text, IsOptional, ArgumentType)]) -> Maybe (ArgumentDescription, ArgumentType)
    go (_, []) = Nothing
    -- If requesting the 0th of >=1 arguments, return it.
    go (0, (argName, _, t) : _) = Just (argName, t)
    -- Vararg parameters should appear at the end of the arg list, and work for
    -- any later argument number.
    go (_, [(argName, ZeroPlus, t)]) = Just (argName, t)
    go (_, [(argName, OnePlus, t)]) = Just (argName, t)
    -- If requesting a later parameter, decrement and drop one.
    go (n, (_argName, o, _) : argTypes)
      | o == Optional || o == Required = go (n - 1, argTypes)
    -- The argument list spec is invalid if something follows a vararg
    go args =
      error $
        "Input pattern "
          <> show patternName
          <> " has an invalid argument list: "
          <> show args

-- `argType` gets called when the user tries to autocomplete an `i`th argument (zero-indexed).
-- todo: would be nice if we could alert the user if they try to autocomplete
-- past the end.  It would also be nice if
argType :: InputPattern -> Int -> Maybe ArgumentType
argType ip i = snd <$> (argInfo ip i)

minArgs :: InputPattern -> Int
minArgs (InputPattern {args, patternName}) =
  go (args ^.. folded . _2)
  where
    go [] = 0
    go (Required : argTypes) = 1 + go argTypes
    go [_] = 0
    go _ =
      error $
        "Invalid args for InputPattern ("
          <> show patternName
          <> "): "
          <> show args

maxArgs :: InputPattern -> Maybe Int
maxArgs (InputPattern {args, patternName}) = go argTypes
  where
    argTypes = args ^.. folded . _2
    go [] = Just 0
    go (Required : argTypes) = (1 +) <$> go argTypes
    go [Optional] = Just 0
    go [_] = Nothing
    go _ =
      error $
        "Invalid args for InputPattern ("
          <> show patternName
          <> "): "
          <> show argTypes

-- | Union suggestions from all possible completions
unionSuggestions ::
  forall m v a.
  (MonadIO m) =>
  [ ( String ->
      Codebase m v a ->
      AuthenticatedHttpClient ->
      Path.Absolute ->
      m [Line.Completion]
    )
  ] ->
  ( String ->
    Codebase m v a ->
    AuthenticatedHttpClient ->
    Path.Absolute ->
    m [Line.Completion]
  )
unionSuggestions suggesters inp codebase httpClient path = do
  suggesters & foldMapM \suggester ->
    suggester inp codebase httpClient path
      & fmap List.nubOrd

-- | Try the first completer, if it returns no suggestions, try the second, etc.
suggestionFallbacks ::
  forall m v a.
  (MonadIO m) =>
  [ ( String ->
      Codebase m v a ->
      AuthenticatedHttpClient ->
      Path.Absolute ->
      m [Line.Completion]
    )
  ] ->
  ( String ->
    Codebase m v a ->
    AuthenticatedHttpClient ->
    Path.Absolute ->
    m [Line.Completion]
  )
suggestionFallbacks suggesters inp codebase httpClient path = go suggesters
  where
    go (s : rest) = do
      suggestions <- s inp codebase httpClient path
      if null suggestions
        then go rest
        else pure suggestions
    go [] = pure []
