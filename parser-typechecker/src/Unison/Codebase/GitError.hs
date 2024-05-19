module Unison.Codebase.GitError
  ( CodebasePath,
    GitProtocolError (..),
    GitCodebaseError (..),
  )
where

import Unison.Codebase.Editor.RemoteRepo (ReadGitRepo, WriteGitRepo)
import Unison.Codebase.Path (Path)
import Unison.Codebase.ShortCausalHash (ShortCausalHash)
import Unison.Prelude

type CodebasePath = FilePath

data GitProtocolError
  = NoGit
  | UnrecognizableCacheDir ReadGitRepo CodebasePath
  | UnrecognizableCheckoutDir ReadGitRepo CodebasePath
  | --            srcPath  destPath error-description
    CopyException FilePath FilePath String
  | CloneException ReadGitRepo String
  | PushException WriteGitRepo String
  | PushNoOp WriteGitRepo
  | -- url commit Diff of what would change on merge with remote
    PushDestinationHasNewStuff WriteGitRepo
  | CleanupError SomeException
  | -- Thrown when a commit, tag, or branch isn't found in a repo.
    --                repo ref
    RemoteRefNotFound Text Text
  deriving stock (Show)
  deriving anyclass (Exception)

data GitCodebaseError h
  = NoRemoteNamespaceWithHash ReadGitRepo ShortCausalHash
  | RemoteNamespaceHashAmbiguous ReadGitRepo ShortCausalHash (Set h)
  | CouldntFindRemoteBranch ReadGitRepo Path
  deriving (Show)
