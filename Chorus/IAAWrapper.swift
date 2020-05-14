//
//  IAAWrapper.swift
//  Duplicat
//
//  Created by Chris Rivers on 14/06/2016.
//  Copyright © 2016 Lofionic. All rights reserved.
//

import UIKit
import AVFoundation
import ManiFramework

let kIAATransportStateChangedNotification:String = "IAATransportStateChangedNotification"

protocol IAAWrapperDelegate {
    func audioUnitDidConnect(_ iaaWrapper : IAAWrapper, audioUnit : AUAudioUnit?)
}

open class IAAWrapper: NSObject {

    var delegate : IAAWrapperDelegate?
    
    fileprivate let kSampleRate = 44100.0
    
    fileprivate var avEngine : AVAudioEngine
    fileprivate var effectNode : AVAudioUnit?
    
    fileprivate var graphStarted : Bool
    fileprivate var isConnected  : Bool
    fileprivate var isForeground : Bool
    
    fileprivate var isAudiobusSession : Bool
    fileprivate var isAudiobusConnected : Bool
    
    fileprivate var streamFormat : AudioStreamBasicDescription
    
    fileprivate(set) open var isPlaying : Bool
    fileprivate(set) open var isRecording : Bool
    
    fileprivate var callbackInfo : UnsafeMutablePointer<HostCallbackInfo>?
    
    fileprivate var hostIcon : UIImage?
    
    fileprivate var audioBusController : ABAudiobusController?
    fileprivate var audioBusfilterPort : ABFilterPort?
    
    internal func getAudioUnit() -> AudioUnit {
        return self.effectNode!.audioUnit
    }

    override init() {

        avEngine = AVAudioEngine()
        
        graphStarted    = false
        isConnected     = false
        isForeground    = false
        
        isAudiobusConnected = false
        isAudiobusSession = false
        
        callbackInfo = nil
        
        isPlaying = false
        isRecording = false
        
        streamFormat = AudioStreamBasicDescription()
        
        super.init()
        let appState = UIApplication.shared.applicationState
        isForeground = (appState != UIApplicationState.background)
        
        NotificationCenter.default.addObserver(self,
                                                         selector: #selector(appHasGoneInBackground),
                                                         name: NSNotification.Name.UIApplicationDidEnterBackground,
                                                         object: nil)
        
        NotificationCenter.default.addObserver(self,
                                                         selector: #selector(appHasGoneForeground),
                                                         name: NSNotification.Name.UIApplicationWillEnterForeground,
                                                         object: nil)
        
        NotificationCenter.default.addObserver(self,
                                                         selector: #selector(cleanup),
                                                         name: NSNotification.Name.UIApplicationWillTerminate,
                                                         object: nil)
        
        NotificationCenter.default.addObserver(forName: NSNotification.Name.AVAudioSessionMediaServicesWereReset, object: nil, queue: nil) { note in
            self.cleanup()
            self.createAndPublish()
        }
        
        //TODO: Listen for AVAudioSessionMediaServicesWereResetNotification
        //        //If media services get reset republish output node
        //        [[NSNotificationCenter defaultCenter] addObserverForName:AVAudioSessionMediaServicesWereResetNotification object: nil queue: nil usingBlock: ^(NSNotification *note) {
        //
        //            //Throw away entire engine and rebuild like starting the app from scratch
        //            [self cleanup];
        //            [self createAndPublish];
        //            }];
    }
    
    func createAndPublish() {
        connectAudioUnit()
        addAudioUnitPropertyListeners()
        publishOutputAudioUnit()
        publishAudiobus()
    }
    
