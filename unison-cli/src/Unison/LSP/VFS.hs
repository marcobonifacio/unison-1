{-# LANGUAGE DataKinds #-}
{-# LANGUAGE NumericUnderscores #-}
{-# LANGUAGE PatternSynonyms #-}
{-# LANGUAGE RecordWildCards #-}

module Unison.LSP.VFS where

import qualified Colog.Core as Colog
import Control.Lens
import Control.Monad.Reader
import Control.Monad.State
import Data.Char
import qualified Data.Map as Map
import qualified Data.Set as Set
import Data.Set.Lens (setOf)
import qualified Data.Text as Text
import qualified Data.Text.Utf16.Rope as Rope
import qualified Language.LSP.Logging as LSP
import Language.LSP.Types
import Language.LSP.Types.Lens (HasCharacter (character), HasParams (params), HasPosition (position), HasTextDocument (textDocument), HasUri (uri))
import qualified Language.LSP.Types.Lens as LSP
import Language.LSP.VFS as VFS hiding (character)
import Unison.LSP.Orphans ()
import Unison.LSP.Types
import Unison.Prelude
import UnliftIO

-- | Some VFS combinators require Monad State, this provides it in a transactionally safe
-- manner so we're sure we don't edit the same file in two different actions at the same time.
usingVFS :: forall a. StateT VFS Lsp a -> Lsp a
usingVFS m = do
  vfsVar' <- asks vfsVar
  modifyMVar vfsVar' $ \vfs -> do
    (!a, !b) <- runStateT m vfs
    pure $! (b, a)

getVirtualFile :: (HasUri doc Uri) => doc -> Lsp (Maybe VirtualFile)
getVirtualFile p = do
  vfs <- asks vfsVar >>= readMVar
  pure $ vfs ^. vfsMap . at (toNormalizedUri $ p ^. uri)

getFileContents :: (HasUri doc Uri) => doc -> Lsp (Maybe (FileVersion, Text))
getFileContents p = runMaybeT $ do
  vf <- MaybeT $ getVirtualFile p
  pure (vf ^. lsp_version, Rope.toText $ vf ^. file_text)

vfsLogger :: Colog.LogAction (StateT VFS Lsp) (Colog.WithSeverity VfsLog)
vfsLogger = Colog.cmap (fmap tShow) (Colog.hoistLogAction lift LSP.defaultClientLogger)

-- | Mark some files as needing to be checked.
markFilesDirty :: (Foldable f, HasUri doc Uri) => f doc -> Lsp ()
markFilesDirty docs = do
  dirtyFilesV <- asks dirtyFilesVar
  checkedFilesV <- asks checkedFilesVar
  let dirtyUris = setOf (folded . uri) docs
  atomically $ do
    modifyTVar' dirtyFilesV (Set.union dirtyUris)
    checkedFiles <- readTVar checkedFilesV
    -- Clear the analysis for any files which need to be re-checked.
    for_ dirtyUris \uri -> do
      case Map.lookup uri checkedFiles of
        Nothing -> pure ()
        Just mvar -> void $ tryTakeTMVar mvar

-- | Mark all files for re-checking.
--
-- We may want to do this when our names or perspective change.
markAllFilesDirty :: Lsp ()
markAllFilesDirty = do
  vfs <- asks vfsVar >>= readMVar
  markFilesDirty $ Map.keys (vfs ^. vfsMap)

-- | Returns the name or symbol which the provided position is contained in.
identifierAtPosition :: (HasPosition p Position, HasTextDocument p TextDocumentIdentifier) => p -> Lsp (Maybe Text)
identifierAtPosition p = do
  identifierSplitAtPosition p <&> fmap \(before, after) -> (before <> after)

-- | Returns the prefix and suffix of the symbol which the provided position is contained in.
identifierSplitAtPosition :: (HasPosition p Position, HasTextDocument p docId, HasUri docId Uri) => p -> Lsp (Maybe (Text, Text))
identifierSplitAtPosition p = runMaybeT $ do
  vf <- MaybeT (getVirtualFile (p ^. textDocument))
  PosPrefixInfo {fullLine, cursorPos} <- MaybeT (VFS.getCompletionPrefix (p ^. position) vf)
  let (before, after) = Text.splitAt (cursorPos ^. character . to fromIntegral) fullLine
  pure $ (Text.takeWhileEnd isIdentifierChar before, Text.takeWhile isIdentifierChar after)
  where
    -- TODO: Should probably use something from the Lexer here
    isIdentifierChar = \case
      c
        | isSpace c -> False
        | elem c ("[]()`'\"" :: String) -> False
        | otherwise -> True

-- | Returns the prefix of the symbol at the provided location, and the range that prefix
-- spans.
completionPrefix :: (HasPosition p Position, HasTextDocument p docId, HasUri docId Uri) => p -> Lsp (Maybe (Range, Text))
completionPrefix p = runMaybeT $ do
  (before, _) <- MaybeT $ identifierSplitAtPosition p
  let posLine = p ^. position . LSP.line
  let posChar = (p ^. position . LSP.character)
  let range = mkRange posLine (posChar - fromIntegral (Text.length before)) posLine posChar
  pure (range, before)

--- Handlers for tracking file changes.

lspOpenFile :: NotificationMessage 'TextDocumentDidOpen -> Lsp ()
lspOpenFile msg = do
  usingVFS . openVFS vfsLogger $ msg
  markFilesDirty [msg ^. params . textDocument]

lspCloseFile :: NotificationMessage 'TextDocumentDidClose -> Lsp ()
lspCloseFile msg =
  usingVFS . closeVFS vfsLogger $ msg

lspChangeFile :: NotificationMessage 'TextDocumentDidChange -> Lsp ()
lspChangeFile msg = do
  usingVFS . changeFromClientVFS vfsLogger $ msg
  markFilesDirty [msg ^. params . textDocument]
