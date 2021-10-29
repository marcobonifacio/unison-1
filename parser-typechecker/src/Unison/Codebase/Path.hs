{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE OverloadedLists #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE PatternSynonyms   #-}
{-# LANGUAGE ViewPatterns #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE GADTs #-}

module Unison.Codebase.Path
  ( Path (..),
    -- Resolve (..),
    -- pattern Empty,
    -- singleton,
    -- Unison.Codebase.Path.uncons,
    -- absoluteEmpty,
    -- relativeEmpty',
    currentPath,
    prefix,
    -- This seems semantically invalid
    -- unprefix,
    -- prefixName,
    -- unprefixName,
    HQSplit,
    Split,
    ancestors,

    -- * tests
    isCurrentPath,
    isRoot,

    -- * things that could be replaced with `Convert` instances
    -- fromAbsoluteSplit,
    -- fromList,
    fromName,
    -- fromPath',
    fromText,
    -- toAbsoluteSplit,
    -- Should this be exposed?
    -- toList,
    toName,
    toText,
    unsplit,
    unsplitHQ,

    -- * things that could be replaced with `Parse` instances
    -- splitFromName,
    hqSplitFromName,

    -- * things that could be replaced with `Cons` instances
    -- cons,

    -- * things that could be replaced with `Snoc` instances
    Lens.snoc,
    Lens.unsnoc,

  -- This should be moved to a common util module, or we could use the 'witch' package.
  Convert(..)
  )
where
import Unison.Prelude hiding (empty, toList)

import Control.Lens hiding (Empty, cons, snoc, unsnoc)
import qualified Control.Lens as Lens
import qualified Data.List.NonEmpty as List.NonEmpty
import Data.Sequence (Seq ((:<|)))
import qualified Data.Sequence as Seq
import qualified Data.Text as Text
import qualified Unison.HashQualified' as HQ'
import Unison.Name (Convert(..), Name, Parse)
import qualified Unison.Name as Name
import Unison.NameSegment (NameSegment)
import qualified Unison.NameSegment as NameSegment
import Unison.Util.Monoid (intercalateMap)
import Data.Function (on)

data Position = Relative | Absolute | Unchecked

data Path (pos :: Position) where
  AbsoluteP :: Seq NameSegment -> Path 'Absolute
  RelativeP :: Seq NameSegment -> Path 'Relative
  UncheckedP :: Either (Path 'Absolute) (Path 'Relative) -> Path 'Unchecked

instance Eq (Path pos) where
  (==) = (==) `on` (view segments_)

instance Ord (Path pos) where
  compare = compare `on` (view segments_)

unchecked :: Path pos -> Path 'Unchecked
unchecked = match (UncheckedP . Left) (UncheckedP . Right)

  -- = Path { toSeq :: Seq NameSegment } deriving (Eq, Ord, Semigroup, Monoid)

-- newtype Absolute = Absolute { unabsolute :: Path } deriving (Eq,Ord)
-- newtype Relative = Relative { unrelative :: Path } deriving (Eq,Ord)
-- newtype Path' = Path' { unPath' :: Either Absolute Relative }
  -- deriving (Eq,Ord)

segments_ :: Lens' (Path pos) (Seq NameSegment)
segments_ = lens getter setter
  where
    getter p = match (\(AbsoluteP p) -> p) (\(RelativeP p) -> p) p
    setter :: Path pos -> Seq NameSegment -> Path pos
    setter p segments = case p of
      AbsoluteP{} -> AbsoluteP segments
      RelativeP{} -> RelativeP segments
      UncheckedP (Left p) -> UncheckedP (Left $ setter p segments)
      UncheckedP (Right p) -> UncheckedP (Right $ setter p segments)

match :: (Path 'Absolute -> r) -> (Path 'Relative -> r) -> Path pos -> r
match onAbs onRel = \case
  p@AbsoluteP{} -> onAbs p
  p@RelativeP{} -> onRel p
  (UncheckedP (Left p)) -> onAbs p
  (UncheckedP (Right p)) -> onRel p

isCurrentPath :: Path 'Relative -> Bool
isCurrentPath = (== currentPath)

currentPath :: Path 'Relative
currentPath = RelativeP mempty

isRoot :: Path 'Absolute -> Bool
isRoot = (== rootPath)

rootPath :: Path 'Absolute
rootPath = AbsoluteP mempty

toText :: Path pos -> Text
toText = match (("." <>) . segmentsToText)
                segmentsToText
  where
    segmentsToText = (intercalateMap "." NameSegment.toText . view segments_)

instance Show (Path pos) where
  show = Text.unpack . toText

type Split pos = (Path pos, NameSegment)
type HQSplit pos = (Path pos, HQ'.HQSegment)

unsplit :: Split pos -> Path pos
unsplit (p, a) = p & segments_ %~ Lens.cons a

unsplitHQ :: HQSplit pos -> HQ'.HashQualified (Path pos)
unsplitHQ (p, a) = fmap (Lens.snoc p) a

-- | examples:
--   unprefix .foo.bar .blah == .blah (absolute paths left alone)
--   unprefix .foo.bar id    == id    (relative paths starting w/ nonmatching prefix left alone)
--   unprefix .foo.bar foo.bar.baz == baz (relative paths w/ common prefix get stripped)
-- unprefix :: Path 'Absolute -> Path pos -> Path 'Unchecked
-- unprefix (Absolute prefix) (Path' p) = case p of
--   Left abs -> unabsolute abs
--   Right (unrelative -> rel) -> fromList $ dropPrefix (toList prefix) (toList rel)

-- unprefix :: Path 'Absolute -> Path 'Relative -> Path 'Relative'

-- Attach a relative path to another path.
prefix :: Path pos -> Path 'Relative -> Path pos
prefix pref suff = pref & segments_ %~ (<> (suff ^. segments_))
-- prefix (Absolute (Path prefix)) (Path' p) = case p of
--   Left (unabsolute -> abs) -> abs
--   Right (unrelative -> rel) -> Path $ prefix <> toSeq rel


-- toAbsoluteSplit :: Absolute -> (Path', a) -> (Absolute, a)
-- toAbsoluteSplit a (p, s) = (resolve a p, s)

-- fromAbsoluteSplit :: (Absolute, a) -> (Path, a)
-- fromAbsoluteSplit (Absolute p, a) = (p, a)

-- absoluteEmpty :: Absolute
-- absoluteEmpty = Absolute empty

-- relativeEmpty' :: Path'
-- relativeEmpty' = Path' (Right (Relative empty))

-- Should these be exposed??
-- toList :: Path -> [NameSegment]
-- toList = Foldable.toList . toSeq

-- fromList :: [NameSegment] -> Path
-- fromList = Path . Seq.fromList

ancestors :: Path 'Absolute -> Seq (Path 'Absolute)
ancestors p = AbsoluteP <$> Seq.inits (view segments_ p)

hqSplitFromName :: Name -> Maybe (HQSplit 'Unchecked)
hqSplitFromName = fmap (fmap HQ'.fromName) . Lens.unsnoc . fromName

splitFromName :: Name -> Maybe (Split 'Unchecked)
splitFromName = Lens.unsnoc . fromName

-- | what is this? —AI
-- unprefixName :: Absolute -> Name -> Name
-- unprefixName prefix = toName . unprefix prefix . fromName'

-- prefixName :: Absolute -> Name -> Name
-- prefixName p = toName . prefix p . fromName'

-- singleton :: NameSegment -> Path
-- singleton n = fromList [n]

-- > Path.fromName . Name.unsafeFromText $ ".Foo.bar"
-- /Foo/bar
-- Int./  -> "Int"/"/"
-- pkg/Int.. -> "pkg"/"Int"/"."
-- Int./foo -> error because "/foo" is not a valid NameSegment
--                      and "Int." is not a valid NameSegment
--                      and "Int" / "" / "foo" is not a valid path (internal "")
-- todo: fromName needs to be a little more complicated if we want to allow
--       identifiers called Function.(.)
fromName :: Name -> Path 'Unchecked
fromName n = 
  let segments = Seq.fromList . List.NonEmpty.toList . Name.segments $ n
   in if Name.isAbsolute n 
         then unchecked $ AbsoluteP segments
         else unchecked $ RelativeP segments

toName :: Path pos -> Name
toName = Name.unsafeFromText . toText

fromText :: Text -> Path 'Unchecked
fromText t = case NameSegment.splitText t of
  (True, segments) -> unchecked . AbsoluteP $ Seq.fromList segments
  (False, segments)-> unchecked . RelativeP $ Seq.fromList segments

instance Cons (Path 'Relative) (Path 'Relative) NameSegment NameSegment where
  _Cons = prism (uncurry cons) uncons where
    cons :: NameSegment -> Path 'Relative -> Path 'Relative
    cons ns = over segments_ (Lens.cons ns)
    uncons :: Path 'Relative -> Either (Path 'Relative) (NameSegment, Path 'Relative)
    uncons p = case p ^. segments_ of
      (hd :<| tl) -> Right (hd, p & segments_ .~ tl)
      _ -> Left p

instance Snoc (Path pos) (Path pos) NameSegment NameSegment where
  _Snoc = prism (uncurry snoc) unsnoc
    where
      snoc :: Path pos -> NameSegment -> Path pos
      snoc p ns = p & segments_ %~ (Lens.|> ns)
      unsnoc :: Path pos -> Either (Path pos) (Path pos, NameSegment)
      unsnoc p = case p ^. segments_ of
        (pref :> ns) -> Right (p & segments_ .~ pref, ns)
        _ -> Left p

-- instance Snoc Split' Split' NameSegment NameSegment where
--   _Snoc = prism (uncurry snoc') $ \case -- unsnoc
--     (Lens.unsnoc -> Just (s, a), ns) -> Right ((s, a), ns)
--     e -> Left e
--     where
--     snoc' :: Split' -> NameSegment -> Split'
--     snoc' (p, a) n = (Lens.snoc p a, n)

-- class Resolve l r o where
--   resolve :: l -> r -> o

-- instance Resolve Path Path Path where
--   resolve (Path l) (Path r) = Path (l <> r)

-- instance Resolve Relative Relative Relative where
--   resolve (Relative (Path l)) (Relative (Path r)) = Relative (Path (l <> r))

-- instance Resolve Absolute Relative Absolute where
--   resolve (Absolute l) (Relative r) = Absolute (resolve l r)

-- instance Resolve Path' Path' Path' where
--   resolve _ a@(Path' Left{}) = a
--   resolve (Path' (Left a)) (Path' (Right r)) = Path' (Left (resolve a r))
--   resolve (Path' (Right r1)) (Path' (Right r2)) = Path' (Right (resolve r1 r2))

-- instance Resolve Path' Split' Path' where
--   resolve l r = resolve l (unsplit' r)

-- instance Resolve Path' Split' Split' where
--   resolve l (r, ns) = (resolve l r, ns)

-- instance Resolve Absolute HQSplit HQSplitAbsolute where
--   resolve l (r, hq) = (resolve l (Relative r), hq)

-- instance Resolve Absolute Path' Absolute where
--   resolve _ (Path' (Left a)) = a
--   resolve a (Path' (Right r)) = resolve a r

instance Convert (Path pos) Text where convert = toText
instance Convert (Path pos) String where convert = show
-- instance Convert [NameSegment] Path where convert = fromList
-- instance Convert Path [NameSegment] where convert = toList
instance Convert (Path pos) Name where convert = toName
instance Convert (HQSplit pos) (HQ'.HashQualified (Path pos)) where convert = unsplitHQ
instance Parse Name (HQSplit 'Unchecked) where parse = hqSplitFromName
instance Parse Name (Split 'Unchecked) where parse = splitFromName
