//
//  main.swift
//  CH07_AUGraphSpeechSynthesis
//
//  Created by Douglas Adams on 7/14/16.
//

import AudioToolbox

//--------------------------------------------------------------------------------------------------
// MARK: Struct definition

struct MyAUGraphPlayer
{
//    var streamFormat = AudioStreamBasicDescription()            // ASBD to use in the graph
    var graph: AUGraph?                                         // Opaque pointer to the AUGraph
    var speechAU: AudioUnit?                                    // pointer to a ComponentInstanceRecord
}

//--------------------------------------------------------------------------------------------------
// MARK: Supporting methods

//
//
//
func CreateMyAUGraph(player: UnsafeMutablePointer<MyAUGraphPlayer>) {
    
    // create a new AUGraph
    Utility.check(error: NewAUGraph(&player.pointee.graph),
                  operation: "NewAUGraph failed")
    
    // generate description that will match our output device (speakers)
    var outputCd = AudioComponentDescription()
    outputCd.componentType = kAudioUnitType_Output
    outputCd.componentSubType = kAudioUnitSubType_DefaultOutput
    outputCd.componentManufacturer = kAudioUnitManufacturer_Apple
    
    // adds a node with above description to the graph
    var outputNode = AUNode()
    Utility.check(error: AUGraphAddNode(player.pointee.graph!,
                                        &outputCd,
                                        &outputNode),
                  operation: "AUGraphAddNode[kAudioUnitSubType_DefaultOutput] failed")
    
    // generate description that will match a generator AU of type: speech synthesizer
    var speechCd = AudioComponentDescription()
    speechCd.componentType = kAudioUnitType_Generator
    speechCd.componentSubType = kAudioUnitSubType_SpeechSynthesis
    speechCd.componentManufacturer = kAudioUnitManufacturer_Apple
    
    // adds a node with above description to the graph
    var speechNode = AUNode()
    Utility.check(error: AUGraphAddNode(player.pointee.graph!,
                                        &speechCd,
                                        &speechNode),
                  operation: "AUGraphAddNode[kAudioUnitSubType_SpeechSynthesis] failed")
    
    // opening the graph opens all contained audio units but does not allocate any resources yet
    Utility.check(error: AUGraphOpen(player.pointee.graph!),
                  operation: "AUGraphOpen failed")
    
    // get the reference to the AudioUnit object for the speech synthesis graph node
    Utility.check(error: AUGraphNodeInfo(player.pointee.graph!,
                                         speechNode,
                                         nil,
                                         &player.pointee.speechAU),
                  operation: "AUGraphNodeInfo failed")
    
    // debug - get the asbd
//    var propSize = UInt32(sizeof(AudioStreamBasicDescription.self))
//    Utility.check(error: AudioUnitGetProperty(player.pointee.speechAU!,
//                                    kAudioUnitProperty_StreamFormat,
//                                    kAudioUnitScope_Output,
//                                    0,
//                                    &player.pointee.streamFormat,
//                                    &propSize),
//                  operation: "Couldn't get ASBD")
    
    //
    // FUN! re-route the speech thru a reverb effect before sending to speakers
    //
    // generate description that will match out reverb effect
    var reverbCd = AudioComponentDescription()
    reverbCd.componentType = kAudioUnitType_Effect
    reverbCd.componentSubType = kAudioUnitSubType_MatrixReverb
    reverbCd.componentManufacturer = kAudioUnitManufacturer_Apple
    
    // adds a node with above description to the graph
    var reverbNode = AUNode()
    Utility.check(error: AUGraphAddNode(player.pointee.graph!,
                                        &reverbCd,
                                        &reverbNode),
                  operation: "AUGraphAddNode[kAudioUnitSubType_MatrixReverb] failed")
    
    // connect the output source of the reverb AU to the input source of the output node
    Utility.check(error: AUGraphConnectNodeInput(player.pointee.graph!,
                                                 reverbNode,
                                                 0,
                                                 outputNode,
                                                 0),
                  operation: "AUGraphConnectNodeInput, reverb->output to output->input")

    // connect the output source of the speech synthesizer AU to the input source of the reverb node
    Utility.check(error: AUGraphConnectNodeInput(player.pointee.graph!,
                                                 speechNode,
                                                 0,
                                                 reverbNode,
                                                 0),
                  operation: "AUGraphConnectNodeInput, synth->output to reverb->input")
    
    // get the reference to the AudioUnit object for the reverb graph node
    var reverbUnit: AudioUnit? = nil
    Utility.check(error: AUGraphNodeInfo(player.pointee.graph!,
                                         reverbNode,
                                         nil,
                                         &reverbUnit),
                  operation: "AUGraphNodeInfo failed")
    
    /*
     enum {
     reverbRoomType_SmallRoom		= 0,
     reverbRoomType_MediumRoom		= 1,
     reverbRoomType_LargeRoom		= 2,
     reverbRoomType_MediumHall		= 3,
     reverbRoomType_LargeHall		= 4,
     reverbRoomType_Plate			= 5,
     reverbRoomType_MediumChamber	= 6,
     reverbRoomType_LargeChamber	= 7,
     reverbRoomType_Cathedral		= 8,
     reverbRoomType_LargeRoom2		= 9,
     reverbRoomType_MediumHall2		= 10,
     reverbRoomType_MediumHall3		= 11,
     reverbRoomType_LargeHall2		= 12
     }
     
     */
    
    // now initialize the graph (causes resources to be allocated)
    Utility.check(error: AUGraphInitialize(player.pointee.graph!),
                  operation: "AUGraphInitialize failed")
    
    
    // set the reverb preset for room size
    var roomType: AUReverbRoomType = .reverbRoomType_SmallRoom
//    var roomType: AUReverbRoomType = .reverbRoomType_MediumRoom
//    var roomType: AUReverbRoomType = .reverbRoomType_LargeHall
//    var roomType: AUReverbRoomType = .reverbRoomType_Cathedral
    
    Utility.check(error: AudioUnitSetProperty(reverbUnit!,
                                              kAudioUnitProperty_ReverbRoomType,
                                              kAudioUnitScope_Global,
                                              0,
                                              &roomType,
                                              UInt32(sizeof(UInt32.self))),
                  operation: "AudioUnitSetProperty[kAudioUnitProperty_ReverbRoomType] failed")

    CAShow(UnsafeMutablePointer<Void>(player.pointee.graph!))
}
//
//
//
func PrepareSpeechAU(player: UnsafeMutablePointer<MyAUGraphPlayer>) {
    var chan: SpeechChannel? = nil
    
    var propsize = UInt32(sizeof(SpeechChannel.self))
    Utility.check(error: AudioUnitGetProperty(player.pointee.speechAU!,
                                              kAudioUnitProperty_SpeechChannel,
                                              kAudioUnitScope_Global,
                                              0,
                                              &chan,
                                              &propsize),
                  operation: "AudioUnitGetProperty[kAudioUnitProperty_SpeechChannel] failed")
    
    
    let myString = CFStringCreateWithCString(kCFAllocatorDefault, "hello world", CFStringBuiltInEncodings.UTF8.rawValue)!
    SpeakCFString(chan!, myString, nil)
}

//--------------------------------------------------------------------------------------------------
// MARK: Main

var player = MyAUGraphPlayer()

// build a basic speech->speakers graph
CreateMyAUGraph(player: &player)

// configure the speech synthesizer
PrepareSpeechAU(player: &player)

// start playing
Utility.check(error: AUGraphStart(player.graph!),
              operation: "AUGraphStart failed")

// sleep a while so the speech can play out
usleep(10 * 1000 * 1000)

// cleanup
AUGraphStop (player.graph!)
AUGraphUninitialize (player.graph!)
AUGraphClose(player.graph!)
DisposeAUGraph(player.graph!)

exit(0)

