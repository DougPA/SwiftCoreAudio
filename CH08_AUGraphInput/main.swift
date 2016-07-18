//
//  main.swift
//  CH08_AUGraphInput
//
//  Created by Douglas Adams on 7/16/16.
//

import AudioToolbox
import ApplicationServices

let part2 = false

//--------------------------------------------------------------------------------------------------
// MARK: Struct definition

struct MyAUGraphPlayer
{
    var streamFormat = AudioStreamBasicDescription()
    
    var graph: AUGraph?
    var inputUnit: AudioUnit?
    var outputUnit: AudioUnit?
    var speechUnit: AudioUnit?

    var inputBuffer: AudioBufferList?
    var ringBuffer: CARingBuffer?

    var firstInputSampleTime: Float64 = 0
    var firstOutputSampleTime: Float64 = 0
    var inToOutSampleTimeOffset: Float64 = 0

}

//OSStatus InputRenderProc(void *inRefCon,
//                         AudioUnitRenderActionFlags *ioActionFlags,
//                         const AudioTimeStamp *inTimeStamp,
//                         UInt32 inBusNumber,
//                         UInt32 inNumberFrames,
//                         AudioBufferList * ioData);
//OSStatus GraphRenderProc(void *inRefCon,
//                         AudioUnitRenderActionFlags *ioActionFlags,
//                         const AudioTimeStamp *inTimeStamp,
//                         UInt32 inBusNumber,
//                         UInt32 inNumberFrames,
//                         AudioBufferList * ioData);
//void CreateInputUnit (MyAUGraphPlayer *player);
//void CreateMyAUGraph(MyAUGraphPlayer *player);

//--------------------------------------------------------------------------------------------------
// MARK: Supporting methods

func InputRenderProc(userData: UnsafeMutablePointer<Void>,
                     actionFlags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
                     timeStamp: UnsafePointer<AudioTimeStamp>,
                     busNumber: UInt32,
                     numberOfFrames: UInt32,
                     bufferList: UnsafeMutablePointer<AudioBufferList>?) -> OSStatus {
    
    //	printf ("InputRenderProc!\n");
    let player = UnsafeMutablePointer<MyAUGraphPlayer>(userData)
    
    // have we ever logged input timing? (for offset calculation)
    if (player.pointee.firstInputSampleTime < 0.0) {
        
        player.pointee.firstInputSampleTime = timeStamp.pointee.mSampleTime
        
        if player.pointee.firstOutputSampleTime > -1.0 && player.pointee.inToOutSampleTimeOffset < 0.0 {
            
            player.pointee.inToOutSampleTimeOffset = player.pointee.firstInputSampleTime - player.pointee.firstOutputSampleTime
        }
    }
    
    // render into our buffer
    var inputProcErr: OSStatus = noErr
    inputProcErr = AudioUnitRender(player.pointee.inputUnit!,
                                   actionFlags,
                                   timeStamp,
                                   busNumber,
                                   numberOfFrames,
                                   player.pointee.inputBuffer)
    // copy from our buffer to ring buffer
    if inputProcErr == noErr {
        inputProcErr = player.pointee.ringBuffer.pointee.Store(player.pointee.inputBuffer,
                                                 numberOfFrames,
                                                 timeStamp.pointee.mSampleTime)
        
        //		printf ("stored %d frames at time %f\n", inNumberFrames, inTimeStamp->mSampleTime);
    }
    //	else {
    //		printf ("input renderErr: %d\n", inputProcErr);
    //	}
    //
    
    return inputProcErr
}


