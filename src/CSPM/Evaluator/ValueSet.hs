-- | Provides a set implementation for machine CSP sets. This relies heavily
-- on the type checking and assumes in many places that the sets being operated
-- on are suitable for the opertion in question.
--
-- We cannot just use the built in set implementation as FDR assumes in several
-- places that infinite sets are allowed.
module CSPM.Evaluator.ValueSet (
    -- * Construction
    ValueSet(Integers, Processes, IntSetFrom),
    emptySet, fromList, toList, toSeq,
    -- * Basic Functions
    compareValueSets,
    member, card, empty,
    union, unions,
    intersection, intersections,
    difference,
    -- * Derived functions
    CartProductType(..), cartesianProduct, powerset, allSequences,
    -- * Specialised Functions
    singletonValue,
    valueSetToEventSet,
    isFinitePrintable,
)
where

import Control.Monad
import qualified Data.Foldable as F
import Data.Hashable
import qualified Data.Set as S
import qualified Data.Sequence as Sq

import CSPM.Evaluator.Exceptions
import CSPM.Evaluator.Values
import qualified CSPM.Compiler.Events as CE
import Util.Exception
import qualified Util.List as UL
import Util.PrettyPrint hiding (empty)

data CartProductType = CartDot | CartTuple deriving (Eq, Ord)

data ValueSet = 
    -- | Set of all integers
    Integers
    -- | Set of all processes
    | Processes
    -- | An explicit set of values
    | ExplicitSet (S.Set Value)
    -- | The infinite set of integers starting at lb.
    | IntSetFrom Int
    -- | A union of two sets.
    | CompositeSet ValueSet ValueSet
    -- | A set containing all sequences over the given set.
    | AllSequences ValueSet
    -- | A cartesian product of several sets.
    | CartesianProduct [ValueSet] CartProductType
    -- Only used for the internal set representation
    deriving Ord

instance Hashable ValueSet where
    hash Integers = 1
    hash Processes = 2
    hash (ExplicitSet s) = combine 3 (hash (S.toList s))
    hash (IntSetFrom lb) = combine 4 lb
    hash (AllSequences vs) = combine 5 (hash vs)
    hash (CompositeSet vs1 vs2) = combine 6 (combine (hash vs1) (hash vs2))
    hash (CartesianProduct vss _) = combine 7 (hash vss)

instance Eq ValueSet where
    s1 == s2 = compareValueSets s1 s2 == Just EQ

instance PrettyPrintable ValueSet where
    prettyPrint Integers = text "Integers"
    prettyPrint Processes = text "Proc"
    prettyPrint (IntSetFrom lb) = braces (int lb <> text "...")
    prettyPrint (AllSequences vs) = text "Seq" <> parens (prettyPrint vs)
    prettyPrint (CartesianProduct vss CartDot) =
        hcat (punctuate (text ".") (map prettyPrint vss))
    prettyPrint (CartesianProduct vss CartTuple) =
        parens (hcat (punctuate (text ",") (map prettyPrint vss)))
    prettyPrint (ExplicitSet s) =
        braces (list (map prettyPrint $ S.toList s))
    prettyPrint (CompositeSet s1 s2) =
        text "union" <> parens (prettyPrint s1 <> comma <+> prettyPrint s2)
    
instance Show ValueSet where
    show = show . prettyPrint

isFinitePrintable :: ValueSet -> Bool
isFinitePrintable (ExplicitSet vs) = True
isFinitePrintable Integers = True
isFinitePrintable Processes = True
isFinitePrintable (IntSetFrom v1) = True
isFinitePrintable (CompositeSet v1 v2) =
    isFinitePrintable v1 && isFinitePrintable v2
isFinitePrintable (CartesianProduct vss _) = and (map isFinitePrintable vss)
isFinitePrintable (AllSequences vs) = isFinitePrintable vs

flipOrder :: Maybe Ordering -> Maybe Ordering
flipOrder Nothing = Nothing
flipOrder (Just EQ) = Just EQ
flipOrder (Just LT) = Just GT
flipOrder (Just GT) = Just LT

