//
//  main.swift
//  CH07_AUGraphSineWave
//
//  Created by Douglas Adams on 7/13/16.
//

import AudioToolbox

let sineFrequency = 880.0

//--------------------------------------------------------------------------------------------------
// MARK: Global Struct

struct SineWavePlayer
{
    var outputUnit: AudioUnit?
    var startingFrameCount: Double = 0.0
}

//OSStatus SineWaveRenderProc(void *inRefCon,
//                            AudioUnitRenderActionFlags *ioActionFlags,
//                            const AudioTimeStamp *inTimeStamp,
//                            UInt32 inBusNumber,
//                            UInt32 inNumberFrames,
//                            AudioBufferList * ioData);
//void CreateAndConnectOutputUnit (MySineWavePlayer *player) ;

//--------------------------------------------------------------------------------------------------
// MARK: Supporting methods

//  AURenderCallback function
//
//      must have the following signature:
//          @convention(c) (UnsafeMutablePointer<Swift.Void>,                               // pointer to the SineWavePlayer struct
//                          UnsafeMutablePointer<AudioUnitRenderActionFlags>,               // pointer to the AudioUnitRenderActionFlags
//                          UnsafePointer<AudioTimeStamp>,                                  // pointer to an AudioTimeStamp
//                          UInt32,                                                         // input Bus Number
//                          UInt32,                                                         // number of frames required
//                          UnsafeMutablePointer<AudioBufferList>?) -> OSStatus             // pointer to the AudioBufferList
//
func SineWaveRenderProc(inRefCon: UnsafeMutablePointer<Void>,
                        ioActionFlags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
                        inTimeStamp: UnsafePointer<AudioTimeStamp>,
                        inBusNumber: UInt32,
                        inNumberFrames: UInt32,
                        ioData: UnsafeMutablePointer<AudioBufferList>?) -> OSStatus
{
    //	printf ("SineWaveRenderProc needs %ld frames at %f\n", inNumberFrames, CFAbsoluteTimeGetCurrent());
    
    let player = UnsafeMutablePointer<SineWavePlayer>(inRefCon)
    
    var j: Double = player.pointee.startingFrameCount
    //	double cycleLength = 44100. / 2200./*frequency*/;
    let cycleLength: Double  = 44100 / sineFrequency
    for frame in 0..<Int(inNumberFrames)
    {
        if let ioData = ioData {
            
            let channels = UnsafeMutablePointer<Float32>(ioData.pointee.mBuffers.mData)!
            
            let left = UnsafeMutableBufferPointer<Float32>(start: channels, count: Int(inNumberFrames))
            let right = UnsafeMutableBufferPointer<Float32>(start: channels.advanced(by: Int(inNumberFrames)), count: Int(inNumberFrames))
            
            // copy to right channel too
            left[frame] = Float32(sin (2 * M_PI * (j / cycleLength)))
            right[frame] = left[frame]
            
            j += 1.0
            if j > cycleLength { j -= cycleLength }
        }
    }
    
    player.pointee.startingFrameCount = j
    return noErr
}

func CreateAndConnectOutputUnit (player: UnsafeMutablePointer<SineWavePlayer>) {
    
    //  10.6 and later: generate description that will match out output device (speakers)
    var outputcd = AudioComponentDescription()
    outputcd.componentType = kAudioUnitType_Output
    outputcd.componentSubType = kAudioUnitSubType_DefaultOutput
    outputcd.componentManufacturer = kAudioUnitManufacturer_Apple
    
    guard let component = AudioComponentFindNext(nil, &outputcd) else {
        Swift.print("can't get output unit")
        exit(-1)
    }

    Utility.check(error: AudioComponentInstanceNew(component,
                                                   &player.pointee.outputUnit),
                  operation: "Couldn't open component for outputUnit")
    
    // register render callback
    var input = AURenderCallbackStruct()
    input.inputProc = SineWaveRenderProc
    input.inputProcRefCon = UnsafeMutablePointer<Void>(player)
    Utility.check(error: AudioUnitSetProperty(player.pointee.outputUnit!,
                                    kAudioUnitProperty_SetRenderCallback,
                                    kAudioUnitScope_Input,
                                    0,
                                    &input,
                                    UInt32(sizeof(AURenderCallbackStruct))),
                  operation: "AudioUnitSetProperty failed")
    
    // initialize unit
    Utility.check(error: AudioUnitInitialize(player.pointee.outputUnit!),
                  operation: "Couldn't initialize output unit")
    
}

//--------------------------------------------------------------------------------------------------
// MARK: Main

var player = SineWavePlayer()

// set up unit and callback
CreateAndConnectOutputUnit(player: &player)

// start playing
Utility.check(error: AudioOutputUnitStart(player.outputUnit!), operation: "Couldn't start output unit")

Swift.print("playing\n")

// play for 5 seconds
sleep(5)

AudioOutputUnitStop(player.outputUnit!)
AudioUnitUninitialize(player.outputUnit!)
AudioComponentInstanceDispose(player.outputUnit!)

exit(0)
