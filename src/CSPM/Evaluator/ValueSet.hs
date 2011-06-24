module CSPM.Evaluator.ValueSet where

import qualified Data.Set as S

import CSPM.Evaluator.Values
import Util.PrettyPrint

data ValueSet = 
	Integers -- Set of all integers
	| Processes -- Set of all processes
	| Events -- Set of all events
	| ExplicitSet (S.Set Value)
	| IntSetFrom Integer -- {lb..}
-- | InfSetTo Integer
	| RangedSet Integer Integer -- {lb..ub}

instance Eq ValueSet where
	Integers == Integers = True
	Processes == Processes = True
	Events == Events = True
	IntSetFrom lb1 == IntSetFrom lb2 = lb1 == lb2
	RangedSet lb1 ub1 == RangedSet lb2 ub2 = lb1 == lb2 && ub1 == ub2
	ExplicitSet s1 == ExplicitSet s2 = s1 == s2
	
	ExplicitSet s == RangedSet lb ub = s == S.fromList (map VInt [lb..ub])
	RangedSet lb ub == ExplicitSet s = s == S.fromList (map VInt [lb..ub])
	
	ExplicitSet s == Events = error "TODO: events equality"
	Events == ExplicitSet s = error "TODO: events equality"
	
	_ == _ = error "Cannot compare sets"
	
instance Ord ValueSet where
	compare (ExplicitSet s1) (ExplicitSet s2) = compare s1 s2

instance PrettyPrintable ValueSet where
	prettyPrint (RangedSet lb1 lb2) = 
		braces (integer lb1 <> text "..." <> integer lb2)
	prettyPrint (ExplicitSet s) =
		braces (list (map prettyPrint $ S.toList s))

instance Show ValueSet where
	show = show . prettyPrint

emptySet = ExplicitSet S.empty

fromList :: [Value] -> ValueSet
fromList = ExplicitSet . S.fromList

toList :: ValueSet -> [Value]
toList (ExplicitSet s) = S.toList s
toList (RangedSet lb ub) = map VInt [lb..ub]

member :: Value -> ValueSet -> Bool
member v (ExplicitSet s) = S.member v s
member (VInt i) Integers = True
member (VInt i) (IntSetFrom lb) = i >= lb
member (VInt i) (RangedSet lb ub) = i >= lb && i <= ub
--member (VEvent _) Events = True

card :: ValueSet -> Integer
card (ExplicitSet s) = toInteger (S.size s)
card (RangedSet lb ub) = ub-lb+1
card (Events) = error "card(Events) Not implemented"

empty :: ValueSet -> Bool
empty Events = error "empty(Events) Not implemented"
empty Processes = error "empty(Processes) Not implemented"
empty (ExplicitSet s) = S.null s
empty (IntSetFrom lb) = False
empty (Integers) = False
empty (RangedSet lb ub) = False

mapMonotonic :: (Value -> Value) -> ValueSet -> ValueSet
mapMonotonic f (ExplicitSet s) = ExplicitSet $ S.mapMonotonic f s

unions :: [ValueSet] -> ValueSet
unions vs = foldr union (ExplicitSet S.empty) vs

intersections :: [ValueSet] -> ValueSet
intersections vs = error "Unions not implemented"

union :: ValueSet -> ValueSet -> ValueSet
union (ExplicitSet s1) (ExplicitSet s2) =
	 ExplicitSet (S.union s1 s2)
union (IntSetFrom lb1) (IntSetFrom lb2) = 
	 IntSetFrom (min lb1 lb2)
union (IntSetFrom lb) Integers =Integers
union Integers (IntSetFrom lb) =Integers
union (IntSetFrom lb1) (RangedSet lb2 ub2) | lb1 <= ub2 =
	 IntSetFrom (min lb1 lb2)
union (RangedSet lb2 ub2) (IntSetFrom lb1) | lb1 <= ub2 =
	 IntSetFrom (min lb1 lb2)
union x y | x == y =  x

intersection :: ValueSet -> ValueSet -> ValueSet
intersection (ExplicitSet s1) (ExplicitSet s2) =
	 ExplicitSet (S.intersection s1 s2)
intersection (IntSetFrom lb1) (IntSetFrom lb2) = 
	 IntSetFrom (min lb1 lb2)
intersection (IntSetFrom lb) Integers =IntSetFrom lb
intersection Integers (IntSetFrom lb) =IntSetFrom lb
intersection (IntSetFrom lb1) (RangedSet lb2 ub2) =
	if lb1 <= ub2 then RangedSet (max lb2 lb1) ub2
	else ExplicitSet S.empty
intersection (RangedSet lb2 ub2) (IntSetFrom lb1) | lb1 <= ub2 =
	intersection (IntSetFrom lb1) (RangedSet lb2 ub2)
inter x y | x == y =  x

difference :: ValueSet -> ValueSet -> ValueSet
difference (ExplicitSet s1) (ExplicitSet s2) =
	 ExplicitSet (S.difference s1 s2)
difference (IntSetFrom lb1) (IntSetFrom lb2) = 
	if lb1 < lb2 then RangedSet lb1 (lb2-1)
	else ExplicitSet S.empty
difference (IntSetFrom lb) Integers = ExplicitSet S.empty
--difference Integers (IntSetFrom lb) = 
--	 InfSetTo (lb-1)
--difference (IntSetFrom lb1) (RangedSet lb2 ub2) =
--	if lb1 <= ub2 thenRangedSet (max lb2 lb1) ub2
--	elseExplicitSet empty
--difference (RangedSet lb2 ub2) (IntSetFrom lb1) | lb1 <= ub2 =
difference x y | x == y = ExplicitSet S.empty 
