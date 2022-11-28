{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE UndecidableInstances #-}
{-# OPTIONS_GHC -Wno-orphans #-}

module Slacklinker.Models where

import Data.Aeson (Value (..))
import Slacklinker.PersistImport
import Slacklinker.Settings.Types
import Slacklinker.Types
import Web.Slack.Types qualified as Slack

$(mkModelUnprefixed $(discoverEntities) $(modelFile "models"))
