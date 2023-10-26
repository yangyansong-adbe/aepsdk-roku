' ********************** Copyright 2023 Adobe. All rights reserved. **********************

' This file is licensed to you under the Apache License, Version 2.0 (the "License");
' you may not use this file except in compliance with the License. You may obtain a copy
' of the License at http://www.apache.org/licenses/LICENSE-2.0

' Unless required by applicable law or agreed to in writing, software distributed under
' the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR REPRESENTATIONS
' OF ANY KIND, either express or implied. See the License for the specific language
' governing permissions and limitations under the License.

' *****************************************************************************************

sub init()
  m.ButtonGroup = m.top.findNode("ButtonGroup")
  m.Warning = m.top.findNode("WarningDialog")
  m.ButtonGroup.setFocus(true)
  m.ButtonGroup.observeField("buttonSelected", "onButtonSelected")
  m.timer = m.top.findNode("MainTimer")
  m.timer.control = "start"
  m.timer.ObserveField("fire", "timerExecutor")
  m.videoTimer = m.top.findNode("VideoTimer")
  m.videoTimer.control = "none"
  m.videoTimer.ObserveField("fire", "videoTimerExecutor")
  m.video = m.top.findNode("Video")
  setContent()

  m.test_shutdown = false
  m.video_position = 0

  _initSDK()
end sub


sub _initSDK()
  '------------------------------------
  ' Initalize Adobe Edge SDK
  '------------------------------------

  m.aepSdk = AdobeAEPSDKInit()
  print "Adobe SDK version : " + m.aepSdk.getVersion()

  ADB_CONSTANTS = AdobeAEPSDKConstants()
  m.aepSdk.setLogLevel(ADB_CONSTANTS.LOG_LEVEL.VERBOSE)

  configuration = {
    "edgemedia.channel": "channel_test",
    "edgemedia.playerName": "player_test",
    "edgemedia.appVersion": "1.0.0",
  }
  test_config = ParseJson(ReadAsciiFile("pkg:/source/test_config.json"))
  if test_config <> invalid and test_config.count() > 0
    configuration[ADB_CONSTANTS.CONFIGURATION.EDGE_CONFIG_ID] = test_config.config_id
  end if

  m.aepSdk.updateConfiguration(configuration)

  ' mInfo = adb_media_init_mediainfo("test_media_name", "test_media_id", 10, "vod")
  ' mediaContextData = {}
  ' mediaContextData["videotype"] = "episode"
  ' m.aepSdk.mediaTrackSessionStart(mInfo, mediaContextData)
  ' m.aepSdk.mediaTrackEvent("media.bufferStart")
  ' m.aepSdk.mediaTrackPlay()
  ' m.aepSdk.mediaTrackSessionEnd()

  ' m.aepSdk.mediaUpdatePlayhead(10)
end sub

sub _sendEventWithCallback()
  '----------------------------------------
  ' Send an Experience Event with callback
  '----------------------------------------

  m.aepSdk.sendEvent({
    "eventType": "commerce.orderPlaced",
    "commerce": {
      "key3": "value3"
    },
    "identityMap": {
      "RIDA": [
        {
          "id": "SampleAdId",
          "authenticatedState": "ambiguous",
          "primary": false
        }
      ]
    }
  }, sub(context, result)
    print "callback result: "
    print result
    print context
    jsonObj = ParseJson(result.message)
    message = ""
    for each item in jsonObj.handle
      if item.type = "locationHint:result" then
        for each data in item.payload
          if data.scope = "EdgeNetwork" then
            message = "locationHint:EdgeNetwork: " + data.hint
          end if
        end for
      end if
    end for

    ' show result in dialog
    context.Warning.visible = "true"

    context.Warning.message = message
  end sub, m)
end sub

sub _testShutdownAPI()
  if m.aepSdk = invalid
    throw "Adobe Edge SDK is not initialized"
  end if

  counter = 0
  while counter < 20
    m.aepSdk.sendEvent({
      "eventType": "commerce.orderPlaced",
      "commerce": {
        "key1": "value1",
        "counter": counter
      }
    })
    counter++
  end while

  m.test_shutdown = true
end sub

sub onButtonSelected()

  if m.ButtonGroup.buttonSelected = 0
    'SendEventWithCallback button pressed
    _sendEventWithCallback()

  else if m.ButtonGroup.buttonSelected = 1
    'Shutdown button pressed
    _testShutdownAPI()

  else if m.ButtonGroup.buttonSelected = 2

    _testMedia()

  else
  end if
end sub

sub _testMedia()
  m.video.visible = "true"
  m.video.control = "play"
  m.video.setFocus(true)

  ' mInfo = adb_media_init_mediainfo("test_media_name", "test_media_id", 100, "vod")
  ' mediaContextData = {}
  ' mediaContextData["videotype"] = "episode"
  ' m.aepSdk.mediaTrackSessionStart(mInfo, mediaContextData)
  m.video_position = 0

  m.aepSdk.createMediaSession({
    "xdm": {
      "eventType": "media.sessionStart"
      "mediaCollection": {
        "playhead": 0,
        "sessionDetails": {
          "streamType": "video",
          "friendlyName": "test_media_name",
          "hasResume": false,
          "name": "test_media_id",
          "length": 100,
          "contentType": "vod"
        }
      }
    }
  })

end sub

