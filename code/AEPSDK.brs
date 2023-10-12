' ********************** Copyright 2023 Adobe. All rights reserved. **********************
' *
' * This file is licensed to you under the Apache License, Version 2.0 (the "License");
' * you may not use this file except in compliance with the License. You may obtain a copy
' * of the License at http://www.apache.org/licenses/LICENSE-2.0
' *
' * Unless required by applicable law or agreed to in writing, software distributed under
' * the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR REPRESENTATIONS
' * OF ANY KIND, either express or implied. See the License for the specific language
' * governing permissions and limitations under the License.
' *
' *****************************************************************************************

' *********************************** MODULE: public API **********************************

' Return the Adobe SDK constants

function AdobeAEPSDKConstants() as object
    return {
        CONFIGURATION: {
            EDGE_CONFIG_ID: "edge.configId",
            EDGE_DOMAIN: "edge.domain",
            MEDIA_CHANNEL: "edgemedia.channel",
            MEDIA_PLAYER_NAME: "edgemedia.playerName",
            MEDIA_APP_VERSION: "edgemedia.appVersion",
        },
        LOG_LEVEL: {
            VERBOSE: 0,
            DEBUG: 1,
            INFO: 2,
            WARNING: 3,
            ERROR: 4
        },
        MEDIA: {
            ' EVENT_TYPE: {
            '     MEDIA_AD_BREAK_START: "MediaAdBreakStart"
            '     MEDIA_AD_BREAK_COMPLETE: "MediaAdBreakComplete"
            '     MEDIA_AD_BREAK_SKIP: "MediaAdBreakSkip"
            '     MEDIA_AD_START: "MediaAdStart"
            '     MEDIA_AD_COMPLETE: "MediaAdComplete"
            '     MEDIA_AD_SKIP: "MediaAdSkip"
            '     MEDIA_CHAPTER_START: "MediaChapterStart"
            '     MEDIA_CHAPTER_COMPLETE: "MediaChapterComplete"
            '     MEDIA_CHAPTER_SKIP: "MediaChapterSkip"
            '     MEDIA_BUFFER_START: "MediaBufferStart"
            '     MEDIA_BUFFER_COMPLETE: "MediaBufferComplete"
            '     MEDIA_SEEK_START: "MediaSeekStart"
            '     MEDIA_SEEK_COMPLETE: "MediaSeekComplete"
            '     MEDIA_BITRATE_CHANGE: "MediaBitrateChange"
            ' },
            MEDIA_TYPE: {
                VIDEO: 0,
                AUDIO: 1,
            },
        }

    }
end function

' -------------------------------------------------------------
' Media Roku SDK:
' mediaType = invalid as dynamic
'
' AEP Mobile SDK:
' resumed: Bool = false
' prerollWaitingTime: Int = DEFAULT_PREROLL_WAITING_TIME_IN_MS
' granularAdTracking: Bool = false
' -------------------------------------------------------------
function adb_media_init_mediainfo(name as string, id as string, length as double, streamType as string, mediaType = 0 as integer) as object
    if mediaType = 1 then
        mediaTypeString = "audio"
    else
        mediaTypeString = "video"
    end if

    return {
        id: id,
        name: name,
        length: length,
        streamType: streamType,
        mediaType: mediaTypeString
    }
end function

function adb_media_init_adinfo(name as string, id as string, position as double, length as double) as object
    return {
        id: id,
        name: name,
        length: length,
        position: position
    }
end function

function adb_media_init_chapterinfo(name as string, position as double, length as double, startTime as double) as object
    return {
        name: name,
        length: length,
        position: position,
        startTime: startTime
    }
end function

function adb_media_init_adbreakinfo(name as string, startTime as double, position as double) as object
    return {
        name: name,
        startTime: startTime,
        position: position
    }
end function
' -------------------------------------------------------------
' Media Roku SDK:
' adb_media_init_qosinfo()
' -------------------------------------------------------------
function adb_media_init_qoeinfo(bitrate as double, startupTime as double, fps as double, droppedFrames as double) as object
    return {
        bitrate: bitrate,
        fps: fps,
        droppedFrames: droppedFrames,
        startupTime: startupTime
    }