func GraphRenderProc(userData: UnsafeMutablePointer<Void>,
                     actionFlags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
                     timeStamp: UnsafePointer<AudioTimeStamp>,
                     busNumber: UInt32,
                     numberOfFrames: UInt32,
                     bufferList: UnsafeMutablePointer<AudioBufferList>?) -> OSStatus {
    
    //	printf ("GraphRenderProc! need %d frames for time %f \n", inNumberFrames, inTimeStamp->mSampleTime);
    
    let player = UnsafeMutablePointer<MyAUGraphPlayer>(userData)
    
    // have we ever logged output timing? (for offset calculation)
    if (player.pointee.firstOutputSampleTime < 0.0) {
        
        player.pointee.firstOutputSampleTime = inTimeStamp->mSampleTime;
        
        if ((player.pointee.firstInputSampleTime > -1.0) &&
            
            (player.pointee.inToOutSampleTimeOffset < 0.0)) {
            
            player.pointee.inToOutSampleTimeOffset = player.pointee.firstInputSampleTime - player.pointee.firstOutputSampleTime
        }
    }
    
    // copy samples out of ring buffer
    var outputProcErr: OSStatus = noErr;
    
    // new CARingBuffer doesn't take bool 4th arg
    outputProcErr = player.pointee.ringBuffer.Fetch(bufferList,
                                              numberOfFrames,
                                              timeStamp.pointee.mSampleTime + player.pointee.inToOutSampleTimeOffset)
    
    //	printf ("fetched %d frames at time %f\n", inNumberFrames, inTimeStamp->mSampleTime);
    return outputProcErr;
}

