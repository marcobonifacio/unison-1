module Unison.Merge.Diff
  ( nameBasedNamespaceDiff,
  )
where

import Data.Bitraversable (bitraverse)
import Data.Map.Strict qualified as Map
import Data.Semialign (alignWith)
import Data.Set qualified as Set
import Data.These (These (..))
import U.Codebase.Reference (TypeReference)
import Unison.Hash (Hash)
import Unison.HashQualified' qualified as HQ'
import Unison.Merge.Database (MergeDatabase (..))
import Unison.Merge.DeclNameLookup (DeclNameLookup)
import Unison.Merge.DeclNameLookup qualified as DeclNameLookup
import Unison.Merge.DiffOp (DiffOp (..))
import Unison.Merge.Synhash qualified as Synhash
import Unison.Merge.Synhashed (Synhashed (..))
import Unison.Merge.ThreeWay (ThreeWay (..))
import Unison.Merge.TwoWay (TwoWay (..))
import Unison.Merge.Updated (Updated (..))
import Unison.Name (Name)
import Unison.Prelude hiding (catMaybes)
import Unison.PrettyPrintEnv (PrettyPrintEnv (..))
import Unison.PrettyPrintEnv qualified as Ppe
import Unison.Referent (Referent)
import Unison.Sqlite (Transaction)
import Unison.Util.BiMultimap (BiMultimap)
import Unison.Util.BiMultimap qualified as BiMultimap
import Unison.Util.Defns (Defns (..), DefnsF2, DefnsF3, zipDefnsWith)

-- | @nameBasedNamespaceDiff db declNameLookups defns@ returns Alice's and Bob's name-based namespace diffs, each in the
-- form:
--
-- > terms :: Map Name (DiffOp (Synhashed Referent))
-- > types :: Map Name (DiffOp (Synhashed TypeReference))
--
-- where each name is paired with its diff-op (added, deleted, or updated), relative to the LCA between Alice and Bob's
-- branches. If the hash of a name did not change, it will not appear in the map.
nameBasedNamespaceDiff ::
  MergeDatabase ->
  ThreeWay DeclNameLookup ->
  ThreeWay (Defns (BiMultimap Referent Name) (BiMultimap TypeReference Name)) ->
  Transaction (TwoWay (DefnsF3 (Map Name) DiffOp Synhashed Referent TypeReference))
nameBasedNamespaceDiff db declNameLookups defns = do
  diffs <- sequence (synhashDefns <$> declNameLookups <*> defns)
  pure (diffNamespaceDefns diffs.lca <$> TwoWay {alice = diffs.alice, bob = diffs.bob})
  where
    synhashDefns ::
      DeclNameLookup ->
      Defns (BiMultimap Referent Name) (BiMultimap TypeReference Name) ->
      Transaction (DefnsF2 (Map Name) Synhashed Referent TypeReference)
    synhashDefns declNameLookup =
      -- FIXME: use cache so we only synhash each thing once
      synhashDefnsWith hashTerm hashType
      where
        hashTerm :: Referent -> Transaction Hash
        hashTerm =
          Synhash.hashTerm db.loadV1Term ppe

        hashType :: Name -> TypeReference -> Transaction Hash
        hashType name =
          Synhash.hashDecl
            (fmap (DeclNameLookup.setConstructorNames declNameLookup name) . db.loadV1Decl)
            ppe
            name

    ppe :: PrettyPrintEnv
    ppe =
      -- The order between Alice and Bob isn't important here for syntactic hashing; not sure right now if it matters
      -- that the LCA is added last
      deepNamespaceDefinitionsToPpe defns.alice
        `Ppe.addFallback` deepNamespaceDefinitionsToPpe defns.bob
        `Ppe.addFallback` deepNamespaceDefinitionsToPpe defns.lca

diffNamespaceDefns ::
  DefnsF2 (Map Name) Synhashed term typ ->
  DefnsF2 (Map Name) Synhashed term typ ->
  DefnsF3 (Map Name) DiffOp Synhashed term typ
diffNamespaceDefns =
  zipDefnsWith f f
  where
    f :: Map Name (Synhashed ref) -> Map Name (Synhashed ref) -> Map Name (DiffOp (Synhashed ref))
    f old new =
      Map.mapMaybe id (alignWith g old new)

    g :: Eq x => These x x -> Maybe (DiffOp x)
    g = \case
      This old -> Just (DiffOp'Delete old)
      That new -> Just (DiffOp'Add new)
      These old new
        | old == new -> Nothing
        | otherwise -> Just (DiffOp'Update Updated {old, new})

------------------------------------------------------------------------------------------------------------------------
-- Pretty-print env helpers

deepNamespaceDefinitionsToPpe :: Defns (BiMultimap Referent Name) (BiMultimap TypeReference Name) -> PrettyPrintEnv
deepNamespaceDefinitionsToPpe Defns {terms, types} =
  PrettyPrintEnv (arbitraryName terms) (arbitraryName types)
  where
    arbitraryName :: Ord ref => BiMultimap ref Name -> ref -> [(HQ'.HashQualified Name, HQ'.HashQualified Name)]
    arbitraryName names ref =
      BiMultimap.lookupDom ref names
        & Set.lookupMin
        & maybe [] \name -> [(HQ'.NameOnly name, HQ'.NameOnly name)]

------------------------------------------------------------------------------------------------------------------------
-- Syntactic hashing helpers

synhashDefnsWith ::
  Monad m =>
  (term -> m Hash) ->
  (Name -> typ -> m Hash) ->
  Defns (BiMultimap term Name) (BiMultimap typ Name) ->
  m (DefnsF2 (Map Name) Synhashed term typ)
synhashDefnsWith hashTerm hashType = do
  bitraverse
    (traverse hashTerm1 . BiMultimap.range)
    (Map.traverseWithKey hashType1 . BiMultimap.range)
  where
    hashTerm1 term = do
      hash <- hashTerm term
      pure (Synhashed hash term)

    hashType1 name typ = do
      hash <- hashType name typ
      pure (Synhashed hash typ)