end function

' *****************************************************************************
'
' Initialize the Adobe SDK and return the public API instance.
' The following variables are reserved to hold SDK instances in GetGlobalAA():
'   - GetGlobalAA()._adb_public_api
'   - GetGlobalAA()._adb_main_task_node
'   - GetGlobalAA()._adb_serviceProvider_instance
'
' @return instance as object : public API instance
'
' *****************************************************************************

function AdobeAEPSDKInit() as object

    if GetGlobalAA()._adb_public_api <> invalid then
        _adb_logInfo("AdobeAEPSDKInit() - Unable to initialize a new SDK instance as there is an existing active instance. Call shutdown() API for existing instance before initializing a new one.")
        return GetGlobalAA()._adb_public_api
    end if

    _adb_logDebug("AdobeAEPSDKInit() - Initializing the SDK.")

    ' create the SDK thread
    _adb_createTaskNode()

    if _adb_retrieveTaskNode() = invalid then
        _adb_logDebug("AdobeAEPSDKInit() - Failed to initialize the SDK, task node is invalid.")
        return invalid
    end if

    ' listen response events
    _adb_observeTaskNode("responseEvent", "_adb_handleResponseEvent")

    GetGlobalAA()._adb_public_api = {

        ' ********************************
        '
        ' Return SDK version
        '
        ' @return version as string
        '
        ' ********************************

        getVersion: function() as string
            return _adb_sdkVersion()
        end function,

        ' ********************************************************************************************************
        '
        ' Set log level
        '
        ' @param level as integer : the accepted values are (VERBOSE: 0, DEBUG: 1, INFO: 2, WARNING: 3, ERROR: 4)
        '
        ' ********************************************************************************************************

        setLogLevel: function(level as integer) as void
            _adb_logDebug("API: setLogLevel()")
            if(level < 0 or level > 4) then
                _adb_logError("setLogLevel() - Invalid log level:(" + StrI(level) + ").")
                return
            end if
            ' event data: { "level": level }
            data = {}
            data[m._private.cons.EVENT_DATA_KEY.LOG.LEVEL] = level

            event = _adb_RequestEvent(m._private.cons.PUBLIC_API.SET_LOG_LEVEL, data)
            m._private.dispatchEvent(event)
        end function,

        ' ***********************************************************************
        '
        ' Call this function to shutdown the SDK and drop the further API calls.
        '
        ' ***********************************************************************

        shutdown: function() as void
            _adb_logDebug("API: shutdown()")

            if GetGlobalAA()._adb_public_api <> invalid then
                ' stop the task node
                _adb_stopTaskNode()
                ' clear the cached callback functions
                m._private.cachedCallbackInfo = {}
                ' clear the global reference
                GetGlobalAA()._adb_public_api = invalid
            end if

        end function,

        ' ***********************************************************************
        '
        ' Call this function to reset the Adobe identities such as ECID from the SDK.
        '
        ' ***********************************************************************

        resetIdentities: function() as void
            _adb_logDebug("API: resetIdentities()")
            event = _adb_RequestEvent(m._private.cons.PUBLIC_API.RESET_IDENTITIES, invalid)
            m._private.dispatchEvent(event)
        end function,

        ' **********************************************************************************
        '
        ' Call this function before using any other public APIs.
        ' For example, if calling sendEvent() without a valid configuration in the SDK,
        ' the SDK will drop the Edge event.
        '
        ' @param configuration as object
        '
        ' **********************************************************************************

        updateConfiguration: function(configuration as object) as void
            _adb_logDebug("API: updateConfiguration()")
            if _adb_isEmptyOrInvalidMap(configuration) then
                _adb_logError("updateConfiguration() - Cannot update configuration as the configuration is invalid.")
                return
            end if
            event = _adb_RequestEvent(m._private.cons.PUBLIC_API.SET_CONFIGURATION, configuration)
            m._private.dispatchEvent(event)
            m._private.latestConfiguration.Append(configuration)
        end function,

        ' *************************************************************************************
        '
        ' Send event.
        '
        ' This function will automatically add an identity property, the Experience Cloud Identifier (ECID),
        ' to each Edge network request within the Experience event's "XDM IdentityMap".
        ' Also "ImplementationDetails" are automatically collected and are sent with every Experience Event.
        ' If you would like to include this information in your dataset, add the "Implementation Details"
        ' field group to the schema tied to your dataset.
        '
        ' This function allows passing custom identifiers using identityMap.
        '
        ' @param data as object : xdm data
        ' @param [optional] callback as function(context, result) : handle Edge response
        ' @param [optional] context as dynamic : context to be passed to the callback function
        '
        ' *************************************************************************************

        sendEvent: function(xdmData as object, callback = _adb_defaultCallback as function, context = invalid as dynamic) as void
            _adb_logDebug("API: sendEvent()")
            if _adb_isEmptyOrInvalidMap(xdmData) then
                _adb_logError("sendEvent() - Cannot send event, invalid XDM data")
                return
            end if
            ' event data: { "xdm": xdmData }
            ' add a timestamp to the XDM data
            xdmData.timestamp = _adb_ISO8601_timestamp()
            event = _adb_RequestEvent(m._private.cons.PUBLIC_API.SEND_EDGE_EVENT, {
                xdm: xdmData,
            })

            ' event.data.xdm.timestamp = event.getISOTimestamp()
            if callback <> _adb_defaultCallback then
                ' store callback function
                callbackInfo = {
                    cb: callback,
                    context: context,
                    timestampInMillis: event.timestampInMillis
                }
                m._private.cachedCallbackInfo[event.uuid] = callbackInfo
                _adb_logDebug("sendEvent() - Cached callback function for event with uuid: " + FormatJson(event.uuid))
            end if
            m._private.dispatchEvent(event)
        end function,

        ' ****************************************************************************************************
        '
        ' Note: Please do not call this API if you do not have both the Adobe Media SDK and the Edge SDK
        ' running in the same channel and you need to use the same ECID in both SDKs.
        '
        ' By default, the Edge SDK automatically generates an ECID (Experience Cloud ID) when first used.
        ' If the Edge SDK and the previous media SDK are running in the same channel, calling this function
        ' can keep both SDKs running with the same ECID.
        '
        ' Call this function before using other public APIs. Otherwise, an automatically generated ECID will be assigned.
        ' Whenever the ECID is changed in the Media SDK, this API needs to be called to synchronize it in both SDKs.
        '
        ' @param ecid as string : the ECID generated by the previous media SDK
        '
        ' ****************************************************************************************************

        setExperienceCloudId: function(ecid as string) as void
            _adb_logDebug("API: setExperienceCloudId()")
            if _adb_isEmptyOrInvalidString(ecid)
                _adb_logError("setExperienceCloudId() - Cannot set ECID, invalid ecid:(" + FormatJson(ecid) + ") passed.")
                return
            end if
            ' event data: { "ecid": ecid }
            data = {}
            data[m._private.cons.EVENT_DATA_KEY.ecid] = ecid
            event = _adb_RequestEvent(m._private.cons.PUBLIC_API.SET_EXPERIENCE_CLOUD_ID, data)
            m._private.dispatchEvent(event)
        end function,

        ' ****************************************************************************************************
        '                                           Media APIs
        ' ****************************************************************************************************

        _createMediaSession: function(xdmData as object) as void
            _adb_logDebug("API: _createMediaSession()")
            ' TODO: validate input

            m._private.mediaSession.startNewSession()
            m._sendMediaEvent(xdmData)

        end function,

        _sendMediaEvent: function(xdmData as object) as void
            _adb_logDebug("API: _sendMediaEvent()")
            ' TODO: validate input

            sessionId = m._private.mediaSession.getClientSessionIdAndRecordAction(xdmData.xdm.eventType)

            data = {
                clientSessionId: sessionId,
                timestampInISO8601: _adb_ISO8601_timestamp(),
                param: xdmData
            }
            event = _adb_RequestEvent(m._private.cons.PUBLIC_API.SEND_MEDIA_EVENT, data)
            m._private.dispatchEvent(event)

            if xdmData.xdm.eventType = "media.sessionEnd"
                m._private.mediaSession.endSession()
            end if
        end function,

        mediaTrackSessionStart: function(mediaInfo as object, ContextData = invalid as object) as void
            _adb_logDebug("API: mediaTrackSessionStart()")
            ' TODO: validate mediaInfo
            ' TODO: add ContextData to xdmData
            configuration = m._private.latestConfiguration
            channel = configuration["edgemedia.channel"]
            playerName = configuration["edgemedia.playerName"]
            appVersion = configuration["edgemedia.appVersion"]

            xdmData = {
                "xdm": {
                    "eventType": "media.sessionStart"
                    "mediaCollection": {
                        "playhead": 0,
                        "sessionDetails": {
                            "playerName": playerName,
                            "streamType": mediaInfo.mediaType,
                            "friendlyName": mediaInfo.name,
                            "hasResume": false,
                            "channel": channel,
                            "appVersion": appVersion,
                            "name": mediaInfo.id,
                            "length": mediaInfo.length,
                            "contentType": mediaInfo.streamType
                        }
                    }
                }
            }
            m._createMediaSession(xdmData)
        end function,

        mediaTrackSessionEnd: function() as void
            _adb_logDebug("API: mediaTrackSessionEnd()")

            xdmData = {
                xdm: {
                    "eventType": "media.sessionEnd",
                    "mediaCollection": {
                        ' TODO: update playhead
                        "playhead": 100,
                        ' "sessionID": sessionId
                    }
                }
            }

            m._sendMediaEvent(xdmData)
            ' sessionId = m._private.mediaSession.getClientSessionIdAndRecordAction(m._private.cons.MEDIA_EVENT_NAME.SESSION_END)
            ' data = {
            '     mediaEventName: m._private.cons.MEDIA_EVENT_NAME.SESSION_END,
            '     timestampInISO8601: _adb_ISO8601_timestamp(),
            '     clientSessionId: sessionId
            ' }
            ' event = _adb_RequestEvent(m._private.cons.PUBLIC_API.MEDIA_API, data)
            ' m._private.dispatchEvent(event)

        end function,

        ' depracated API:
        ' mediaTrackLoad
        ' mediaTrackUnload
        ' trackStart

        mediaTrackPlay: function() as void
            _adb_logDebug("API: mediaTrackPlay()")
            xdmData = {
                xdm: {
                    "eventType": "media.play",
                    "mediaCollection": {
                        ' TODO: update playhead
                        "playhead": 0,
                        ' "sessionID": sessionId
                    }
                }
            }

            m._sendMediaEvent(xdmData)
            ' sessionId = m._private.mediaSession.getClientSessionIdAndRecordAction(m._private.cons.MEDIA_EVENT_NAME.PLAY)
            ' data = {
            '     mediaEventName: m._private.cons.MEDIA_EVENT_NAME.PLAY,
            '     timestampInISO8601: _adb_ISO8601_timestamp(),
            '     clientSessionId: sessionId
            ' }
            ' event = _adb_RequestEvent(m._private.cons.PUBLIC_API.MEDIA_API, data)
            ' m._private.dispatchEvent(event)
        end function,

        mediaTrackPause: function() as void
            _adb_logDebug("API: mediaTrackPause()")
            sessionId = m._private.mediaSession.getClientSessionIdAndRecordAction(m._private.cons.MEDIA_EVENT_NAME.PAUSE)
            data = {
                mediaEventName: m._private.cons.MEDIA_EVENT_NAME.PAUSE,
                timestampInISO8601: _adb_ISO8601_timestamp(),
                clientSessionId: sessionId
            }
            event = _adb_RequestEvent(m._private.cons.PUBLIC_API.MEDIA_API, data)
            m._private.dispatchEvent(event)
        end function,

        mediaTrackComplete: function() as void
            _adb_logDebug("API: mediaTrackComplete()")
            sessionId = m._private.mediaSession.getClientSessionIdAndRecordAction(m._private.cons.MEDIA_EVENT_NAME.COMPLETE)
            data = {
                mediaEventName: m._private.cons.MEDIA_EVENT_NAME.COMPLETE,
                timestampInISO8601: _adb_ISO8601_timestamp(),
                clientSessionId: sessionId
            }
            event = _adb_RequestEvent(m._private.cons.PUBLIC_API.MEDIA_API, data)
            m._private.dispatchEvent(event)
        end function,

        mediaTrackEvent: function(eventName as string, data = invalid as object, ContextData = invalid as object) as void
            _adb_logDebug("API: mediaTrackEvent()")
            xdmData = {
                xdm: {
                    "eventType": eventName,
                    "mediaCollection": {
                        ' TODO: update playhead
                        "playhead": 0,
                        ' "sessionID": sessionId
                    }
                }
            }

            ' if eventName = "media.play"
            ' else if eventName = "media.bufferStart"
            ' else if eventName = "media.x"
            ' end if

            m._sendMediaEvent(xdmData)
            ' sessionId = m._private.mediaSession.getClientSessionIdAndRecordAction(eventName)
            ' data = {
            '     mediaEventName: eventName,
            '     timestampInISO8601: _adb_ISO8601_timestamp(),
            '     clientSessionId: sessionId,
            '     params: {
            '         data: data,
            '         contextData: ContextData
            '     }
            ' }
            ' event = _adb_RequestEvent(m._private.cons.PUBLIC_API.MEDIA_API, data)
            ' m._private.dispatchEvent(event)
        end function,

        mediaTrackError: function(errorId as string, errorSource as string) as void
            _adb_logDebug("API: mediaTrackError()")
            sessionId = m._private.mediaSession.getClientSessionIdAndRecordAction(m._private.cons.MEDIA_EVENT_NAME.ERROR)
            data = {
                mediaEventName: m._private.cons.MEDIA_EVENT_NAME.ERROR,
                timestampInISO8601: _adb_ISO8601_timestamp(),
                clientSessionId: sessionId,
                params: {
                    errorId: errorId,
                    errorSource: errorSource
                }
            }
            event = _adb_RequestEvent(m._private.cons.PUBLIC_API.MEDIA_API, data)
            m._private.dispatchEvent(event)
        end function,

        mediaUpdatePlayhead: function(position as integer) as void
            _adb_logDebug("API: mediaUpdatePlayhead()")
            xdmData = {
                xdm: {
                    "eventType": "media.ping",
                    "mediaCollection": {
                        "playhead": position,
                        ' "sessionID": sessionId
                    }
                }
            }
            m._sendMediaEvent(xdmData)
            ' sessionId = m._private.mediaSession.getClientSessionIdAndRecordAction(m._private.cons.MEDIA_EVENT_NAME.PLAYHEAD_UPDATE)
            ' data = {
            '     mediaEventName: m._private.cons.MEDIA_EVENT_NAME.PLAYHEAD_UPDATE,
            '     timestampInISO8601: _adb_ISO8601_timestamp(),
            '     clientSessionId: sessionId,
            '     params: {
            '         playheadPosition: position
            '     }
            ' }
            ' event = _adb_RequestEvent(m._private.cons.PUBLIC_API.MEDIA_API, data)
            ' m._private.dispatchEvent(event)
        end function,

        ' -------------------------------------------------------------
        ' Media Roku SDK:
        ' mediaUpdateQoS()
        ' -------------------------------------------------------------
        mediaUpdateQoE: function(data as object) as void
            _adb_logDebug("API: mediaUpdatePlayhead()")
            sessionId = m._private.mediaSession.getClientSessionIdAndRecordAction(m._private.cons.MEDIA_EVENT_NAME.QOE_UPDATE)
            data = {
                mediaEventName: m._private.cons.MEDIA_EVENT_NAME.QOE_UPDATE,
                timestampInISO8601: _adb_ISO8601_timestamp(),
                clientSessionId: sessionId,
                params: {
                    data: data
                }
            }
            event = _adb_RequestEvent(m._private.cons.PUBLIC_API.MEDIA_API, data)
            m._private.dispatchEvent(event)
        end function

        ' ********************************
        ' Add private memebers below
        ' ********************************
        _private: {
            mediaSession: {
                _clientSessionId: invalid,
                _trackActionQueue: [],

                startNewSession: function() as string
                    m._clientSessionId = _adb_generate_UUID()
                    m._trackActionQueue = []
                    return m._clientSessionId
                end function,

                endSession: sub()
                    m._clientSessionId = invalid

                    print "We can start the validation process here:"
                    print "The session is ended, the media action series is -> "
                    for each action in m._trackActionQueue
                        print "media event: " + action
                    end for
                    m._trackActionQueue = []
                end sub,

                getClientSessionIdAndRecordAction: function(action as string) as string
                    m._trackActionQueue.Push(action)
                    return m._clientSessionId
                end function,

            },
            latestConfiguration: {},
            ' constants
            cons: _adb_InternalConstants(),
            ' for testing purpose
            lastEventId: invalid,
            ' dispatch events to the task node
            dispatchEvent: function(event as object) as void
                _adb_logDebug("dispatchEvent() - Dispatching event:(" + FormatJson(event) + ")")
                taskNode = _adb_retrieveTaskNode()
                if taskNode = invalid then
                    _adb_logDebug("dispatchEvent() - Cannot dispatch public API event after shutdown(). Please initialze the SDK using AdobeAEPSDKInit() API.")
                    return
                end if

                taskNode[m.cons.TASK.REQUEST_EVENT] = event
                m.lastEventId = event.uuid
            end function,

            ' API callbacks to be called later
            ' CallbackInfo = {cb: function, context: dynamic}
            cachedCallbackInfo: {},
        }

    }

    ' start the event loop on the SDK thread
    _adb_startTaskNode()

    _adb_logDebug("AdobeAEPSDKInit() - Successfully initialized the SDK")
    return GetGlobalAA()._adb_public_api