//
//
//
func CreateInputUnit (player: UnsafeMutablePointer<MyAUGraphPlayer>) {
    
    // generate description that will match audio HAL
    var inputCd = AudioComponentDescription()
    inputCd.componentType = kAudioUnitType_Output
    inputCd.componentSubType = kAudioUnitSubType_HALOutput
    inputCd.componentManufacturer = kAudioUnitManufacturer_Apple
    
    var comp: AudioComponent?  = AudioComponentFindNext(nil, &inputCd)
    if comp == nil {
        Swift.print("can't get output unit")
        exit(-1)
    }
    
    Utility.check(error: AudioComponentInstanceNew(comp, &player.pointee.inputUnit),
                  operation: "Couldn't open component for inputUnit");
    
    // enable/io
    var disableFlag: UInt32  = 0
    var enableFlag: UInt32  = 1
    var outputBus: AudioUnitScope = 0
    var inputBus: AudioUnitScope = 1
    Utility.check(error: AudioUnitSetProperty(player.pointee.inputUnit,
                                     kAudioOutputUnitProperty_EnableIO,
                                     kAudioUnitScope_Input,
                                     inputBus,
                                     &enableFlag,
                                     sizeof(enableFlag)),
                  operation: "Couldn't enable input on I/O unit");
    
    Utility.check(error: AudioUnitSetProperty(player.pointee.inputUnit,
                                     kAudioOutputUnitProperty_EnableIO,
                                     kAudioUnitScope_Output,
                                     outputBus,
                                     &disableFlag,	// well crap, have to disable
                                        sizeof(enableFlag)),
                  operation: "Couldn't disable output on I/O unit");
    
    // set device (osx only... iphone has only one device)
    var defaultDevice: AudioDeviceID  = kAudioObjectUnknown
    var propertySize: UInt32 = sizeof(defaultDevice)
    
    // AudioHardwareGetProperty() is deprecated
    //	CheckError (AudioHardwareGetProperty(kAudioHardwarePropertyDefaultInputDevice,
    //										 &propertySize,
    //										 &defaultDevice),
    //				"Couldn't get default input device");
    
    // AudioObjectProperty stuff new in 10.6, replaces AudioHardwareGetProperty() call
    // TODO: need to update ch08 to explain, use this call. need CoreAudio.framework
    var defaultDeviceProperty = AudioObjectPropertyAddress()
    defaultDeviceProperty.mSelector = kAudioHardwarePropertyDefaultInputDevice
    defaultDeviceProperty.mScope = kAudioObjectPropertyScopeGlobal
    defaultDeviceProperty.mElement = kAudioObjectPropertyElementMaster
    
    Utility.check(error: AudioObjectGetPropertyData(kAudioObjectSystemObject,
                                                    &defaultDeviceProperty,
                                                    0,
                                                    nil,
                                                    &propertySize,
                                                    &defaultDevice),
                  operation: "Couldn't get default input device")
    
    // set this defaultDevice as the input's property
    // kAudioUnitErr_InvalidPropertyValue if output is enabled on inputUnit
    Utility.check(error: AudioUnitSetProperty(player.pointee.inputUnit,
                                              kAudioOutputUnitProperty_CurrentDevice,
                                              kAudioUnitScope_Global,
                                              outputBus,
                                              &defaultDevice,
                                              sizeof(defaultDevice)),
                  operation: "Couldn't set default device on I/O unit")
    
    // use the stream format coming out of the AUHAL (should be de-interleaved)
    propertySize = sizeof(AudioStreamBasicDescription)
    Utility.check(error: AudioUnitGetProperty(player.pointee.inputUnit,
                                              kAudioUnitProperty_StreamFormat,
                                              kAudioUnitScope_Output,
                                              inputBus,
                                              &player.pointee.streamFormat,
                                              &propertySize),
                  operation: "Couldn't get ASBD from input unit")
    
    // 9/6/10 - check the input device's stream format
    var deviceFormat = AudioStreamBasicDescription()
    Utility.check(error: AudioUnitGetProperty(player.pointee.inputUnit,
                                              kAudioUnitProperty_StreamFormat,
                                              kAudioUnitScope_Input,
                                              inputBus,
                                              &deviceFormat,
                                              &propertySize),
                  operation: "Couldn't get ASBD from input unit")
    
    Swift.print("Device rate \(deviceFormat.mSampleRate), graph rate \(player.pointee.streamFormat.mSampleRate)\n")

    player.pointee.streamFormat.mSampleRate = deviceFormat.mSampleRate
    
    propertySize = sizeof(AudioStreamBasicDescription)
    Utility.check(error: AudioUnitSetProperty(player.pointee.inputUnit,
                                              kAudioUnitProperty_StreamFormat,
                                              kAudioUnitScope_Output,
                                              inputBus,
                                              &player.pointee.streamFormat,
                                              propertySize),
                  operation: "Couldn't set ASBD on input unit")
    
    /* allocate some buffers to hold samples between input and output callbacks
     (this part largely copied from CAPlayThrough) */
    //Get the size of the IO buffer(s)
    var bufferSizeFrames: UInt32 = 0
    propertySize = sizeof(UInt32)
    Utility.check(error: AudioUnitGetProperty(player.pointee.inputUnit,
                                              kAudioDevicePropertyBufferFrameSize,
                                              kAudioUnitScope_Global,
                                              0,
                                              &bufferSizeFrames,
                                              &propertySize),
                  operation: "Couldn't get buffer frame size from input unit")
    
    var bufferSizeBytes: UInt32 = bufferSizeFrames * sizeof(Float32)
    
    if (player.pointee.streamFormat.mFormatFlags & kAudioFormatFlagIsNonInterleaved) {
        
        Swift.print("format is non-interleaved\n")
        
        // allocate an AudioBufferList plus enough space for array of AudioBuffers
        var propsize: UInt32 = offsetof(AudioBufferList, mBuffers[0]) + (sizeof(AudioBuffer) * player.pointee.streamFormat.mChannelsPerFrame)
        
        //malloc buffer lists
        player.pointee.inputBuffer = UnsafeMutablePointer<AudioBufferList>(malloc(propsize))
        player.pointee.inputBuffer->mNumberBuffers = player.pointee.streamFormat.mChannelsPerFrame
        
        //pre-malloc buffers for AudioBufferLists
        for i in 0..<player.pointee.inputBuffer.mNumberBuffers {
            
            player.pointee.inputBuffer->mBuffers[i].mNumberChannels = 1
            player.pointee.inputBuffer->mBuffers[i].mDataByteSize = bufferSizeBytes
            player.pointee.inputBuffer->mBuffers[i].mData = malloc(bufferSizeBytes)
        }
    } else {
        printf ("format is interleaved\n");
        // allocate an AudioBufferList plus enough space for array of AudioBuffers
        var propsize: UInt32 = offsetof(AudioBufferList, mBuffers[0]) + (sizeof(AudioBuffer) * 1)
        
        //malloc buffer lists
        player.pointee.inputBuffer = UnsafeMutablePointer<AudioBufferList>(malloc(propsize))
        player.pointee.inputBuffer.mNumberBuffers = 1
        
        //pre-malloc buffers for AudioBufferLists
        player.pointee.inputBuffer->mBuffers[0].mNumberChannels = player.pointee.streamFormat.mChannelsPerFrame
        player.pointee.inputBuffer->mBuffers[0].mDataByteSize = bufferSizeBytes
        player.pointee.inputBuffer->mBuffers[0].mData = malloc(bufferSizeBytes)
    }
    
    //Alloc ring buffer that will hold data between the two audio devices
    player.pointee.ringBuffer = CARingBuffer()
    player.pointee.ringBuffer->Allocate(player.pointee.streamFormat.mChannelsPerFrame, player.pointee.streamFormat.mBytesPerFrame, bufferSizeFrames * 3)
    
    // set render proc to supply samples from input unit
    var callbackStruct = AURenderCallbackStruct()
    callbackStruct.inputProc = InputRenderProc
    callbackStruct.inputProcRefCon = player
    
    Utility.check(error: AudioUnitSetProperty(player.pointee.inputUnit,
                                              kAudioOutputUnitProperty_SetInputCallback,
                                              kAudioUnitScope_Global,
                                              0,
                                              &callbackStruct,
                                              sizeof(callbackStruct)),
                  operation: "Couldn't set input callback")
    
    Utility.check(error: AudioUnitInitialize(player.pointee.inputUnit),
                  operation: "Couldn't initialize input unit")
    
    player.pointee.firstInputSampleTime = -1
    player.pointee.inToOutSampleTimeOffset = -1
    
    Swift.print("Bottom of CreateInputUnit()\n")
}