    fileprivate func connectAudioUnit() {
        
        // Register the AU process
        var localComponentDescription = AudioComponentDescription()
        localComponentDescription.componentType = kIAAComponentType
        localComponentDescription.componentSubType = fourCharCodeFrom(kIAAComponentSubtype)
        localComponentDescription.componentManufacturer = fourCharCodeFrom(kIAAComponentManufacturer)
        localComponentDescription.componentFlags = 0
        localComponentDescription.componentFlagsMask = 0
        AUAudioUnit.registerSubclass(Mani.self, as: localComponentDescription, name: "Local Chorus", version: UInt32.max);
        
        var effectComponentDescription = AudioComponentDescription()
        effectComponentDescription.componentType = kIAAComponentType
        effectComponentDescription.componentSubType = fourCharCodeFrom(kIAAComponentSubtype)
        effectComponentDescription.componentManufacturer = fourCharCodeFrom(kIAAComponentManufacturer)
        AVAudioUnit.instantiate(with: effectComponentDescription, options: []) { avAudioUnit, error in
        
            // Assert that the avAudioUnit has been created succesfully
            if let avAudioUnit = avAudioUnit {
                
                self.effectNode = avAudioUnit
                
                // Connect the nodes
                self.avEngine.attach(avAudioUnit)
                
                var maxFrames : UInt32 = 4096;
                self.CheckError(AudioUnitSetProperty(avAudioUnit.audioUnit,
                    kAudioUnitProperty_MaximumFramesPerSlice,
                    kAudioUnitScope_Global,
                    0,
                    &maxFrames,
                    UInt32(MemoryLayout<UInt32>.size)),
                                desc: "Setting AU max frames");
                
                self.avEngine.connect(avAudioUnit, to: self.avEngine.mainMixerNode, format: nil)
                self.avEngine.connect(self.avEngine.mainMixerNode, to: self.avEngine.outputNode, format: nil)
                self.audioUnitDidConnect()
            }
        }
    }
    
    fileprivate func audioUnitDidConnect() {
        if let delegate = self.delegate {
            delegate.audioUnitDidConnect(self, audioUnit: self.effectNode?.auAudioUnit)
        }
        
        checkStartStopGraph()
    }
    
    fileprivate func addAudioUnitPropertyListeners() {
        
        var s : UnsafeMutableRawPointer;

        s = Unmanaged.passUnretained(self).toOpaque()
        
        let inputNode = self.avEngine.inputNode 
        CheckError(AudioUnitAddPropertyListener(inputNode.audioUnit!,
            kAudioUnitProperty_IsInterAppConnected,
            AudioUnitPropertyChangeDispatcher,
            s), desc: "Adding IsInterAppConnected property listener");
        CheckError(AudioUnitAddPropertyListener(inputNode.audioUnit!,
            kAudioOutputUnitProperty_HostTransportState,
            AudioUnitPropertyChangeDispatcher,
            s), desc: "Adding HostTransportState property listener");

        NSLog("Listeners Added")
    }
    
    let AudioUnitPropertyChangeDispatcher : @convention(c) (UnsafeMutableRawPointer, OpaquePointer, UInt32, UInt32, UInt32) -> Void = {
        (inRefCon, inUnit, inID, inScope, inElement) in
        
        NSLog("[AudioUnitPropertyChangeDispatcher]");
 
        let SELF = (Unmanaged<IAAWrapper>.fromOpaque(inRefCon)).takeUnretainedValue()

        SELF.audioUnitPropertyChangedListener(inRefCon, inUnit: inUnit, inPropID: inID, inScope: inScope, inElement: inElement)
    }

    func audioUnitPropertyChangedListener(_ inObject: UnsafeMutableRawPointer, inUnit:AudioUnit, inPropID: AudioUnitPropertyID, inScope: AudioUnitScope, inElement: AudioUnitElement) {
        if (inPropID == kAudioUnitProperty_IsInterAppConnected) {
            checkIsHostConnected()
            postUpdateStateNotification()
        } else if (inPropID == kAudioOutputUnitProperty_HostTransportState) {
            updateStateFromTransportCallBack()
            postUpdateStateNotification()
        }
    }
    
