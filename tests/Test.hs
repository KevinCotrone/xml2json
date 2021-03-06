{-# LANGUAGE OverloadedStrings #-}
import Control.Applicative
import Control.Monad.Trans.Resource (ExceptionT, runExceptionT )
import Control.Exception (throw)
import Data.Maybe (fromMaybe)
import Data.Functor.Identity (Identity(runIdentity))
import qualified Data.ByteString.Char8 as S
import qualified Data.ByteString.Lazy as L
import Data.ByteString.Lazy.Char8 ()
import Data.Text (Text)
import qualified Data.Text.Encoding as T
import Data.Aeson.Types (typeMismatch)
import Data.Aeson (decode, FromJSON(parseJSON), (.:), Value(Object, Array))
import qualified Data.Vector as V
import Text.XML.ToJSON (xmlToJSON, parseXML)
import qualified Text.XML.PList as PList
import Test.Hspec

toLazy :: S.ByteString -> L.ByteString
toLazy s = L.fromChunks [s]

cases :: [(String, L.ByteString, Value)]
cases =
  [ ( "basic"
    , toLazy $ T.encodeUtf8
      "<user>\
         \<name>foo</name>\
         \<addr>bar road</addr>\
      \</user>"
    , fromMaybe "impossible" $ decode
      "{\"user\":{\"name\":\"foo\",\"addr\":\"bar road\"}}"
    )
  , ( "unicode"
    , toLazy $ T.encodeUtf8
      "<?xml encoding=\"utf-8\"?>\n\
      \<user>\
         \<name>测试</name>\
         \<addr>bar road</addr>\
      \</user>"
    , fromMaybe "impossible" $ decode $ toLazy $ T.encodeUtf8
      "{\"user\":{\"name\":\"测试\",\"addr\":\"bar road\"}}"
    )
  , ( "array"
    , toLazy $ T.encodeUtf8
      "<users>\
        \<user>\
         \<name>foo</name>\
         \<addr>foo road</addr>\
        \</user>\
        \<user>\
         \<name>bar</name>\
         \<addr>bar road</addr>\
        \</user>\
        \<user>\
         \<name>test</name>\
         \<addr>test road</addr>\
        \</user>\
      \</users>"
    , fromMaybe "impossible" $ decode
      "{\"users\":\
         \{\"user\":\
            \[{\"name\":\"foo\",\"addr\":\"foo road\"}\
            \,{\"name\":\"bar\",\"addr\":\"bar road\"}\
            \,{\"name\":\"test\",\"addr\":\"test road\"}\
            \]\
         \}\
       \}"
    )
  ]

plistCases :: [(String, L.ByteString, Value)]
plistCases =
    [ ( "basic"
      , toLazy $ T.encodeUtf8
        "<plist>\
          \<dict>\
            \<key>name</key>\
            \<string>foo</string>\
            \<key>addr</key>\
            \<string>bar road</string>\
            \<key>age</key>\
            \<integer>25</integer>\
            \<key>nil key</key>\
            \<key>income</key>\
            \<float>234.223</float>\
            \<key>extra</key>\
            \<dict>\
              \<key>sex</key>\
              \<string>male</string>\
            \</dict>\
            \<key>array</key>\
            \<array>\
              \<string>blahblah</string>\
              \<integer>200</integer>\
              \<real>100.5</real>\
              \<dict>\
                \<key>sex</key>\
                \<string>male</string>\
              \</dict>\
            \</array>\
          \</dict>\
        \</plist>"
      , fromMaybe "impossible" $ decode
        "{\"name\":\"foo\"\
        \,\"addr\":\"bar road\"\
        \,\"age\":25\
        \,\"nil key\":null\
        \,\"income\":234.223\
        \,\"extra\":\
          \{\"sex\":\"male\"\
          \}\
        \,\"array\":\
          \[\"blahblah\"\
          \,200\
          \,100.5\
          \,{\"sex\":\"male\"\
           \}\
          \]\
        \}"
      )
    ]

runExcT :: ExceptionT Identity a -> a
runExcT m = either throw id $ runIdentity $ runExceptionT m

testOne :: (String, L.ByteString, Value) -> Spec
testOne (desc, xml, json) =
    it desc $
        let v = runExcT (xmlToJSON xml)
        in  v == json

testPList :: (String, L.ByteString, Value) -> Spec
testPList (desc, xml, json) =
    it desc $
        let v = runExcT (PList.xmlToJSON xml)
        in  v == json

data User = User
  { name :: Text
  , addr :: Text
  } deriving (Eq)

data UserList = UserList
  { userList :: [User]
  , userCount :: Int
  } deriving (Eq)

instance FromJSON User where
    parseJSON (Object o) =
        User <$> o .: "name"
             <*> o .: "addr"
    parseJSON o = typeMismatch "User" o

instance FromJSON UserList where
    parseJSON (Object o) = do
        root <- o .: "users"
        UserList <$> (root .: "user" >>= parseUserList)
                 <*> fmap read (root .: "count")
      where
        parseUserList (Array a) =
            mapM parseJSON (V.toList a)
        parseUserList a = typeMismatch "UserList.userList" a
    parseJSON o = typeMismatch "UserList" o

main :: IO ()
main = hspec $ do
    describe "basic cases" $ mapM_ testOne cases
    describe "parse" $
        it "user list" $
            let a = runExcT $ parseXML
                      "<users>\
                        \<count>100</count>\
                        \<user><name>foo</name><addr>foo addr</addr></user>\
                        \<user><name>bar</name><addr>bar addr</addr></user>\
                      \</users>"
            in  a == UserList [User "foo" "foo addr", User "bar" "bar addr"] 100
    describe "plist" $ mapM_ testPList plistCases