func CreateMyAUGraph(player: UnsafeMutablePointer<MyAUGraphPlayer>) {
    
    // create a new AUGraph
    Utility.check(error: NewAUGraph(&player.pointee.graph),
                  operation: "NewAUGraph failed");
    
    // generate description that will match default output
    //	ComponentDescription outputcd = {0};
    //	outputcd.componentType = kAudioUnitType_Output;
    //	outputcd.componentSubType = kAudioUnitSubType_DefaultOutput;
    //	outputcd.componentManufacturer = kAudioUnitManufacturer_Apple;
    //
    //	Component comp = FindNextComponent(NULL, &outputcd);
    //	if (comp == NULL) {
    //		printf ("can't get output unit"); exit (-1);
    //	}
    
    var outputCd = AudioComponentDescription()
    outputCd.componentType = kAudioUnitType_Output
    outputCd.componentSubType = kAudioUnitSubType_DefaultOutput
    outputCd.componentManufacturer = kAudioUnitManufacturer_Apple
    
    var comp: AudioComponent? = AudioComponentFindNext(NULL, &outputCd)
    if comp == nil {
        Swift.print("can't get output unit")
        exit(-1)
    }
    
    // adds a node with above description to the graph
    var outputNode = AUNode()
    Utility.check(error: AUGraphAddNode(player.pointee.graph,
                                        &outputCd,
                                        &outputNode),
                  operation: "AUGraphAddNode[kAudioUnitSubType_DefaultOutput] failed");
    
    if part2 {
        
        // add a mixer to the graph,
        var mixerCd = AudioComponentDescription()
        mixerCd.componentType = kAudioUnitType_Mixer
        mixerCd.componentSubType = kAudioUnitSubType_StereoMixer // doesn't work: kAudioUnitSubType_MatrixMixer
        mixerCd.componentManufacturer = kAudioUnitManufacturer_Apple
        
        var mixerNode = AUNode()
        Utility.check(error: AUGraphAddNode(player.pointee.graph,
                                            &mixerCd,
                                            &mixerNode),
                      operation: "AUGraphAddNode[kAudioUnitSubType_StereoMixer] failed")
        
        // adds a node with above description to the graph
        var speechcd = AudioComponentDescription()
        speechcd.componentType = kAudioUnitType_Generator
        speechcd.componentSubType = kAudioUnitSubType_SpeechSynthesis
        speechcd.componentManufacturer = kAudioUnitManufacturer_Apple
        
        var speechNode = AUNode()
        Utility.check(error: AUGraphAddNode(player.pointee.graph,
                                            &speechcd,
                                            &speechNode),
                      operation: "AUGraphAddNode[kAudioUnitSubType_AudioFilePlayer] failed");
        
        // opening the graph opens all contained audio units but does not allocate any resources yet
        Utility.check(error: AUGraphOpen(player.pointee.graph),
                      operation: "AUGraphOpen failed")
        
        // get the reference to the AudioUnit objects for the various nodes
        Utility.check(error: AUGraphNodeInfo(player.pointee.graph,
                                             outputNode,
                                             nil,
                                             &player.pointee.outputUnit),
                      operation: "AUGraphNodeInfo failed")
        
        Utility.check(error: AUGraphNodeInfo(player.pointee.graph,
                                             speechNode,
                                             nil,
                                             &player.pointee.speechUnit),
                      operation: "AUGraphNodeInfo failed")
        
        var mixerUnit = AudioUnit()
        Utility.check(error: AUGraphNodeInfo(player.pointee.graph,
                                             mixerNode,
                                             nil,
                                             &mixerUnit),
                      operation: "AUGraphNodeInfo failed")
        
        // set ASBDs here
        var propertySize: UInt32  = sizeof(AudioStreamBasicDescription)
        Utility.check(error: AudioUnitSetProperty(player.pointee.outputUnit,
                                                  kAudioUnitProperty_StreamFormat,
                                                  kAudioUnitScope_Input,
                                                  0,
                                                  &player.pointee.streamFormat,
                                                  propertySize),
                      operation: "Couldn't set stream format on output unit")
        
        // problem: badComponentInstance (-2147450879)
        Utility.check(error: AudioUnitSetProperty(mixerUnit,
                                                  kAudioUnitProperty_StreamFormat,
                                                  kAudioUnitScope_Input,
                                                  0,
                                                  &player.pointee.streamFormat,
                                                  propertySize),
                      operation: "Couldn't set stream format on mixer unit bus 0")
        
        Utility.check(error: AudioUnitSetProperty(mixerUnit,
                                                  kAudioUnitProperty_StreamFormat,
                                                  kAudioUnitScope_Input,
                                                  1,
                                                  &player.pointee.streamFormat,
                                                  propertySize),
                      operation: "Couldn't set stream format on mixer unit bus 1")
        
        // connections
        // mixer output scope / bus 0 to outputUnit input scope / bus 0
        // mixer input scope / bus 0 to render callback (from ringbuffer, which in turn is from inputUnit)
        // mixer input scope / bus 1 to speech unit output scope / bus 0
        
        Utility.check(error: AUGraphConnectNodeInput(player.pointee.graph,
                                                     mixerNode,
                                                     0,
                                                     outputNode,
                                                     0),
                      operation: "Couldn't connect mixer output(0) to outputNode (0)")
        
        Utility.check(error: AUGraphConnectNodeInput(player.pointee.graph,
                                                     speechNode,
                                                     0,
                                                     mixerNode,
                                                     1),
                      operation: "Couldn't connect speech synth unit output (0) to mixer input (1)")
        
        var callbackStruct = AURenderCallbackStruct()
        callbackStruct.inputProc = GraphRenderProc
        callbackStruct.inputProcRefCon = player
        Utility.check(error: AudioUnitSetProperty(mixerUnit,
                                                  kAudioUnitProperty_SetRenderCallback,
                                                  kAudioUnitScope_Global,
                                                  0,
                                                  &callbackStruct,
                                                  sizeof(callbackStruct)),
                      operation: "Couldn't set render callback on mixer unit")
        
    } else {
        
        // opening the graph opens all contained audio units but does not allocate any resources yet
        Utility.check(error: AUGraphOpen(player.pointee.graph),
                      operation: "AUGraphOpen failed")
        
        // get the reference to the AudioUnit object for the output graph node
        Utility.check(error: AUGraphNodeInfo(player.pointee.graph,
                                             outputNode,
                                             nil,
                                             &player.pointee.outputUnit),
                      operation: "AUGraphNodeInfo failed")
        
        // set the stream format on the output unit's input scope
        var propertySize: UInt32 = sizeof(AudioStreamBasicDescription)
        Utility.check(error: AudioUnitSetProperty(player.pointee.outputUnit,
                                                  kAudioUnitProperty_StreamFormat,
                                                  kAudioUnitScope_Input,
                                                  0,
                                                  &player.pointee.streamFormat,
                                                  propertySize),
                      operation: "Couldn't set stream format on output unit")
        
        var callbackStruct = AURenderCallbackStruct()
        callbackStruct.inputProc = GraphRenderProc
        callbackStruct.inputProcRefCon = player
        
        Utility.check(error: AudioUnitSetProperty(player.pointee.outputUnit,
                                                  kAudioUnitProperty_SetRenderCallback,
                                                  kAudioUnitScope_Global,
                                                  0,
                                                  &callbackStruct,
                                                  sizeof(callbackStruct)),
                      operation: "Couldn't set render callback on output unit")
    }

// now initialize the graph (causes resources to be allocated)
Utility.check(error: AUGraphInitialize(player.pointee.graph),
              operation: "AUGraphInitialize failed");

player.pointee.firstOutputSampleTime = -1

Swift.print("Bottom of CreateSimpleAUGraph()\n")
}