    fileprivate func publishOutputAudioUnit() {
        let inputNode = avEngine.inputNode
        if let audioUnit = inputNode.audioUnit {
            var desc = AudioComponentDescription(componentType: OSType(kIAAComponentType), componentSubType: fourCharCodeFrom(kIAAComponentSubtype), componentManufacturer: fourCharCodeFrom(kIAAComponentManufacturer), componentFlags: 0, componentFlagsMask: 0);
            CheckError(
                AudioOutputUnitPublish(&desc, "Lofionic Mani" as CFString, 1, audioUnit),
                desc: "Publishing IAA Component");
             NSLog("IAA Published")
        }
    
       
    }
    
    fileprivate func publishAudiobus() {
        // Create the audiodus controller
        self.audioBusController = ABAudiobusController(apiKey: kAudiobusKey)
        self.audioBusController?.stateIODelegate = self
        self.audioBusController?.connectionPanelPosition = ABConnectionPanelPositionLeft
        
        // Create the audiobus filter port
        let desc = AudioComponentDescription(componentType: OSType(kIAAComponentType), componentSubType: fourCharCodeFrom(kIAAComponentSubtype), componentManufacturer: fourCharCodeFrom(kIAAComponentManufacturer), componentFlags: 0, componentFlagsMask: 0);
        self.audioBusfilterPort = ABFilterPort.init(name: "Main Port", title: "Main Port", audioComponentDescription: desc, audioUnit: avEngine.outputNode.audioUnit)
        audioBusController?.addFilterPort(self.audioBusfilterPort)
        
        NotificationCenter.default.addObserver(self, selector: #selector(audiobusConnectionsChangedNotifactionReceived), name: NSNotification.Name.ABConnectionsChanged, object: audioBusController)
    }
    
    @objc
    fileprivate func audiobusConnectionsChangedNotifactionReceived(_ note : Notification) {
        // Audiobus connection state has changed, we need to stop or start the graph.
        if let audiobus = audioBusController {
            isAudiobusConnected = audiobus.audiobusConnected
            isAudiobusSession = audiobus.memberOfActiveAudiobusSession
        }
        checkStartStopGraph()
    }
    
    fileprivate func checkStartStopGraph() {
        NSLog("[checkStartStopGraph]");

        
        // If IAA & AudioBus is disconnected...
        if isConnected || isAudiobusConnected {
            if (!graphStarted) {
                setAudioSessionActive()
                startGraph()
            }
        } else {
            if (!isForeground && !isAudiobusSession) {
                if (graphStarted) {
                    stopGraph()
                    setAudioSessionInactive()
                }
            }
        }
    }
    
    fileprivate func startGraph() {
        NSLog("[startGraph]")
        
        // Connect the effect unit to the engine's input node
        let inputNode = self.avEngine.inputNode
        if let effectNode = self.effectNode {
            self.avEngine.disconnectNodeInput(effectNode)
            self.avEngine.connect(inputNode, to: effectNode, format: effectNode.inputFormat(forBus: 0))
        }

        do {
            try avEngine.start()
            graphStarted = true
            NSLog("Engine started")
        } catch {
            NSLog("Failed to start engine")
        }
    }
    
    fileprivate func stopGraph() {
        NSLog("[stopGraph]")
        
        // Disconnect the input
        let inputNode = self.avEngine.inputNode
        self.avEngine.disconnectNodeOutput(inputNode)
        
        avEngine.pause()
        graphStarted = false
    }
    
    fileprivate func setAudioSessionActive() {
        NSLog("[setAudioSessionActive]")
        let session = AVAudioSession.sharedInstance()
        
        do {
            try session.setPreferredSampleRate(kSampleRate);
            try session.setCategory(AVAudioSessionCategoryPlayAndRecord, with: AVAudioSessionCategoryOptions.mixWithOthers)
            try session.setActive(true)
        } catch {
            NSLog("ERROR: setting audio session active")
        }
        
    }
    
    fileprivate func setAudioSessionInactive() {
        NSLog("[setAudioSessionInactive]")
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setActive(false)
        } catch {
            NSLog("ERROR: setting audio session inactive")
        }
    }
    