-- | Compares two value sets using subseteq (as per the specification).
compareValueSets :: ValueSet -> ValueSet -> Maybe Ordering
-- Processes
compareValueSets Processes Processes = Just EQ
compareValueSets _ Processes = Just LT
compareValueSets Processes _ = Just GT
-- Integers
compareValueSets Integers Integers = Just EQ
compareValueSets _ Integers = Just LT
compareValueSets Integers _ = Just GT
-- IntSetFrom
compareValueSets (IntSetFrom lb1) (IntSetFrom lb2) = Just (compare lb1 lb2)
-- ExplicitSet
compareValueSets (ExplicitSet s1) (ExplicitSet s2) =
    if s1 == s2 then Just EQ
    else if S.isProperSubsetOf s1 s2 then Just LT
    else if S.isProperSubsetOf s2 s1 then Just GT
    else Nothing
-- IntSetFrom+ExplicitSet
compareValueSets (IntSetFrom lb1) (ExplicitSet s2) =
    let 
        VInt lb2 = S.findMin s2
        VInt ub2 = S.findMax s2
    in if lb1 <= lb2 then Just GT else Nothing
compareValueSets (ExplicitSet s1) (IntSetFrom lb1) =
    flipOrder (compareValueSets (IntSetFrom lb1) (ExplicitSet s1))
-- Composite Sets
compareValueSets (CompositeSet s1 s2) s =
    case (compareValueSets s1 s, compareValueSets s2 s) of
        (Nothing, _)        -> Nothing
        (_, Nothing)        -> Nothing
        (Just LT, Just x)   -> if x /= GT then Just LT else Nothing
        (Just EQ, Just x)   -> Just x
        (Just GT, Just x)   -> if x /= LT then Just GT else Nothing
compareValueSets s (CompositeSet s1 s2) = 
    flipOrder (compareValueSets (CompositeSet s1 s2) s)
compareValueSets s1 s2 | empty s1 && empty s2 = Just EQ
compareValueSets s1 s2 | empty s1 && not (empty s2) = Just LT
compareValueSets s1 s2 | not (empty s1) && empty s2 = Just GT
-- AllSequences+ExplicitSet sets
compareValueSets (ExplicitSet vs) (AllSequences vss) =
    if and (map (flip member (AllSequences vss)) (S.toList vs)) then Just LT
    -- Otherwise, there is some item in vs that is not in vss. However, unless
    -- vss is empty there must be some value in the second set that is not in
    -- the first, since (AllSequences vss) is infinite and, if the above
    -- finishes, we know the first set is finite. Hence, they would be
    -- incomparable.
    else Nothing
compareValueSets (AllSequences vss) (ExplicitSet vs) =
    flipOrder (compareValueSets (ExplicitSet vs) (AllSequences vss))
-- CartesianProduct+ExplicitSet sets
compareValueSets (ExplicitSet vs) (CartesianProduct vsets vc) =
    compareValueSets (ExplicitSet vs) (fromList (toList (CartesianProduct vsets vc)))
compareValueSets (CartesianProduct vsets vc) (ExplicitSet vs) =
    flipOrder (compareValueSets (ExplicitSet vs) (CartesianProduct vsets vc))
-- Anything else is incomparable
compareValueSets _ _ = Nothing

-- | Produces a ValueSet of the carteisan product of several ValueSets, 
-- using 'vc' to convert each sequence of values into a single value.
cartesianProduct :: CartProductType -> [ValueSet] -> ValueSet
cartesianProduct vc vss = CartesianProduct vss vc

-- | Returns the powerset of a ValueSet. This requires
powerset :: ValueSet -> ValueSet
powerset = fromList . map (VSet . fromList) . 
            filterM (\x -> [True, False]) . toList

-- | Returns the set of all sequences over the input set. This is infinite
-- so we use a CompositeSet.
allSequences :: ValueSet -> ValueSet
allSequences s = AllSequences s

