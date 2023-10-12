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

' *********************************** MODULE: Media ***************************************
function _adb_isMediaModule(module as object) as boolean
    return (module <> invalid and module.type = "com.adobe.module.media")
end function

function _adb_MediaModule(configurationModule as object, identityModule as object) as object
    if _adb_isConfigurationModule(configurationModule) = false then
        _adb_logError("_adb_MediaModule() - configurationModule is not valid.")
        return invalid
    end if

    if _adb_isIdentityModule(identityModule) = false then
        _adb_logError("_adb_EdgeModule() - identityModule is not valid.")
        return invalid
    end if

    module = _adb_AdobeObject("com.adobe.module.media")
    module.Append({
        _configurationModule: configurationModule,
        _identityModule: identityModule,
        _edgeRequestWorker: _adb_EdgeRequestWorker(),
        _CONSTANTS: _adb_InternalConstants(),
        _sessionManager: _adb_MediaSessionManager(),

        ' {
        '     clientSessionId: "xx-xxxx-xxxx",
        '     timestampInISO8601: "2019-01-01T00:00:00.000Z",
        '     param: { xdm: {} }
        ' }
        processEvent: sub(requestId as string, eventData as object, timestampInMillis as longinteger)
            ' m._edgeRequestWorker.queue(requestId, xdmData, timestampInMillis)
            mediaEventType = eventData.param.xdm.eventType
            clientSessionId = eventData.clientSessionId
            timestampInISO8601 = eventData.timestampInISO8601

            if mediaEventType = "media.sessionStart"
                m._sessionStart(requestId, clientSessionId, eventData.param, timestampInISO8601, timestampInMillis)
                ' else if mediaEventType = "media.sessionend"
                '     m._sessionEnd(requestId, clientSessionId, timestampInISO8601, timestampInMillis)
            else
                m._actionInSession(requestId, eventData, timestampInISO8601, timestampInMillis)
                ' _adb_logWarning("handleEvent() - event is invalid: " + FormatJson(event))
            end if
        end sub,

        _sessionStart: sub(requestId as string, clientSessionId as string, xdmData as object, timestampInISO8601 as string, timestampInMillis as longinteger)
            m._sessionManager.createNewSession(clientSessionId)
            meta = {}
            'https://edge.adobedc.net/ee/va/v1/sessionStart?configId=xx&requestId=xx
            path = "/ee/va/v1/sessionStart"

            xdmData.xdm["_id"] = _adb_generate_UUID()
            xdmData.xdm["timestamp"] = timestampInISO8601
            'session start => (clientSessionId = requestId)
            m._edgeRequestWorker.queue(clientSessionId, xdmData, timestampInMillis, meta, path)
            m._kickRequestQueue()
        end sub,

        _actionInSession: sub(requestId as string, eventData as object, timestampInISO8601 as string, timestampInMillis as longinteger)
            mediaEventType = eventData.param.xdm.eventType
            clientSessionId = eventData.clientSessionId

            sessionId = m._sessionManager.getSessionId(clientSessionId)
            location = m._sessionManager.getLocation(clientSessionId)

            if _adb_isEmptyOrInvalidString(sessionId)
                m._kickRequestQueue()
                return
            else
                meta = {}
                path = _adb_EdgePathForAction(mediaEventType, location)
                if _adb_isEmptyOrInvalidString(path)
                    _adb_logError("_actionInSession() - mediaEventName is invalid: " + mediaEventType)
                    return
                end if
                xdmData = eventData.param
                xdmData.xdm["_id"] = _adb_generate_UUID()
                xdmData.xdm["timestamp"] = timestampInISO8601
                xdmData.xdm["mediaCollection"]["sessionID"] = sessionId

                m._edgeRequestWorker.queue(requestId, xdmData, timestampInMillis, meta, path)
                m._kickRequestQueue()
            end if
        end sub,

        _kickRequestQueue: sub()
            responses = m.processQueuedRequests()
            for each edgeResponse in responses
                if _adb_isEdgeResponse(edgeResponse) then
                    ' udpate session id if needed
                    responseJson = edgeResponse.getresponsestring()
                    responseObj = ParseJson(responseJson)
                    requestId = responseObj.requestId
                    sessionId = ""
                    location = ""
                    for each handle in responseObj.handle
                        if handle.type = "media-analytics:new-session"
                            sessionId = handle.payload[0]["sessionId"]
                        else if handle.type = "locationHint:result"
                            for each payload in handle.payload
                                if payload["scope"] = "EdgeNetwork"
                                    location = payload["hint"]
                                end if
                            end for
                        end if
                    end for
                    if _adb_isEmptyOrInvalidString(sessionId) or _adb_isEmptyOrInvalidString(location)
                        _adb_logError("_kickRequestQueue() - sessionId and/or location is invalid.")
                        return
                    else
                        m._sessionManager.updateSessionIdAndGetQueuedData(requestId, sessionId, location)
                    end if
                end if
            end for
        end sub,

        _getEdgeConfig: function() as object
            configId = m._configurationModule.getConfigId()
            if _adb_isEmptyOrInvalidString(configId)
                return invalid
            end if
            ecid = m._identityModule.getECID()
            if _adb_isEmptyOrInvalidString(ecid)
                return invalid
            end if
            return {
                configId: configId,
                ecid: ecid,
                edgeDomain: m._configurationModule.getEdgeDomain()
            }
        end function,

        processQueuedRequests: function() as dynamic
            responseEvents = []

            if not m._edgeRequestWorker.hasQueuedEvent()
                ''' no requests to process
                return responseEvents
            end if

            edgeConfig = m._getEdgeConfig()
            if edgeConfig = invalid
                _adb_logVerbose("processQueuedRequests() - Cannot send network request, invalid configuration.")
                return responseEvents
            end if

            responses = m._edgeRequestWorker.processRequests(edgeConfig.configId, edgeConfig.ecid, edgeConfig.edgeDomain)

            return responses
        end function,

        dump: function() as object
            return {
                requestQueue: m._edgeRequestWorker._queue
            }
        end function
    })
    return module
end function

function _adb_EdgePathForAction(eventName as string, location as string) as dynamic
    if eventName = "media.play"
        return "/ee/" + location + "/va/v1/play"
        ' else if eventName = m._CONSTANTS.MEDIA_EVENT_NAME.PAUSE
        '     return "/ee/va/v1/pauseStart"
        ' else if eventName = m._CONSTANTS.MEDIA_EVENT_NAME.COMPLETE
        '     return "/ee/va/v1/sessionComplete"
        ' else if eventName = m._CONSTANTS.MEDIA_EVENT_NAME.ERROR
        '     return "/ee/va/v1/error"
    else if eventName = "media.ping"
        return "/ee/" + location + "/va/v1/ping"
    else if eventName = "media.sessionEnd"
        return "/ee/" + location + "/va/v1/sessionEnd"
        ' else if eventName = m._CONSTANTS.MEDIA_EVENT_NAME.QOE_UPDATE
        '     return "/ee/va/v1/qoeupdate"
    else if eventName = "media.bufferStart"
        return "/ee/" + location + "/va/v1/bufferStart"
        ' else if eventName = m._CONSTANTS.MEDIA_EVENT_NAME.BUFFER_COMPLETE
        '     return "/ee/va/v1/buffercomplete"
        ' else if eventName = m._CONSTANTS.MEDIA_EVENT_NAME.SEEK_START
        '     return "/ee/va/v1/seekStart"
        ' else if eventName = m._CONSTANTS.MEDIA_EVENT_NAME.SEEK_COMPLETE
        '     return "/ee/va/v1/seekComplete"
        ' else if eventName = m._CONSTANTS.MEDIA_EVENT_NAME.ADBREAK_START
        '     return "/ee/va/v1/adBreakStart"
        ' else if eventName = m._CONSTANTS.MEDIA_EVENT_NAME.ADBREAK_COMPLETE
        '     return "/ee/va/v1/adBreakComplete"
        ' else if eventName = m._CONSTANTS.MEDIA_EVENT_NAME.AD_START
        '     return "/ee/va/v1/adStart"
        ' else if eventName = m._CONSTANTS.MEDIA_EVENT_NAME.AD_SKIP
        '     return "/ee/va/v1/adSkip"
        ' else if eventName = m._CONSTANTS.MEDIA_EVENT_NAME.AD_COMPLETE
        '     return "/ee/va/v1/adComplete"
        ' else if eventName = m._CONSTANTS.MEDIA_EVENT_NAME.CHAPTER_START
        '     return "/ee/va/v1/chapterStart"
        ' else if eventName = m._CONSTANTS.MEDIA_EVENT_NAME.CHAPTER_SKIP
        '     return "/ee/va/v1/chapterSkip"
        ' else if eventName = m._CONSTANTS.MEDIA_EVENT_NAME.CHAPTER_COMPLETE
        '     return "/ee/va/v1/chapterComplete"
        ' else if eventName = m._CONSTANTS.MEDIA_EVENT_NAME.BITRATE_CHANGE
        '     return "/ee/va/v1/bitrateChange"
        ' else if eventName = m._CONSTANTS.MEDIA_EVENT_NAME.STATE_START
        '     return "/ee/va/v1/stateStart"
        ' else if eventName = m._CONSTANTS.MEDIA_EVENT_NAME.STATE_END
        '     return "/ee/va/v1/stateEnd"
    else
        return invalid
    end if
end function

function _adb_MediaSessionManager() as object
    return {
        _map: {},

        createNewSession: sub(clientSessionId as string)
            if _adb_isEmptyOrInvalidString(clientSessionId)
                _adb_logError("createNewSession() - clientSessionId is invalid.")
                return
            end if
            if m._map.DoesExist(clientSessionId)
                _adb_logError("createNewSession() - clientSessionId already exists.")
                return
            end if
            m._map[clientSessionId] = {
                sessionId: invalid,
                location: invalid,
                queue: []
            }
        end sub,

        updateSessionIdAndGetQueuedData: function(clientSessionId as string, sessionId as string, location as string) as object
            if m._map.DoesExist(clientSessionId)
                m._map[clientSessionId].sessionId = sessionId
                m._map[clientSessionId].location = location
                return m._map[clientSessionId].queue
            end if
            _adb_logError("updateSessionId() - clientSessionId is invalid.")
            return []
        end function,

        getLocation: function(clientSessionId as string) as string
            session = m._map.Lookup(clientSessionId)
            if session = invalid
                return ""
            end if
            return session.location
        end function,

        getSessionId: function(clientSessionId as string) as string
            session = m._map.Lookup(clientSessionId)
            if session = invalid
                return ""
            end if
            return session.sessionId
        end function,

        queueMediaData: sub(clientSessionId as string, requestId as string, data as object, timestampInMillis as longinteger)
            if m._map.DoesExist(clientSessionId)
                m._map[clientSessionId].queue.Push({
                    requestId: requestId,
                    data: data,
                    timestampInMillis: timestampInMillis
                })
                return
            end if
            _adb_logError("queueMediaData() - clientSessionId is invalid.")
        end sub,

        deleteSession: sub(clientSessionId as string)
            m._map.Delete(clientSessionId)
        end sub,
    }
end function