    @objc
    fileprivate func appHasGoneInBackground() {
        isForeground = false;
        checkStartStopGraph()
    }
    
    @objc
    fileprivate func appHasGoneForeground() {
        isForeground = true;
        checkIsHostConnected()
        checkStartStopGraph()
        updateStateFromTransportCallBack()
    }
    
    @objc
    fileprivate func cleanup() {
        stopGraph()
        avEngine.stop()
        setAudioSessionInactive()
    }
    
    fileprivate func checkIsHostConnected() {
        
        NSLog("[checkIsHostConnected]")
        let inputNode = self.avEngine.inputNode
        var data = UInt32(0)
        var dataSize = UInt32(MemoryLayout<UInt32>.size)
        CheckError(AudioUnitGetProperty(inputNode.audioUnit!, kAudioUnitProperty_IsInterAppConnected, kAudioUnitScope_Global, 0, &data, &dataSize), desc: "AudioUnitGetProperty_IsInterAppConnected")
        let connect = (data > 0 ? true : false)
        if (connect != isConnected) {
            isConnected = connect
            if (isConnected) {
                NSLog("host did connect")
                checkStartStopGraph()
                getHostCallBackInfo()
                getAudioUnitIcon()
            } else {
                NSLog("host did disconnect")
                checkStartStopGraph()
            }
        }
    }
    
    fileprivate func postUpdateStateNotification() {
        NSLog("[postUpdateStateNotification]")
        DispatchQueue.main.async(execute: {
            NotificationCenter.default.post(name: Notification.Name(rawValue: kIAATransportStateChangedNotification), object: self)
            if (self.isPlaying) {
                NSLog("IsPlaying")
            }
            
            if (self.isRecording) {
                NSLog("IsRecording")
            }
        })
    }
    
    fileprivate func getHostCallBackInfo() {
        NSLog("[getHostCallBackInfo]")
        if (isConnected) {
            if (callbackInfo != nil) {
                free(callbackInfo)
            }
        
        let inputNode = self.avEngine.inputNode
            var datasize = UInt32(MemoryLayout<HostCallbackInfo>.size)
            callbackInfo = UnsafeMutablePointer<HostCallbackInfo>.allocate(capacity: MemoryLayout<HostCallbackInfo>.size)
            let result = AudioUnitGetProperty(inputNode.audioUnit!, kAudioUnitProperty_HostCallbacks, kAudioUnitScope_Global, 0, callbackInfo!, &datasize)
            if (result != noErr) {
                free(callbackInfo)
                callbackInfo = nil
            }
        }
    }
    
    // This is called when the app enters the foreground, or when the host transport state is changed.
    fileprivate func updateStateFromTransportCallBack() {
        // Transport state will only be updated when the app is connected and in the foreground.
        if (isConnected && isForeground) {
            if (callbackInfo == nil) {
                getHostCallBackInfo()
            }
            
            if (callbackInfo != nil) {
                let hostPlaying = UnsafeMutablePointer<DarwinBoolean>.allocate(capacity: 1)
                hostPlaying[0] = isPlaying ? true : false
                
                let hostRecording = UnsafeMutablePointer<DarwinBoolean>.allocate(capacity: 1)

                hostRecording[0] = isRecording ? true : false
                
                var outCurrentSampleInTimeLine = Float64(0)
                
                let hostUserData = callbackInfo?.pointee.hostUserData
                let transportStateProc = callbackInfo?.pointee.transportStateProc2
                if let transportStateProcUnwrapped = transportStateProc {
                    let result = transportStateProcUnwrapped(hostUserData,
                                                             hostPlaying,
                                                             hostRecording,
                                                             nil,
                                                             &outCurrentSampleInTimeLine,
                                                             nil,
                                                             nil,
                                                             nil)
                    
                    if (result == noErr) {
                        isPlaying = hostPlaying.pointee.boolValue
                        isRecording = hostRecording.pointee.boolValue
                    }
                }
            }
        }
    }
    
