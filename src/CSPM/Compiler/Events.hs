{-# LANGUAGE FlexibleInstances, TypeSynonymInstances #-}
module CSPM.Compiler.Events (
    Event(..), newUserEvent,
    EventSet, fromList,
) where

import Data.Foldable as F
import Data.Hashable
import qualified Data.Sequence as Sq
import qualified Data.Text as T
import Util.PrettyPrint

-- | Events, as represented in the LTS.
data Event = 
    -- | The internal special event tau.
    Tau 
    -- | The internal event tick, representing termination.
    | Tick 
    -- | Any event defined in a channel definition.
    | UserEvent T.Text
    deriving (Eq, Ord)

type EventSet = Sq.Seq Event

newUserEvent :: String -> Event
newUserEvent = UserEvent . T.pack

fromList :: [Event] -> EventSet
fromList = Sq.fromList

instance Hashable Event where
    hash Tau = 1
    hash Tick = 2
    hash (UserEvent vs) = combine 3 (hash vs)
instance PrettyPrintable Event where
    prettyPrint Tau = char 'τ'
    prettyPrint Tick = char '✓'
    prettyPrint (UserEvent s) = text (T.unpack s)
instance Show Event where
    show ev = show (prettyPrint ev)

instance PrettyPrintable (Sq.Seq Event) where
    prettyPrint s = braces (list (map prettyPrint (F.toList s)))
