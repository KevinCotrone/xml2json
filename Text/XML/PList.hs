{-# LANGUAGE ViewPatterns, OverloadedStrings #-}
module Text.XML.PList
  (
{-| This module is like `Text.XML.ToJSON', but it handles plist xml file.
 -}
    parseXML
  , xmlToJSON
  , tokensToJSON
  , elementToJSON
  , plistValue
  , module Text.XML.ToJSON
  ) where

import Control.Monad (liftM)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.ByteString.Lazy as L
import qualified Data.HashMap.Strict as HM
import Text.XML.ToJSON.Builder (Element(..))
import qualified Text.XML.ToJSON as ToJSON
import Data.Aeson (Value(..), FromJSON, fromJSON, Result(Error, Success))
import Data.Attoparsec.Text (parseOnly, number, Number)
import Data.Conduit (($=), ($$), MonadThrow(monadThrow))
import qualified Data.Conduit.List as C
import qualified Text.HTML.TagStream.Text as T
import Text.XML.ToJSON hiding (parseXML, xmlToJSON, tokensToJSON, elementToJSON)

-- | parse xml to haskell data type by using aeson's `FromJSON'.
parseXML :: (MonadThrow m, FromJSON a) => L.ByteString -> m a
parseXML s = xmlToJSON s >>= convert
  where
    convert v =
        case fromJSON v of
            Error err -> monadThrow (JSONParseError err)
            Success a -> return a

-- | Convert plist lazy bytestring to aeson `Value'
xmlToJSON :: MonadThrow m => L.ByteString -> m Value
xmlToJSON s = liftM (elementToJSON . tokensToElement) $ C.sourceList (L.toChunks s) $= T.tokenStreamBS $$ C.consume

-- | Convert plist `Element' to aeson `Value'
elementToJSON :: Element -> Value
elementToJSON (Element _ _ [("plist", Element _ _ (item : _))]) =
    plistValue item
elementToJSON _ = error "invalid plist root element."

-- |Convert plist xml format of `T.Token's to aeson `Value', combining of `tokensToElement' and `elementToJSON'
tokensToJSON :: [T.Token] -> Value
tokensToJSON = elementToJSON . tokensToElement

plistValue :: (Text, Element) -> Value
plistValue (t, elm) = case t of
    "string"    -> String (getText elm)
    "data"      -> String (getText elm)
    "integer"   -> Number $ parseNumber (getText elm)
    "float"     -> Number $ parseNumber (getText elm)
    "real"      -> Number $ parseNumber (getText elm)
    "dict"      -> plistObject elm
    "true"      -> Bool True
    "false"     -> Bool False
    "date"      -> error "date support is not implemented"
    _           -> Object $ HM.fromList $ [("type", String t), ("value", ToJSON.elementToJSON elm)]
  where
    parseNumber :: Text -> Number
    parseNumber s = either (error . ("parse number failed:"++)) id $ parseOnly number s

    plistObject :: Element -> Value
    plistObject (Element _ _ cs) =
        Object $ HM.fromList $ mergeKeyValues cs

    mergeKeyValues :: [(Text, Element)] -> [(Text, Value)]
    mergeKeyValues xs = loop xs []
      where
        loop [] kv = kv
        loop ((isKey -> True, getText -> key) : rest) kv =
            case rest of
                (item@(isKey -> False, _) : rest') ->
                     loop rest' ((key, plistValue item) : kv)
                _ -> loop rest  ((key, Null)            : kv)
        loop ((tag,_):_) _ = error $ "expect <key> but got <"++T.unpack tag++">"

    isKey s = s == "key"

    getText :: Element -> Text
    getText (Element [] vs []) = T.concat vs
    getText _ = error "not a text node [getValue]"