    fileprivate func sendStateToRemoteHost(_ event: AudioUnitRemoteControlEvent) {
        let inputNode = self.avEngine.inputNode
        var controlEvent = event.rawValue
        let dataSize = UInt32(MemoryLayout<AudioUnitRemoteControlEvent>.size)
        CheckError(AudioUnitSetProperty(inputNode.audioUnit!, kAudioOutputUnitProperty_RemoteControlToHost, kAudioUnitScope_Global, 0, &controlEvent, dataSize), desc: "Sending remote control event")
    }
    
    fileprivate func getAudioUnitIcon() {
        NSLog("[getAudioUnitIcon]")
        let inputNode = self.avEngine.inputNode
        hostIcon = AudioOutputUnitGetHostIcon(inputNode.audioUnit!, 100);
    }
    
    fileprivate func fourCharCodeFrom(_ string : String) -> FourCharCode
    {
        assert(string.characters.count == 4, "String length must be 4")
        var result : FourCharCode = 0
        for char in string.utf16 {
            result = (result << 8) + FourCharCode(char)
        }
        return result
    }
    
    fileprivate func CheckError(_ error:OSStatus, desc:String) {
        if error == 0 {return}
        
        print (desc);
        switch(error) {
        // AudioToolbox
        case kAUGraphErr_NodeNotFound:
            print("Error:kAUGraphErr_NodeNotFound")
            
        case kAUGraphErr_OutputNodeErr:
            print( "Error:kAUGraphErr_OutputNodeErr")
            
        case kAUGraphErr_InvalidConnection:
            print("Error:kAUGraphErr_InvalidConnection")
            
        case kAUGraphErr_CannotDoInCurrentContext:
            print( "Error:kAUGraphErr_CannotDoInCurrentContext")
            
        case kAUGraphErr_InvalidAudioUnit:
            print( "Error:kAUGraphErr_InvalidAudioUnit")
            
            //    case kMIDIInvalidClient :
            //        print( "kMIDIInvalidClient ")
            //
            //
            //    case kMIDIInvalidPort :
            //        print( "kMIDIInvalidPort ")
            //
            //
            //    case kMIDIWrongEndpointType :
            //        print( "kMIDIWrongEndpointType")
            //
            //
            //    case kMIDINoConnection :
            //        print( "kMIDINoConnection ")
            //
            //
            //    case kMIDIUnknownEndpoint :
            //        print( "kMIDIUnknownEndpoint ")
            //
            //
            //    case kMIDIUnknownProperty :
            //        print( "kMIDIUnknownProperty ")
            //
            //
            //    case kMIDIWrongPropertyType :
            //        print( "kMIDIWrongPropertyType ")
            //
            //
            //    case kMIDINoCurrentSetup :
            //        print( "kMIDINoCurrentSetup ")
            //
            //
            //    case kMIDIMessageSendErr :
            //        print( "kMIDIMessageSendErr ")
            //
            //
            //    case kMIDIServerStartErr :
            //        print( "kMIDIServerStartErr ")
            //
            //
            //    case kMIDISetupFormatErr :
            //        print( "kMIDISetupFormatErr ")
            //
            //
            //    case kMIDIWrongThread :
            //        print( "kMIDIWrongThread ")
            //
            //
            //    case kMIDIObjectNotFound :
            //        print( "kMIDIObjectNotFound ")
            //
            //
            //    case kMIDIIDNotUnique :
            //        print( "kMIDIIDNotUnique ")
            
            
        case kAudioToolboxErr_InvalidSequenceType :
            print( " kAudioToolboxErr_InvalidSequenceType")
            
        case kAudioToolboxErr_TrackIndexError :
            print( " kAudioToolboxErr_TrackIndexError")
            
        case kAudioToolboxErr_TrackNotFound :
            print( " kAudioToolboxErr_TrackNotFound")
            
        case kAudioToolboxErr_EndOfTrack :
            print( " kAudioToolboxErr_EndOfTrack")
            
        case kAudioToolboxErr_StartOfTrack :
            print( " kAudioToolboxErr_StartOfTrack")
            
        case kAudioToolboxErr_IllegalTrackDestination	:
            print( " kAudioToolboxErr_IllegalTrackDestination")
            
        case kAudioToolboxErr_NoSequence 		:
            print( " kAudioToolboxErr_NoSequence")
            
        case kAudioToolboxErr_InvalidEventType		:
            print( " kAudioToolboxErr_InvalidEventType")
            
        case kAudioToolboxErr_InvalidPlayerState	:
            print( " kAudioToolboxErr_InvalidPlayerState")
            
        case kAudioUnitErr_InvalidProperty		:
            print( " kAudioUnitErr_InvalidProperty")
            
        case kAudioUnitErr_InvalidParameter		:
            print( " kAudioUnitErr_InvalidParameter")
            
        case kAudioUnitErr_InvalidElement		:
            print( " kAudioUnitErr_InvalidElement")
            
        case kAudioUnitErr_NoConnection			:
            print( " kAudioUnitErr_NoConnection")
            
        case kAudioUnitErr_FailedInitialization		:
            print( " kAudioUnitErr_FailedInitialization")
            
        case kAudioUnitErr_TooManyFramesToProcess	:
            print( " kAudioUnitErr_TooManyFramesToProcess")
            
        case kAudioUnitErr_InvalidFile			:
            print( " kAudioUnitErr_InvalidFile")
            
        case kAudioUnitErr_FormatNotSupported		:
            print( " kAudioUnitErr_FormatNotSupported")
            
        case kAudioUnitErr_Uninitialized		:
            print( " kAudioUnitErr_Uninitialized")
            
        case kAudioUnitErr_InvalidScope			:
            print( " kAudioUnitErr_InvalidScope")
            
        case kAudioUnitErr_PropertyNotWritable		:
            print( " kAudioUnitErr_PropertyNotWritable")
            
        case kAudioUnitErr_InvalidPropertyValue		:
            print( " kAudioUnitErr_InvalidPropertyValue")
            
        case kAudioUnitErr_PropertyNotInUse		:
            print( " kAudioUnitErr_PropertyNotInUse")
            
        case kAudioUnitErr_Initialized			:
            print( " kAudioUnitErr_Initialized")
            
        case kAudioUnitErr_InvalidOfflineRender		:
            print( " kAudioUnitErr_InvalidOfflineRender")
            
        case kAudioUnitErr_Unauthorized			:
            print( " kAudioUnitErr_Unauthorized")
            
        case kAudioComponentErr_DuplicateDescription :
            print( " kAudioComponentErr_DuplicateDescription ")
        
        case kAudioComponentErr_NotPermitted :
            print ( " kAudioComponentErr_NotPermitted ")
            
        default:
            print("huh?")
        }
    }
    
}