-- | The empty set
emptySet :: ValueSet
emptySet = ExplicitSet S.empty

-- | Converts a list to a set
fromList :: [Value] -> ValueSet
fromList = ExplicitSet . S.fromList

-- | Converts a set to list.
toList :: ValueSet -> [Value]
toList (ExplicitSet s) = S.toList s
toList (IntSetFrom lb) = map VInt [lb..]
toList (CompositeSet s1 s2) = toList s1 ++ toList s2
toList Integers =
    let merge (x:xs) ys = x:merge ys xs in map VInt $ merge [0..] [(-1),(-2)..]
toList Processes = throwSourceError [cannotConvertProcessesToListMessage]
toList (AllSequences vs) =
    if empty vs then [] else 
    let 
        itemsAsList :: [Value]
        itemsAsList = toList vs

        list :: Integer -> [Value]
        list 0 = [VList []]
        list n = concatMap (\x -> map (app x) (list (n-1)))  itemsAsList
            where
                app :: Value -> Value -> Value
                app x (VList xs) = VList $ x:xs
        
        allSequences :: [Value]
        allSequences = concatMap list [0..]
    in allSequences
toList (CartesianProduct vss ct) =
    let cp = UL.cartesianProduct (map toList vss)
    in case ct of
            CartTuple -> map VTuple cp
            CartDot -> map VDot cp

toSeq :: ValueSet -> Sq.Seq Value
toSeq (ExplicitSet s) = F.foldMap Sq.singleton s
toSeq (IntSetFrom lb) = fmap VInt (Sq.fromList [lb..])
toSeq (CompositeSet s1 s2) = toSeq s1 Sq.>< toSeq s2
toSeq (AllSequences vs) = Sq.fromList (toList (AllSequences vs))
toSeq (CartesianProduct vss ct) = Sq.fromList (toList (CartesianProduct vss ct))
toSeq Integers = throwSourceError [cannotConvertIntegersToListMessage]
toSeq Processes = throwSourceError [cannotConvertProcessesToListMessage]

-- | Returns the value iff the set contains one item only.
singletonValue :: ValueSet -> Maybe Value
singletonValue s =
    let
        isSingleton :: ValueSet -> Bool
        isSingleton (ExplicitSet s) = S.size s == 1
        isSingleton _ = False
    in if isSingleton s then Just (head (toList s)) else Nothing

-- | Is the specified value a member of the set.
member :: Value -> ValueSet -> Bool
member v (ExplicitSet s) = S.member v s
member (VInt i) Integers = True
member (VInt i) (IntSetFrom lb) = i >= lb
member v (CompositeSet s1 s2) = member v s1 || member v s2
-- FDR does actually try and given the correct value here.
member (VProc p) Processes = True
member (VList vs) (AllSequences s) = and (map (flip member s) vs)
member (VDot vs) (CartesianProduct vss CartDot) = and (zipWith member vs vss)
member (VTuple vs) (CartesianProduct vss CartTuple) = and (zipWith member vs vss)
member v s1 = throwSourceError [cannotCheckSetMembershipError v s1]

-- | The cardinality of the set. Throws an error if the set is infinite.
card :: ValueSet -> Integer
card (ExplicitSet s) = toInteger (S.size s)
card (CompositeSet s1 s2) = card s1 + card s2
card (CartesianProduct vss _) = product (map card vss)
card s = throwSourceError [cardOfInfiniteSetMessage s]

-- | Is the specified set empty?
empty :: ValueSet -> Bool
empty (ExplicitSet s) = S.null s
empty (CompositeSet s1 s2) = empty s1 && empty s2
empty (IntSetFrom lb) = False
empty (AllSequences s) = empty s
empty (CartesianProduct vss _) = or (map empty vss)
empty Processes = False
empty Integers = False

-- | Replicated union.
unions :: [ValueSet] -> ValueSet
unions [] = emptySet
unions vs = foldr1 union vs

-- | Replicated intersection.
intersections :: [ValueSet] -> ValueSet
intersections [] = emptySet
intersections (v:vs) = foldr1 intersection vs

