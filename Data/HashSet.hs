{-# LANGUAGE CPP, DeriveDataTypeable #-}

------------------------------------------------------------------------
-- |
-- Module      :  Data.HashSet
-- Copyright   :  2011 Bryan O'Sullivan
-- License     :  BSD-style
-- Maintainer  :  johan.tibell@gmail.com
-- Stability   :  provisional
-- Portability :  portable
--
-- A set of /hashable/ values.  A set cannot contain duplicate items.
-- A 'HashSet' makes no guarantees as to the order of its elements.
--
-- The implementation is based on /hash array mapped trie/.  A
-- 'HashSet' is often faster than other tree-based set types,
-- especially when value comparison is expensive, as in the case of
-- strings.
--
-- Many operations have a average-case complexity of /O(log n)/.  The
-- implementation uses a large base (i.e. 16) so in practice these
-- operations are constant time.

module Data.HashSet
    (
      HashSet

    -- * Construction
    , empty
    , singleton

    -- * Combine
    , union
    , unions

    -- * Basic interface
    , null
    , size
    , member
    , insert
    , delete

    -- * Transformations
    , map

      -- * Difference and intersection
    , difference
    , intersection

    -- * Folds
    , foldl'
    , foldr
    , hashNub
    , hashNubBy

    -- * Filter
    , filter

    -- ** Lists
    , toList
    , fromList
    ) where

import Control.DeepSeq (NFData(..))
import Data.Data hiding (Typeable)
import Data.HashMap.Base (HashMap, foldrWithKey)
import Data.Hashable (Hashable)
import Data.Monoid (Monoid(..))
import GHC.Exts (build)
import Prelude hiding (filter, foldr, map, null)
import qualified Data.Foldable as Foldable
import qualified Data.HashMap.Lazy as H
import qualified Data.List as List
import Data.Typeable (Typeable)

-- | A set of values.  A set cannot contain duplicate values.
newtype HashSet a = HashSet {
      asMap :: HashMap a ()
    } deriving (Typeable)

instance (NFData a) => NFData (HashSet a) where
    rnf = rnf . asMap
    {-# INLINE rnf #-}

instance (Hashable a, Eq a) => Eq (HashSet a) where
    -- This performs two passes over the tree.
    a == b = foldr f True b && size a == size b
        where f i = (&& i `member` a)
    {-# INLINE (==) #-}

instance Foldable.Foldable HashSet where
    foldr = Data.HashSet.foldr
    {-# INLINE foldr #-}

instance (Hashable a, Eq a) => Monoid (HashSet a) where
    mempty = empty
    {-# INLINE mempty #-}
    mappend = union
    {-# INLINE mappend #-}

instance (Show a) => Show (HashSet a) where
    showsPrec d m = showParen (d > 10) $
      showString "fromList " . shows (toList m)

instance (Data a, Eq a, Hashable a) => Data (HashSet a) where
    gfoldl f z m   = z fromList `f` toList m
    toConstr _     = fromListConstr
    gunfold k z c  = case constrIndex c of
        1 -> k (z fromList)
        _ -> error "gunfold"
    dataTypeOf _   = hashSetDataType
    dataCast1 f    = gcast1 f

fromListConstr :: Constr
fromListConstr = mkConstr hashSetDataType "fromList" [] Prefix

hashSetDataType :: DataType
hashSetDataType = mkDataType "Data.HashSet" [fromListConstr]

-- | /O(1)/ Construct an empty set.
empty :: HashSet a
empty = HashSet H.empty

-- | /O(1)/ Construct a set with a single element.
singleton :: Hashable a => a -> HashSet a
singleton a = HashSet (H.singleton a ())
{-# INLINABLE singleton #-}

-- | /O(n+m)/ Construct a set containing all elements from both sets.
--
-- To obtain good performance, the smaller set must be presented as
-- the first argument.
union :: (Eq a, Hashable a) => HashSet a -> HashSet a -> HashSet a
union s1 s2 = HashSet $ H.union (asMap s1) (asMap s2)
{-# INLINE union #-}

-- TODO: Figure out the time complexity of 'unions'.

-- | Construct a set containing all elements from a list of sets.
unions :: (Eq a, Hashable a) => [HashSet a] -> HashSet a
unions = List.foldl' union empty
{-# INLINE unions #-}

-- | /O(1)/ Return 'True' if this set is empty, 'False' otherwise.
null :: HashSet a -> Bool
null = H.null . asMap
{-# INLINE null #-}

-- | /O(n)/ Return the number of elements in this set.
size :: HashSet a -> Int
size = H.size . asMap
{-# INLINE size #-}

-- | /O(min(n,W))/ Return 'True' if the given value is present in this
-- set, 'False' otherwise.
member :: (Eq a, Hashable a) => a -> HashSet a -> Bool
member a s = case H.lookup a (asMap s) of
               Just _ -> True
               _      -> False
{-# INLINABLE member #-}

-- | /O(min(n,W))/ Add the specified value to this set.
insert :: (Eq a, Hashable a) => a -> HashSet a -> HashSet a
insert a = HashSet . H.insert a () . asMap
{-# INLINABLE insert #-}

-- | /O(min(n,W))/ Remove the specified value from this set if
-- present.
delete :: (Eq a, Hashable a) => a -> HashSet a -> HashSet a
delete a = HashSet . H.delete a . asMap
{-# INLINABLE delete #-}

-- | /O(n)/ Transform this set by applying a function to every value.
-- The resulting set may be smaller than the source.
map :: (Hashable b, Eq b) => (a -> b) -> HashSet a -> HashSet b
map f = fromList . List.map f . toList
{-# INLINE map #-}

-- | /O(n)/ Difference of two sets. Return elements of the first set
-- not existing in the second.
difference :: (Eq a, Hashable a) => HashSet a -> HashSet a -> HashSet a
difference (HashSet a) (HashSet b) = HashSet (H.difference a b)
{-# INLINABLE difference #-}

-- | /O(n)/ Intersection of two sets. Return elements present in both
-- the first set and the second.
intersection :: (Eq a, Hashable a) => HashSet a -> HashSet a -> HashSet a
intersection (HashSet a) (HashSet b) = HashSet (H.intersection a b)
{-# INLINABLE intersection #-}

-- | /O(n)/ Reduce this set by applying a binary operator to all
-- elements, using the given starting value (typically the
-- left-identity of the operator).  Each application of the operator
-- is evaluated before before using the result in the next
-- application.  This function is strict in the starting value.
foldl' :: (a -> b -> a) -> a -> HashSet b -> a
foldl' f z0 = H.foldlWithKey' g z0 . asMap
  where g z k _ = f z k
{-# INLINE foldl' #-}

-- | /O(n)/ Reduce this set by applying a binary operator to all
-- elements, using the given starting value (typically the
-- right-identity of the operator).
foldr :: (b -> a -> a) -> a -> HashSet b -> a
foldr f z0 = foldrWithKey g z0 . asMap
  where g k _ z = f k z
{-# INLINE foldr #-}

-- | /O(n*min(W, n))/ Remove duplicates elements from a list. It
-- keeps only the first occurrence of each element.
--
-- The first parameter is a function which turns each element
-- into another type which the list will remove duplicate instances
-- of. For example, to remove elements of a list of tuples which
-- have the same first element, you can do:
--
-- >>> let xs = [(2, "hello"), (1, "world"), (2, "hi")] :: [(Int, String)]
-- >>> hashNubBy fst xs
-- [(2, "hello"), (1, "world")]
hashNubBy :: (Eq b, Hashable b) => (a -> b) -> [a] -> [a]
hashNubBy f = go empty
  where
    go _   []   = []
    go s (x:xs) =
      let y = f x
       in if y `member` s
            then go s xs
            else x : go (insert y s) xs
{-# INLINE hashNubBy #-}

-- | /O(n*min(W, n))/ Remove duplicates elements from a list. It
-- keeps only the first occurrence of each element.
hashNub :: (Eq a, Hashable a) => [a] -> [a]
hashNub = hashNubBy id
{-# INLINE hashNub #-}

-- | /O(n)/ Filter this set by retaining only elements satisfying a
-- predicate.
filter :: (a -> Bool) -> HashSet a -> HashSet a
filter p = HashSet . H.filterWithKey q . asMap
  where q k _ = p k
{-# INLINE filter #-}

-- | /O(n)/ Return a list of this set's elements.  The list is
-- produced lazily.
toList :: HashSet a -> [a]
toList t = build (\ c z -> foldrWithKey ((const .) c) z (asMap t))
{-# INLINE toList #-}

-- | /O(n*min(W, n))/ Construct a set from a list of elements.
fromList :: (Eq a, Hashable a) => [a] -> HashSet a
fromList = HashSet . List.foldl' (\ m k -> H.insert k () m) H.empty
{-# INLINE fromList #-}
