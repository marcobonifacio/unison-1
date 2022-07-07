{-# LANGUAGE DataKinds #-}
{-# LANGUAGE PolyKinds #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE TypeOperators #-}

module Unison.LSP where

import Colog.Core (LogAction (LogAction))
import qualified Colog.Core as Colog
import Control.Monad.Reader
import Data.Aeson hiding (Options, defaultOptions)
import qualified Language.LSP.Logging as LSP
import Language.LSP.Server
import Language.LSP.Types
import Language.LSP.Types.SMethodMap
import qualified Language.LSP.Types.SMethodMap as SMM
import Language.LSP.VFS
import qualified Network.Simple.TCP as TCP
import Network.Socket
import System.Environment (lookupEnv)
import Unison.Codebase
import Unison.Codebase.Runtime (Runtime)
import Unison.LSP.RequestHandlers
import Unison.LSP.Types
import Unison.LSP.VFS
import Unison.Parser.Ann
import Unison.Prelude
import Unison.Symbol
import UnliftIO

getLspPort :: IO String
getLspPort = fromMaybe "5050" <$> lookupEnv "UNISON_LSP_PORT"

spawnLsp :: Codebase IO Symbol Ann -> Runtime Symbol -> IO ()
spawnLsp codebase runtime = do
  lspPort <- getLspPort
  putStrLn $ "Language server listening at 127.0.0.1:" <> lspPort <> " https://github.com/unisonweb/unison/blob/trunk/docs/ability-typechecking.markdown"
  putStrLn $ "You can view LSP setup instructions at https://github.com/unisonweb/unison/blob/trunk/docs/ability-typechecking.markdown"
  TCP.serve (TCP.Host "127.0.0.1") "5050" $ \(sock, _sockaddr) -> do
    sockHandle <- socketToHandle sock ReadWriteMode
    -- currently we have an independent VFS for each LSP client since each client might have
    -- different un-saved state for the same file.
    initVFS $ \vfs -> do
      vfsVar <- newMVar vfs
      void $ runServerWithHandles lspServerLogger lspClientLogger sockHandle sockHandle (serverDefinition vfsVar codebase runtime)
  where
    -- Where to send logs that occur before a client connects
    lspServerLogger = Colog.filterBySeverity Colog.Error Colog.getSeverity $ Colog.cmap (fmap tShow) (LogAction print)
    -- Where to send logs that occur after a client connects
    lspClientLogger = Colog.cmap (fmap tShow) LSP.defaultClientLogger

serverDefinition :: MVar VFS -> Codebase IO Symbol Ann -> Runtime Symbol -> ServerDefinition Config
serverDefinition vfsVar codebase runtime =
  ServerDefinition
    { defaultConfig = lspDefaultConfig,
      onConfigurationChange = lspOnConfigurationChange,
      doInitialize = lspDoInitialize vfsVar codebase runtime,
      staticHandlers = lspStaticHandlers,
      interpretHandler = lspInterpretHandler,
      options = lspOptions
    }

lspOnConfigurationChange :: Config -> Value -> Either Text Config
lspOnConfigurationChange _ _ = pure Config

lspDefaultConfig :: Config
lspDefaultConfig = Config

lspDoInitialize :: MVar VFS -> Codebase IO Symbol Ann -> Runtime Symbol -> LanguageContextEnv Config -> Message 'Initialize -> IO (Either ResponseError Env)
lspDoInitialize vfsVar codebase runtime context _ = pure $ Right $ Env {..}

lspStaticHandlers :: Handlers Lsp
lspStaticHandlers =
  Handlers
    { reqHandlers = lspReqHandlers,
      notHandlers = lspNotHandlers
    }

lspReqHandlers :: SMethodMap (ClientMessageHandler Lsp 'Request)
lspReqHandlers =
  mempty
    & SMM.insert STextDocumentHover (ClientMessageHandler hoverHandler)
    & SMM.insert STextDocumentCompletion (ClientMessageHandler completionHandler)
    & SMM.insert SCodeLensResolve (ClientMessageHandler codeLensResolveHandler)

lspNotHandlers :: SMethodMap (ClientMessageHandler Lsp 'Notification)
lspNotHandlers =
  mempty
    & SMM.insert STextDocumentDidOpen (ClientMessageHandler $ usingVFS . openVFS vfsLogger)
    & SMM.insert STextDocumentDidClose (ClientMessageHandler $ usingVFS . closeVFS vfsLogger)
    & SMM.insert STextDocumentDidChange (ClientMessageHandler $ usingVFS . changeFromClientVFS vfsLogger)
  where
    vfsLogger = Colog.cmap (fmap tShow) (Colog.hoistLogAction lift LSP.defaultClientLogger)

lspInterpretHandler :: Env -> Lsp <~> IO
lspInterpretHandler env@(Env {context}) =
  Iso toIO fromIO
  where
    toIO (Lsp m) = flip runReaderT context . unLspT . flip runReaderT env $ m
    fromIO m = liftIO m

lspOptions :: Options
lspOptions = defaultOptions {textDocumentSync = Just $ textDocSyncOptions}
  where
    textDocSyncOptions =
      TextDocumentSyncOptions
        { _openClose = Just True,
          _change = Just TdSyncIncremental, -- TdSyncFull
          _willSave = Just True,
          _willSaveWaitUntil = Just False,
          _save = Just (InL False)
        }