{-# LANGUAGE TupleSections #-}

module Y2016.M09.D23.Solution where

import Control.Arrow ((&&&), (>>>))
import Control.Monad ((>=>))
import Data.Function (on)
import Data.List (sortBy)
import Data.Maybe (mapMaybe)
import Data.Ord
import Data.Time.Clock.POSIX (posixSecondsToUTCTime)
import Data.Time.LocalTime

-- below imports available from 1HaskellADay git repository

import Control.Presentation

import Data.BlockChain.Block.Blocks hiding (time)
import Data.BlockChain.Block.Summary hiding (time)
import Data.BlockChain.Block.Transactions hiding (sequence)
import Data.BlockChain.Block.Types

import Data.Monetary.BitCoin
import qualified Data.Monetary.Currency as BTC

import Data.Relation

import Graph.Query
import Graph.JSON.Cypher

import Y2016.M09.D22.Solution (latestTransactions)

{--
Okay, we can get the addresses from the transactions, now let's get the
bitcoins from the transaction.

In each output of each transaction there is a field called 'value.' Let's
take a look at that:

*Y2016.M09.D23.Exercise> latestSummary
Summary {blockHash = "000000000000000002f56611a761f70493a1293dadec577cd04dbd7c9a4b4477", 
         time = 1474579944, blockIndex = 1148714, height = 431032, 
         txIndices = [176864461,176863406,176863432,176863441,176861799,...]}

Now if we go to blockchain.info and look up this blockHash, we see:

... Transactions ...

<hash>   2016-09-22 21:32:24
from-to hashes 13.02390887 BTC
        total: 13.02390887 BTC
<hash>   2016-09-22 21:26:33
from-to hashes  0.08284317 BTC
                0.07408666 BTC
        total:  0.15691983 BTC

... etc ...

Now, let's look at the values of the first two transactions of this block:

*Y2016.M09.D23.Exercise> mapM_ (print . value) (concatMap out (take 2 (tx (head blk))))
1302390887
8284317
7407666

HUH!  ... HUH! ... and again I say ... HUH!

Today's Haskell exercise. Distill the transaction to the inputs, and the
outputs with a BTC (BitCoin) value for each output. Use the transactions from
the latestSummary.
--}

val2BTC :: Integer -> BitCoin
val2BTC = BTC . (/ 100000000) . fromIntegral

-- *Y2016.M09.D23.Solution> val2BTC 1302390887 ~> BTC 13.02

data Trade = Trd { tradeHash :: Hash, executed :: LocalTime,
                   ins :: [Maybe Hash], outs :: [(Hash, BitCoin)] }
   deriving (Eq, Ord, Show)

tx2trade :: Transaction -> Trade
tx2trade tx = Trd (hashCode tx)
                  (utcToLocalTime (TimeZone (negate 300) False "EST")
                                . posixSecondsToUTCTime . fromIntegral $ time tx)
                  (map (prevOut >=> addr) (inputs tx))
                  (mapMaybe (\o -> fmap (,val2BTC (value o)) (addr o)) (out tx))

-- write this as an applicative functor, maybe? Something like:
-- tx2trade = Trd <$> hashCode <*> show . posixSecondsToUT . fromIntegral NOPE!

{--
*Y2016.M09.D23.Solution> latestTransactions ~> x
*Y2016.M09.D23.Solution> length x ~> 1022
*Y2016.M09.D23.Solution> let trds = map tx2trade x
*Y2016.M09.D23.Solution> head trds ~>
Trd {tradeHash = "77f02eb1f8bac7bb3eb7b61e2367ed4e220a916b5d2175c65f83dfa337f670c7",
     executed = 2016-09-25 19:27:58, ins = [Nothing],
     outs = [("18cBEMRxXHqzWWCxZNtU91F5sbUNKhL5PX",BTC 12.79)]}

What was the biggest trade, BitCoin-value-wise, from the latestSummary?

*Y2016.M09.D23.Solution> let biggestBTC = sortBy (compare `on` Down . sum . map (BTC.value . snd) . outs) trds 
*Y2016.M09.D23.Solution> head biggestBTC ~>
Trd {tradeHash = "dcc69cc06db22b5a768f0ba7eb1dfe156b3c471bc7ef3d3eb3639c801a7960d3", 
     executed = 2016-09-25 19:22:05, 
     ins = [Just "17wGVXsER3oxZ5p49N3q6Sui4yxsiU8iv4"], 
     outs = [("1BJuEryfmH9dpELJyUaJgVPdAmYMv3Yv4G",BTC 230.73),
             ("3CowhhFbSxJyjSZzAvKtVJcWntpftbbdAt",BTC 0.18)]}

What was the biggest trade, most addresses (ins and outs)?
*Y2016.M09.D23.Solution> let mostAddrs = sortBy (compare `on` Down . (length . outs &&& length . ins >>> uncurry (+))) trds 
*Y2016.M09.D23.Solution Control.Arrow> head mostAddrs 
Trd {tradeHash = "d0ad5ecd91f8556030695d402edce6da8834d06229ef2aba0cd845f1f8de2095", 
     executed = 2016-09-25 19:22:23, 
     ins = [Just "1FdPvoUju25SsWZebk2qfKKpRquuz1siN7"], 
     outs = [("18ypMeqLw3Ma6CnZoPzWGtmFWhMra8uFaP",BTC 0.00),...]}
*Y2016.M09.D23.Solution Control.Arrow> length . outs $ head mostAddrs 
2400

Okay. Wow!
--}

{-- BONUS -----------------------------------------------------------------

Represent Trade as a set of relations. Upload those relations to a graph
database for your viewing pleasure. Share an image of some of the transactions.

--}

data Flow = IN | OUT deriving (Eq, Ord, Show)

instance Edge Flow where
   asEdge = show

data Participant = From Hash | Start | To (Hash, BitCoin)
   deriving (Eq, Ord, Show)

in2part :: Maybe Hash -> Participant
in2part Nothing = Start
in2part (Just h) = From h

instance Node Participant where
   asNode Start = "Start { name: 'Begin' }"
   asNode (From h) = "From { " ++ addrRep h ++ " }"
   asNode (To (h,BTC b)) = "To { " ++ addrRep h ++ ", btc: " ++ laxmi 2 b ++ " }"

instance Node Trade where
   asNode tr = "Trade { " ++ addrRep (tradeHash tr) ++ ", executed: '" 
                          ++ show (executed tr) ++ "' }"

addrRep :: Hash -> String
addrRep h = "nick: '" ++ take 4 h ++ "', zhash: '" ++ h ++ "'"

trade2relations :: Trade -> [Relation Participant Flow Trade]
trade2relations tr = 
      map (\h -> Rel (in2part h) IN tr) (ins tr)
   ++ map (\o -> Rel (To o) OUT tr) (outs tr)

{--
So, for a new set of transactions and, then: trades (1269 transactions):
*Y2016.M09.D23.Solution> let t2r = concatMap trade2relations trds
*Y2016.M09.D23.Solution> length t2r ~> 7273
*Y2016.M09.D23.Solution> getGraphResponse ("http://neo4j:password@127.0.0.1:7474/" ++ transaction) (map (mkCypher "a" "rel" "b") t2r)
"{\"results\":[{\"columns\":[],\"data\":[]},{\"columns\":[],\"data\":[]},...
... ],\"errors\":[]}\n"

We show some random trades in this block, and a couple of trades with multiple
addresses on the solution tweet.

A sample Cypher-query to obtain some non-trivial trades is:
MATCH path=(o)-[:OUT]->(t)<-[:IN]-(i) 
RETURN path, count(o) 
ORDER BY count(o) DESC
LIMIT 25
--}
