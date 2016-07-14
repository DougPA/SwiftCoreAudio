//
//  main.swift
//  CH07_AUGraphSineWave
//
//  Created by Douglas Adams on 7/13/16.
//

import AudioToolbox

//--------------------------------------------------------------------------------------------------
// MARK: Struct definition

struct SineWavePlayer
{
    var outputUnit: AudioUnit?                              // pointer to a ComponentInstanceRecord
    var startingPhase: Double = 0.0                         // starting waveform phase
}

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
func SineWaveRenderProc(userData: UnsafeMutablePointer<Void>,
                        actionFlags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
                        timeStamp: UnsafePointer<AudioTimeStamp>,
                        busNumber: UInt32,
                        numberOfFrames: UInt32,
                        bufferList: UnsafeMutablePointer<AudioBufferList>?) -> OSStatus
{

    let kSampleRate = 44100.0
    let kSineFrequency = 880.0
    
    let player = UnsafeMutablePointer<SineWavePlayer>(userData)
    
    // get the starting phase of the waveform
    var phase: Double = player.pointee.startingPhase
    
    // calculate the length of one cycle (one wavelength)
    let cycleLength: Double  = kSampleRate / kSineFrequency
    
    for frame in 0..<Int(numberOfFrames)
    {
        if let bufferList = bufferList {
            
            // get a reference to each channels data (2 channels assumed)
            let channels = UnsafeMutablePointer<Float32>(bufferList.pointee.mBuffers.mData)!
            let left = UnsafeMutableBufferPointer<Float32>(start: channels, count: Int(numberOfFrames))
            let right = UnsafeMutableBufferPointer<Float32>(start: channels.advanced(by: Int(numberOfFrames)), count: Int(numberOfFrames))
            
            // populate each channel with the same data
            left[frame] = Float32(sin (2 * M_PI * (phase / cycleLength)))
            right[frame] = left[frame]
            
            // increment the current frame number
            phase += 1.0
            
            // the phase repeats going from zero through the cycleLength over and over
            if phase > cycleLength { phase -= cycleLength }
        }
    }

    // save the current phase as the starting phase for the next iteration
    player.pointee.startingPhase = phase
    
    return noErr
}
//
//
//
func CreateAndConnectOutputUnit (player: UnsafeMutablePointer<SineWavePlayer>) {
    
    //  10.6 and later: generate description that will match out output device (speakers)
    var outputCd = AudioComponentDescription()
    outputCd.componentType = kAudioUnitType_Output
    outputCd.componentSubType = kAudioUnitSubType_DefaultOutput
    outputCd.componentManufacturer = kAudioUnitManufacturer_Apple
    
    guard let component = AudioComponentFindNext(nil, &outputCd) else {
        Swift.print("can't get output unit")
        exit(-1)
    }

    Utility.check(error: AudioComponentInstanceNew(component,
                                                   &player.pointee.outputUnit),
                  operation: "Couldn't open component for outputUnit")
    
    // register render callback
    var renderCallback = AURenderCallbackStruct()
    renderCallback.inputProc = SineWaveRenderProc
    renderCallback.inputProcRefCon = UnsafeMutablePointer<Void>(player)
    Utility.check(error: AudioUnitSetProperty(player.pointee.outputUnit!,
                                    kAudioUnitProperty_SetRenderCallback,
                                    kAudioUnitScope_Input,
                                    0,
                                    &renderCallback,
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

// cleanup
AudioOutputUnitStop(player.outputUnit!)
AudioUnitUninitialize(player.outputUnit!)
AudioComponentInstanceDispose(player.outputUnit!)

exit(0)