extension IAAWrapper : IAATransportViewDelegate {
    
    public func isHostPlaying() -> Bool {
        return isPlaying
    }
    
    public func isHostConnected() -> Bool {
        return isConnected && !isAudiobusConnected
    }
    
    public func isHostRecording() -> Bool {
        return isRecording
    }
    
    public func getHostIcon() -> UIImage? {
        return hostIcon
    }
    
    public func goToHost() {
        let inputNode = self.avEngine.inputNode
        var instrumentUrl = CFURLCreateWithString(nil, nil, nil)
        var dataSize = UInt32(MemoryLayout<CFURL>.size)
        CheckError(AudioUnitGetProperty(inputNode.audioUnit!, kAudioUnitProperty_PeerURL, kAudioUnitScope_Global, 0, &instrumentUrl, &dataSize), desc: "Getting PeerURL Property")
        UIApplication.shared.openURL(instrumentUrl as! URL)
}
    
    public func canPlay() -> Bool {
        return isConnected
    }
    
    public func canRewind() -> Bool {
        return isConnected
    }
    
    public func canRecord() -> Bool {
        return self.avEngine.inputNode != nil && !isPlaying
    }

    public func hostRewind() {
        sendStateToRemoteHost(.rewind)
        NotificationCenter.default.post(name: Notification.Name(rawValue: kIAATransportStateChangedNotification), object: self)
    }
    