'Set your information here
sub setContent()

  'Change the buttons
  Buttons = ["SendEventWithCallback", "Shutdown", "MediaTest"]
  m.ButtonGroup.buttons = Buttons

  ContentNode = CreateObject("roSGNode", "ContentNode")
  ContentNode.streamFormat = "mp4"
  ContentNode.url = "http://video.ted.com/talks/podcast/DanGilbert_2004_480.mp4"
  ContentNode.ShortDescriptionLine1 = "Can we create new life out of our digital universe?"
  ContentNode.Description = "He walks the TED2008 audience through his latest research into fourth-generation fuels -- biologically created fuels with CO2 as their feedstock. His talk covers the details of creating brand-new chromosomes using digital technology, the reasons why we would want to do this, and the bioethics of synthetic life. A fascinating Q and A with TED's Chris Anderson follows."
  ContentNode.StarRating = 80
  ContentNode.Length = 1972
  ContentNode.Title = "Craig Venter asks, Can we create new life out of our digital universe?"

  m.video.content = ContentNode
  m.video.observeField("state", "onVideoPlayerStateChange")
  m.video.observeField("position", "onPositionChange")
end sub

sub onVideoPlayerStateChange()
  position = m.video_position
  if m.video.state = "error"
    m.aepSdk.sendMediaEvent({
      "xdm": {
        "eventType": "media.error",
        "mediaCollection": {
          "playhead": position,
          "qoeDataDetails": {
            "bitrate": 35000,
            "droppedFrames": 30
          },
          "errorDetails": {
            "name": "test-buffer-start",
            "source": "player"
          }
        }
      }
    })
  else if m.video.state = "buffering"
    ' m.aepSdk.mediaTrackEvent("media.bufferStart")
    m.aepSdk.sendMediaEvent({
      "xdm": {
        "eventType": "media.bufferStart",
        "mediaCollection": {
          "playhead": position,
        }
      }
    })

  else if m.video.state = "playing"
    ' m.aepSdk.mediaTrackPlay()
    m.aepSdk.sendMediaEvent({
      "xdm": {
        "eventType": "media.play",
        "mediaCollection": {
          "playhead": position,
        }
      }
    })
    m.videoTimer.control = "start"
  else if m.video.state = "stopped"
    ' m.aepSdk.mediaTrackSessionEnd()
    m.aepSdk.sendMediaEvent({
      "xdm": {
        "eventType": "media.sessionEnd",
        "mediaCollection": {
          "playhead": position,
        }
      }
    })
    m.videoTimer.control = "stop"
  else if m.video.state = "finished"
    ' m.aepSdk.mediaTrackComplete()
    m.aepSdk.sendMediaEvent({
      "xdm": {
        "eventType": "media.sessionComplete",
        "mediaCollection": {
          "playhead": position,
        }
      }
    })
  else if m.video.state = "paused"
    ' m.aepSdk.mediaTrackPause()
    m.aepSdk.sendMediaEvent({
      "xdm": {
        "eventType": "media.pauseStart",
        "mediaCollection": {
          "playhead": position,
        }
      }
    })
  else
    print "onVideoPlayerStateChange: " + m.video.state
  end if
end sub

sub onPositionChange()
  print "Video Player Position Changed to : " m.video.position
  ' m.aepSdk.mediaUpdatePlayhead(m.video.position)
  position = m.video_position
  m.aepSdk.sendMediaEvent({
    "xdm": {
      "eventType": "media.ping",
      "mediaCollection": {
        "playhead": position,
      }
    }
  })
  m.video_position = m.video.position
  ' print
end sub

sub videoTimerExecutor()
  print "===================="
  print "Video timer started to fire a ping event on video position : " m.video.position
  ' m.aepSdk.mediaUpdatePlayhead(m.video.position)
  position = m.video_position
  m.aepSdk.sendMediaEvent({
    "xdm": {
      "eventType": "media.ping",
      "mediaCollection": {
        "playhead": position,
      }
    }
  })
  m.video_position = m.video.position
end sub

' Called when a key on the remote is pressed
function onKeyEvent(key as string, press as boolean) as boolean
  print "in MainScene.xml onKeyEvent ";key;" "; press
  if press then
    if key = "back"
      print "------ [back pressed] ------"
      if m.Warning.visible
        m.Warning.visible = false
        m.ButtonGroup.setFocus(true)
        return true
      else if m.video.visible
        m.video.control = "stop"
        m.video.visible = false
        m.ButtonGroup.setFocus(true)
        return true
      else
        return false
      end if
    else if key = "OK"
      print "------- [ok pressed] -------"
      if m.Warning.visible
        m.Warning.visible = false
        m.ButtonGroup.setFocus(true)
        return true
      end if
    else
      return false
    end if
  end if
  return false
end function

sub timerExecutor()
  if m.test_shutdown
    m.aepSdk.shutdown()
    m.aepSdk = invalid

    m.aepSdk_2 = AdobeAEPSDKInit()
    ADB_CONSTANTS = AdobeAEPSDKConstants()
    m.aepSdk_2.setLogLevel(ADB_CONSTANTS.LOG_LEVEL.VERBOSE)

    configuration = {}

    test_config = ParseJson(ReadAsciiFile("pkg:/source/test_config.json"))
    if test_config <> invalid and test_config.count() > 0
      configuration[ADB_CONSTANTS.CONFIGURATION.EDGE_CONFIG_ID] = test_config.config_id
    end if
    m.aepSdk_2.updateConfiguration(configuration)

    m.aepSdk_2.sendEvent({
      "eventType": "commerce.orderPlaced",
      "commerce": {
        "key3": "value3"
      }
    }, sub(context, result)
      jsonObj = ParseJson(result.message)
      message = ""
      for each item in jsonObj.handle
        if item.type = "locationHint:result" then
          for each data in item.payload
            if data.scope = "EdgeNetwork" then
              message = "shutdown -> re-init -> sendEvent: " + data.hint
            end if
          end for
        end if
      end for

      ' show result in dialog
      context.Warning.visible = "true"

      context.Warning.message = message
    end sub, m)

  end if

  m.test_shutdown = false
end sub