if part2 {
    func PrepareSpeechAU(player: UnsafeMutablePointer<MyAUGraphPlayer>) {
        var chan: SpeechChannel
        
        var propsize: UInt32 = sizeof(SpeechChannel)
        Utility.check(error: AudioUnitGetProperty(player.pointee.speechUnit,
                                                  kAudioUnitProperty_SpeechChannel,
                                                  kAudioUnitScope_Global,
                                                  0,
                                                  &chan,
                                                  &propsize),
                      operation: "AudioFileGetProperty[kAudioUnitProperty_SpeechChannel] failed")
        
        let myString = CFStringCreateWithCString(kCFAllocatorDefault, "Please purchase as many copies of our\n Core Audio book as you possibly can", CFStringBuiltInEncodings.UTF8.rawValue)!
        SpeakCFString(chan, myString, nil)
    }
}

//--------------------------------------------------------------------------------------------------
// MARK: Main

var player = MyAUGraphPlayer()

// create the input unit
CreateInputUnit(player: &player)

// build a graph with output unit
CreateMyAUGraph(player: &player);

if part2 {
    // configure the speech synthesizer
    PrepareSpeechAU(player: &player);
    
}

// start playing
Utility.check(error: AudioOutputUnitStart(player.inputUnit),
              operation: "AudioOutputUnitStart failed")
Utility.check(error: AUGraphStart(player.graph),
              operation: "AUGraphStart failed");

// and wait
Swift.print("Capturing, press <return> to stop:\n")
getchar()

// cleanup
AUGraphStop (player.graph)
AUGraphUninitialize (player.graph)
AUGraphClose(player.graph)