    public func hostPlay() {
        sendStateToRemoteHost(.togglePlayPause)
        NotificationCenter.default.post(name: Notification.Name(rawValue: kIAATransportStateChangedNotification), object: self)
    }
    
    public func hostRecord() {
        sendStateToRemoteHost(.toggleRecord)
        NotificationCenter.default.post(name: Notification.Name(rawValue: kIAATransportStateChangedNotification), object: self)
    }
}

extension IAAWrapper : ABAudiobusControllerStateIODelegate {
    
    public func audiobusStateDictionaryForCurrentState() -> [AnyHashable: Any]! {

        if let effectNode = self.effectNode {
            // Fetch the parameter IDs from the AudioUnit
            // These IDs will be used to get & set parameters
            var size: UInt32 = 0
            var propertyBool = DarwinBoolean(true)
            AudioUnitGetPropertyInfo(
                effectNode.audioUnit,
                kAudioUnitProperty_ParameterList,
                kAudioUnitScope_Global,
                0,
                &size,
                &propertyBool)
            let numParams = Int(size)/MemoryLayout<AudioUnitParameterID>.size
            var paramIDs = [AudioUnitParameterID](repeating: 0, count: Int(numParams))
            AudioUnitGetProperty(
                effectNode.audioUnit,
                kAudioUnitProperty_ParameterList,
                kAudioUnitScope_Global,
                0,
                &paramIDs,
                &size)
        
            let stateDictionary = NSMutableDictionary.init(capacity: paramIDs.count)
            for paramID in paramIDs {
                
                var value = AudioUnitParameterValue(0)
                AudioUnitGetParameter(effectNode.audioUnit, paramID, kAudioUnitScope_Global, 0, &value)
                
                stateDictionary.setValue(value, forKey: String(paramID))
            }
        
        return (stateDictionary as NSDictionary) as! [AnyHashable: Any]
            
        } else {
            return NSDictionary() as! [AnyHashable: AnyObject]
        }
    }
    
    public func loadState(fromAudiobusStateDictionary dictionary: [AnyHashable : Any]!, responseMessage outResponseMessage: AutoreleasingUnsafeMutablePointer<NSString?>!) {
    
        if let effectNode = self.effectNode {
            let stateDictionary = dictionary as NSDictionary
            for thisKey in stateDictionary.allKeys {
                let paramId = UInt32(thisKey as! String)
                
                if let paramId = paramId {
                    let value = stateDictionary.object(forKey: thisKey) as! AudioUnitParameterValue
                    AudioUnitSetParameter(effectNode.audioUnit, paramId, kAudioUnitScope_Global, 0, value, 0)
                }
            }
        }
    }
}

// Some useful code for fetching parameter IDs from an audio unit.
//    func connectViewWithAU(audioUnit: AudioUnit?) {
//
//        // Fetch the parameter IDs from the AudioUnit
//        // These IDs will be used to get & set parameters
//        var size: UInt32 = 0
//        var propertyBool = DarwinBoolean(true)
//        AudioUnitGetPropertyInfo(
//            audioUnit!,
//            kAudioUnitProperty_ParameterList,
//            kAudioUnitScope_Global,
//            0,
//            &size,
//            &propertyBool)
//        let numParams = Int(size)/sizeof(AudioUnitParameterID)
//        paramIDs = [AudioUnitParameterID](count: Int(numParams), repeatedValue: 0)
//        AudioUnitGetProperty(
//            audioUnit!,
//            kAudioUnitProperty_ParameterList,
//            kAudioUnitScope_Global,
//            0,
//            &paramIDs,
//            &size)
//
//        updateTapeSpeedControl();
//        updateMixControl();
//        updateFeedbackControl();
//        updateTapeEffectControl();
//
//        updateDelayButtons();
//    }
