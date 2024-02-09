{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE RecordWildCards #-}

module Unison.UnisonFile.Type where

import Control.Lens
import Unison.ABT qualified as ABT
import Unison.DataDeclaration (DataDeclaration, EffectDeclaration (..))
import Unison.Prelude
import Unison.Reference (TermReference, TermReferenceId, TypeReference, TypeReferenceId)
import Unison.Reference qualified as Reference
import Unison.Term (Term)
import Unison.Term qualified as Term
import Unison.Type (Type)
import Unison.Type qualified as Type
import Unison.WatchKind (WatchKind)

data UnisonFile v a = UnisonFileId
  { dataDeclarationsId :: Map v (TypeReferenceId, DataDeclaration v a),
    effectDeclarationsId :: Map v (TypeReferenceId, EffectDeclaration v a),
    terms :: [(v, a {- ann for whole binding -}, Term v a)],
    watches :: Map WatchKind [(v, a {- ann for whole watch -}, Term v a)]
  }
  deriving (Generic, Show)

pattern UnisonFile ::
  Map v (TypeReference, DataDeclaration v a) ->
  Map v (TypeReference, EffectDeclaration v a) ->
  [(v, a, Term v a)] ->
  Map WatchKind [(v, a, Term v a)] ->
  UnisonFile v a
pattern UnisonFile ds es tms ws <-
  UnisonFileId
    (fmap (first Reference.DerivedId) -> ds)
    (fmap (first Reference.DerivedId) -> es)
    tms
    ws

{-# COMPLETE UnisonFile #-}

-- | A UnisonFile after typechecking. Terms are split into groups by
--  cycle and the type of each term is known.
data TypecheckedUnisonFile v a = TypecheckedUnisonFileId
  { dataDeclarationsId' :: Map v (TypeReferenceId, DataDeclaration v a),
    effectDeclarationsId' :: Map v (TypeReferenceId, EffectDeclaration v a),
    topLevelComponents' :: [[(v, a {- ann for whole binding -}, Term v a, Type v a)]],
    watchComponents :: [(WatchKind, [(v, a {- ann for whole watch -}, Term v a, Type v a)])],
    hashTermsId :: Map v (a {- ann for whole binding -}, TermReferenceId, Maybe WatchKind, Term v a, Type v a)
  }
  deriving stock (Generic, Show)

{-# COMPLETE TypecheckedUnisonFile #-}

pattern TypecheckedUnisonFile ::
  Map v (TypeReference, DataDeclaration v a) ->
  Map v (TypeReference, EffectDeclaration v a) ->
  [[(v, a, Term v a, Type v a)]] ->
  [(WatchKind, [(v, a, Term v a, Type v a)])] ->
  Map
    v
    ( a,
      TermReference,
      Maybe WatchKind,
      ABT.Term (Term.F v a a) v a,
      ABT.Term Type.F v a
    ) ->
  TypecheckedUnisonFile v a
pattern TypecheckedUnisonFile ds es tlcs wcs hts <-
  TypecheckedUnisonFileId
    (fmap (first Reference.DerivedId) -> ds)
    (fmap (first Reference.DerivedId) -> es)
    tlcs
    wcs
    (fmap (over _2 Reference.DerivedId) -> hts)

instance (Ord v) => Functor (TypecheckedUnisonFile v) where
  fmap f (TypecheckedUnisonFileId ds es tlcs wcs hashTerms) =
    TypecheckedUnisonFileId ds' es' tlcs' wcs' hashTerms'
    where
      ds' = ds <&> \(refId, decl) -> (refId, fmap f decl)
      es' = es <&> \(refId, effect) -> (refId, fmap f effect)
      tlcs' =
        tlcs
          & (fmap . fmap) \(v, a, tm, tp) -> (v, f a, Term.amap f tm, fmap f tp)
      wcs' = map (\(wk, tms) -> (wk, map (\(v, a, tm, tp) -> (v, f a, Term.amap f tm, fmap f tp)) tms)) wcs
      hashTerms' = fmap (\(a, id, wk, tm, tp) -> (f a, id, wk, Term.amap f tm, fmap f tp)) hashTerms
