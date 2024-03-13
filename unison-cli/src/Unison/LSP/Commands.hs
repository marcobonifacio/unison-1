{-# LANGUAGE DataKinds #-}
{-# LANGUAGE PolyKinds #-}
{-# LANGUAGE QuasiQuotes #-}
{-# LANGUAGE TypeOperators #-}

module Unison.LSP.Commands where

import Control.Lens hiding (List)
import Control.Monad.Except
import Data.Aeson qualified as Aeson
import Data.Map qualified as Map
import Data.Text qualified as Text
import Language.LSP.Protocol.Lens
import Language.LSP.Protocol.Message qualified as Msg
import Language.LSP.Protocol.Types
import Language.LSP.Server (sendRequest)
import Unison.Codebase.Editor.Input qualified as Input
import Unison.Debug qualified as Debug
import Unison.LSP.Types
import Unison.LSP.Types qualified as Lsp
import Unison.Prelude
import Unison.Symbol
import Unison.Var qualified as Var

data UnisonLspCommand
  = ReplaceText
  | Add
  | Update
  deriving (Eq, Show, Ord, Enum, Bounded)

commandName :: UnisonLspCommand -> Text
commandName = \case
  ReplaceText -> "unison.replaceText"
  Add -> "unison.add"
  Update -> "unison.update"

fromCommandName :: Text -> Maybe UnisonLspCommand
fromCommandName = \case
  "unison.replaceText" -> Just ReplaceText
  "unison.add" -> Just Add
  "unison.update" -> Just Update
  _ -> Nothing

supportedCommands :: [Text]
supportedCommands =
  commandName
    <$> [ minBound :: UnisonLspCommand
          .. maxBound :: UnisonLspCommand
        ]

replaceText ::
  --  | The text displayed to the user for this command if used in a CodeLens
  Text ->
  TextReplacement ->
  Command
replaceText title tr = Command title "replaceText" (Just [Aeson.toJSON tr])

data TextReplacement = TextReplacement
  { range :: Range,
    -- Used in things like the editor's undo buffer
    description :: Text,
    replacementText :: Text,
    fileUri :: Uri
  }

instance Aeson.ToJSON TextReplacement where
  toJSON (TextReplacement range description replacementText fileUri) =
    Aeson.object
      [ "range" Aeson..= range,
        "description" Aeson..= description,
        "replacementText" Aeson..= replacementText,
        "fileUri" Aeson..= fileUri
      ]

instance Aeson.FromJSON TextReplacement where
  parseJSON = Aeson.withObject "TextReplacement" $ \o ->
    TextReplacement
      <$> o
        Aeson..: "range"
      <*> o
        Aeson..: "description"
      <*> o
        Aeson..: "replacementText"
      <*> o
        Aeson..: "fileUri"

data AddOrUpdateArgs = AddOrUpdateParams {symbol :: Symbol, fileUri :: Uri}

instance Aeson.ToJSON AddOrUpdateArgs where
  toJSON (AddOrUpdateParams sym uri) =
    Aeson.object
      [ "symbol" Aeson..= Text.pack (Var.nameStr sym),
        "fileUri" Aeson..= uri
      ]

instance Aeson.FromJSON AddOrUpdateArgs where
  parseJSON = Aeson.withObject "AddOrUpdateArgs" $ \o -> do
    sym <- o Aeson..: "symbol"
    uri <- o Aeson..: "fileUri"
    pure $ AddOrUpdateParams (Var.named sym) uri

addCommand :: Symbol -> Uri -> Command
addCommand sym uri =
  let title = "Add Definition"
      command = commandName Add
   in Command title command (Just [Aeson.toJSON $ AddOrUpdateParams sym uri])

updateCommand :: Symbol -> Uri -> Command
updateCommand sym uri =
  let title = "Update Definition"
      command = commandName Update
   in Command title command (Just [Aeson.toJSON $ AddOrUpdateParams sym uri])

-- | Computes code actions for a document.
executeCommandHandler :: Msg.TRequestMessage 'Msg.Method_WorkspaceExecuteCommand -> (Either Msg.ResponseError (Aeson.Value |? Null) -> Lsp ()) -> Lsp ()
executeCommandHandler m respond =
  respond =<< runExceptT do
    let cmd = m ^. params . command
    let args = m ^. params . arguments
    let invalidCmdErr = throwError $ Msg.ResponseError (InR ErrorCodes_InvalidParams) "Invalid command" Nothing
    case fromCommandName cmd of
      Just ReplaceText -> case args of
        Just [Aeson.fromJSON -> Aeson.Success (TextReplacement range description replacementText fileUri)] -> do
          let params =
                ApplyWorkspaceEditParams
                  (Just description)
                  (WorkspaceEdit (Just ((Map.singleton fileUri [TextEdit range replacementText]))) Nothing Nothing)
          lift
            ( sendRequest Msg.SMethod_WorkspaceApplyEdit params $ \case
                Left err -> Debug.debugM Debug.LSP "Error applying workspace edit" err
                Right _ -> pure ()
            )
        _ -> invalidCmdErr
      Just Add -> case args of
        Just [Aeson.fromJSON -> Aeson.Success (AddOrUpdateParams sym uri)] -> do
          Lsp.sendUCMInput (Input.AddI sym)
        _ -> invalidCmdErr
      Nothing -> invalidCmdErr
    pure $ InL Aeson.Null
