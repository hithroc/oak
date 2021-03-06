module CardList where

import Prelude
import Control.Monad.Aff (Aff)
import Network.HTTP.Affjax as AX
import Halogen as H
import Halogen.HTML as HH
import Halogen.HTML.Core(AttrName(..), ClassName(..))
import Halogen.HTML.Events as HE
import Halogen.HTML.Properties as HP
import Data.Maybe
import Data.Tuple
import Data.Array (mapWithIndex)
import Data.Array as A
import Data.Foldable
import Control.Monad.Eff.Console (CONSOLE)
import Control.Monad.Aff.Console (log)
import Data.Map as M
import Data.List (List, group')
import Data.List.NonEmpty as NE

import Card as C

type CardListState
  = { cards :: Array (Tuple Int C.Card)
    , picked :: Boolean
    , currentUrl :: String
    }

data CardListQuery a
  = PickCard Int a
  | NewCards (Array C.Card) Boolean a
  | UpdateLink a
  | GetDeckURL (String -> a)

data CardListMessage = CardPicked Int

chunksOf :: forall a. Int -> Array a -> Array (Array a)
chunksOf n xs
  | A.null xs = []
  | otherwise = A.take n xs A.: chunksOf n (A.drop n xs)

toV1Code :: List String -> String
toV1Code = intercalate "-" <<<map (\x -> NE.head x <> "x" <> show (NE.length x))<<<group'
toDeckURL :: List String -> String
toDeckURL = \x -> "http://ponyhead.com/deckbuilder?draftMode&v1code="<> toV1Code x

type CardListAff eff = Aff (ajax :: AX.AJAX, console :: CONSOLE | eff)
cardList :: String -> Maybe String -> forall m. H.Component HH.HTML CardListQuery Unit CardListMessage (CardListAff m)
cardList name req =
  H.lifecycleParentComponent
  { initialState : const initialState
  , render
  , eval
  , receiver : const Nothing
  , initializer: Nothing
  , finalizer: Nothing
  }
  where
    initialState :: CardListState
    initialState = { cards : [], picked: false, currentUrl: "" }
    render :: forall m. CardListState -> H.ParentHTML CardListQuery C.CardQuery Int (CardListAff m)
    render st =
      HH.div
        [ HP.class_ (ClassName $ if st.picked then "cardlist cardlist-picked" else "cardlist")
        ]
        [ HH.div [HP.class_ (ClassName "cardlist-header")]
          [ HH.div [HP.class_ (ClassName "cardlist-title")] [HH.text name]
          , HH.div [HP.class_ (ClassName "cardlist-count")] [HH.text $ "" <> show (A.length st.cards) <> " cards"]
          ]
        , HH.div [HP.class_ (ClassName "card-container")]
          <<< (\x -> x <> [HH.span [HP.class_ (ClassName "cardlist-clear")] []])
          <<< flip mapWithIndex st.cards $ \i c -> HH.slot (A.length st.cards - i) (C.card) (c) listen
        ]

    eval :: forall m. CardListQuery ~> H.ParentDSL CardListState CardListQuery C.CardQuery Int CardListMessage (CardListAff m)
    eval =
      case _ of
        PickCard i next -> do
          case req of
            Just path -> do
              (response :: AX.AffjaxResponse Unit) <- H.liftAff $ AX.get (path <> show i)
              pure unit
            Nothing -> pure unit
          pure next
        NewCards newcards picked next -> do
          H.modify $ _ { cards = mapWithIndex (\i -> Tuple i) newcards, picked = picked }
          eval $ UpdateLink next
        UpdateLink next -> do
          cids <- H.queryAll $ H.request C.GetCID
          H.modify $ _ { currentUrl = toDeckURL $ M.values $ cids }
          pure next
        GetDeckURL reply -> do
          st <- H.get
          pure $ reply st.currentUrl

    listen :: C.CardMessage -> Maybe (CardListQuery Unit)
    listen (C.Picked i) = Just<<<H.action $ PickCard i
    listen C.Updated = Just<<<H.action $ UpdateLink