end function

' ****************************************************************************************************************************************
'                                              Below functions are for internal use only
' ****************************************************************************************************************************************

function _adb_defaultCallback(_context, _result) as void
end function

' ********** response event observer **********
function _adb_handleResponseEvent() as void
    sdk = GetGlobalAA()._adb_public_api
    if sdk <> invalid then
        ' remove timeout callbacks
        timeout_ms = sdk._private.cons.CALLBACK_TIMEOUT_MS
        current_time = _adb_timestampInMillis()
        for each key in sdk._private.cachedCallbackInfo
            cachedCallback = sdk._private.cachedCallbackInfo[key]

            if cachedCallback <> invalid and ((current_time - cachedCallback.timestampInMillis) > timeout_ms)
                sdk._private.cachedCallbackInfo.Delete(key)
            end if
        end for

        taskNode = _adb_retrieveTaskNode()
        if taskNode = invalid then
            return
        end if
        responseEvent = taskNode[sdk._private.cons.TASK.RESPONSE_EVENT]
        if responseEvent <> invalid
            uuid = responseEvent.parentId

            _adb_logDebug("_adb_handleResponseEvent() - Received response event:" + FormatJson(responseEvent) + " with uuid:" + FormatJson(uuid))
            if sdk._private.cachedCallbackInfo[uuid] <> invalid
                context = sdk._private.cachedCallbackInfo[uuid].context
                sdk._private.cachedCallbackInfo[uuid].cb(context, responseEvent.data)
                sdk._private.cachedCallbackInfo.Delete(uuid)
            else
                _adb_logDebug("_adb_handleResponseEvent() - Not handling response event, callback not passed with the request event.")
            end if
        else
            _adb_logError("_adb_handleResponseEvent() - Failed to handle response event, response event is invalid")
        end if
    else
        _adb_logError("_adb_handleResponseEvent() - Failed to handle response event, SDK instance is invalid")
    end if
end function
' *********************************************