-- | Union two sets throwing an error if it cannot be done in a way that will
-- terminate.
union :: ValueSet -> ValueSet -> ValueSet
-- Process unions
union _ Processes = Processes
union Processes _ = Processes
-- Integer unions
union (IntSetFrom lb1) (IntSetFrom lb2) = IntSetFrom (min lb1 lb2)
union _ Integers = Integers
union Integers _ = Integers
-- Explicit unions
union (ExplicitSet s1) (ExplicitSet s2) = ExplicitSet (S.union s1 s2)
union s1 s2 = CompositeSet s1 s2

-- | Intersects two sets throwing an error if it cannot be done in a way that 
-- will terminate.
intersection :: ValueSet -> ValueSet -> ValueSet
-- Explicit intersections
intersection (ExplicitSet s1) (ExplicitSet s2) =
    ExplicitSet (S.intersection s1 s2)
-- Integer intersections
intersection (IntSetFrom lb1) (IntSetFrom lb2) = IntSetFrom (max lb1 lb2)
intersection Integers Integers = Integers
intersection x Integers = x
intersection Integers x = x
-- Integer+ExplicitSet
intersection (ExplicitSet s1) (IntSetFrom lb1) =
    let
        VInt ubs = S.findMax s1
        VInt lbs = S.findMin s1
    in if lbs >= lb1 then ExplicitSet s1
    else ExplicitSet (S.intersection (S.fromList (map VInt [lbs..ubs])) s1)
intersection (IntSetFrom lb1) (ExplicitSet s2) =
    intersection (ExplicitSet s2) (IntSetFrom lb1)
-- Process intersection
intersection Processes Processes = Processes
intersection Processes x = x
intersection x Processes = x
-- Composite Sets
intersection (CompositeSet s1 s2) s =
    CompositeSet (intersection s1 s) (intersection s2 s)
intersection s (CompositeSet s1 s2) =
    CompositeSet (intersection s s1) (intersection s s2)
-- Cartesian product and all sequences - here we simpy convert to a list and
-- compare.
intersection (CartesianProduct vss vc) s =
    intersection (fromList (toList (CartesianProduct vss vc))) s
intersection s (CartesianProduct vss vc) =
    intersection (fromList (toList (CartesianProduct vss vc))) s
intersection (AllSequences vs) s =
    intersection (fromList (toList (AllSequences vs))) s
intersection s (AllSequences vs) =
    intersection (fromList (toList (AllSequences vs))) s

difference :: ValueSet -> ValueSet -> ValueSet
difference (ExplicitSet s1) (ExplicitSet s2) = ExplicitSet (S.difference s1 s2)
difference (IntSetFrom lb1) (IntSetFrom lb2) = fromList (map VInt [lb1..(lb2-1)])
difference _ Integers = ExplicitSet S.empty
difference (IntSetFrom lb1) (ExplicitSet s1) =
    let
        VInt ubs = S.findMax s1
        VInt lbs = S.findMin s1
        card = S.size s1
        rangeSize = 1+(ubs-lbs)
        s1' = IntSetFrom lb1
        s2' = ExplicitSet s1
    in if fromIntegral rangeSize == card then
            -- is contiguous
            if lb1 == lbs then IntSetFrom (ubs+1)
            else throwSourceError [cannotDifferenceSetsMessage s1' s2']
        else
            -- is not contiguous
            throwSourceError [cannotDifferenceSetsMessage s1' s2']
difference (ExplicitSet s1) (IntSetFrom lb1) =
    ExplicitSet (S.fromList [VInt i | VInt i <- S.toList s1, i < lb1])
difference (CompositeSet s1 s2) s = CompositeSet (difference s1 s) (difference s2 s)
difference s (CompositeSet s1 s2) = difference (difference s s1) s2
difference s1 s2 = difference (fromList (toList s1)) (fromList (toList s2))

valueSetToEventSet :: ValueSet -> CE.EventSet
valueSetToEventSet = CE.fromList . map valueEventToEvent . toList
