module Slacklinker.Handler.WebhookSpec (spec) where

import Database.Persist
import Slacklinker.App (runAppM, runDB)
import Slacklinker.Handler.Webhook (handleMessage)
import Slacklinker.Models
import Slacklinker.SplitUrl (SlackUrlParts (..), splitSlackUrl)
import TestApp
import TestImport
import TestUtils (createWorkspace)
import Web.Slack.Experimental.Blocks
import Web.Slack.Experimental.Events.Types
import Web.Slack.Types

sampleUrl :: (Text, SlackUrlParts)
sampleUrl = (url, fromJust $ splitSlackUrl url)
  where
    url = "https://jadeapptesting.slack.com/archives/C0451SKQN72/p1663961604007869"

urlRichText :: Text -> RichText
urlRichText url =
  RichText
    { blockId = Nothing
    , elements =
        [ RichTextSectionItemRichText
            [ RichItemLink
                ( RichLinkAttrs
                    { style = RichStyle {rsBold = False, rsItalic = False}
                    , url
                    , text = Nothing
                    }
                )
            ]
        ]
    }

messageEventWithBlocks :: [SlackBlock] -> MessageEvent
messageEventWithBlocks blocks =
  MessageEvent
    { blocks
    , channel = ConversationId "C043YJGBY49"
    , text = "nobody looks at this"
    , channelType = Channel
    , user = UserId "U043H11ES4V"
    , ts = "1663978925.099999"
    , threadTs = Nothing
    , appId = Nothing
    , botId = Nothing
    }

-- XXX: lol, DuplicateRecordFields makes update syntax not work if two fields
-- of the same name are in scope
updateThreadTs :: MessageEvent -> Maybe Text -> MessageEvent
updateThreadTs MessageEvent {..} newThreadTs = MessageEvent {threadTs = newThreadTs, ..}

spec :: Spec
spec = describe "Webhooks" do
  withApp $ describe "Should insert RepliedThread for a message" do
    it "simple link" \app -> do
      runAppM app $ do
        (wsId, teamId) <- createWorkspace
        let (url, parts) = sampleUrl
        let msg = messageEventWithBlocks [SlackBlockRichText . urlRichText $ url]

        handleMessage msg teamId

        -- FIXME: MonadFail instead of irrefutable pattern crimes
        ~(Just (Entity rtId _thread)) <- runDB $ getBy $ UniqueRepliedThread wsId parts.channelId parts.messageTs

        ~[Entity _ theLink] <- runDB $ selectList [LinkedMessageRepliedThreadId ==. rtId] []
        print theLink
        ~(Just (Entity channelId _)) <- runDB $ getBy $ UniqueJoinedChannel wsId msg.channel

        liftIO $ do
          -- This should name the message that triggered slacklinker
          theLink.joinedChannelId `shouldBe` channelId
          theLink.messageTs `shouldBe` msg.ts
          theLink.threadTs `shouldBe` Nothing
          theLink.sent `shouldBe` False

    it "no link to thread parent" \app -> do
      runAppM app $ do
        (wsId, teamId) <- createWorkspace
        let (url, parts) = sampleUrl
        let msg =
              updateThreadTs
                (messageEventWithBlocks [SlackBlockRichText . urlRichText $ url])
                (Just parts.messageTs)

        handleMessage msg teamId

        -- We should not plan a reply to a thread that links to itself
        ~Nothing <- runDB $ getBy $ UniqueRepliedThread wsId parts.channelId parts.messageTs
        pure ()
