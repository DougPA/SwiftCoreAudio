//
//  main.swift
//  CH--_OpenALSineWave
//
//  Created by Douglas Adams on 7/26/16.
//


import AudioToolbox
import OpenAL

//--------------------------------------------------------------------------------------------------
// MARK: Constants

let streamPath = CFStringCreateWithCString(kCFAllocatorDefault,
                                           "/Library/Audio/Apple Loops/Apple/iLife Sound Effects/Jingles/Kickflip Long.caf",
                                           CFStringBuiltInEncodings.UTF8.rawValue)

let kBufferDuration: UInt32 = 1             // duration in seconds
let kBufferCount = 3                        // count of buffers
let kOrbitSpeed: Double = 1                 // speed in seconds
let kRunTime = 20.0                         // run time in seconds

let kSampleRate: Double = 44_100.0
let kSineFrequency: Double = 440.0


//--------------------------------------------------------------------------------------------------
// MARK: Struct definition

struct MyStreamPlayer {
    var dataFormat = AudioStreamBasicDescription()                      // stream AudioStreamBasicDescription
    var bufferSizeBytes: UInt32	= 0                                     // buffer size in bytes
    var fileLengthFrames: Int64 = 0                                     // file length in frames
    var totalFramesRead: Int64 = 0                                      // number of frames read
    var sources = [ALuint](repeating: 0, count: 1)                      // OpenAL source handles
    var extAudioFile: ExtAudioFileRef?                                  // reference to an ExtAudioFile
    
    var phase: Double = 0.0
}

//--------------------------------------------------------------------------------------------------
// MARK: Supporting methods

//
// calculate and set a new player position
//
func updateSourceLocation (player: UnsafeMutablePointer<MyStreamPlayer>) {
    
    let theta: Double  = fmod(CFAbsoluteTimeGetCurrent() * kOrbitSpeed, M_PI * 2)
    let x = ALfloat(3.0 * cos(theta))
    let y = ALfloat(0.5 * sin (theta))
    let z = ALfloat(1.0 * sin (theta))
    
    Swift.print("x = \(x), y = \(y), z = \(z)\n")
    
    alSource3f(player.pointee.sources[0], AL_POSITION, x, y, z)
}
//
//
//
//func setupSineWave() {
//
//    let kSampleRate = 44100.0
//    let kSineFrequency = 880.0
//    
//    let player = UnsafeMutablePointer<SineWavePlayer>(userData)
//    
//    // get the starting phase of the waveform
//    var phase: Double = player.pointee.phase
//    
//    // calculate the length of one cycle (one wavelength)
//    let cycleLength: Double  = kSampleRate / kSineFrequency
//    
//    for frame in 0..<Int(numberOfFrames)
//    {
//        // get a reference to each channels data (2 channels assumed)
//        let channels = UnsafeMutablePointer<Float32>(bufferList.pointee.mBuffers.mData)!
//        let left = UnsafeMutableBufferPointer<Float32>(start: channels, count: Int(numberOfFrames))
//        
//        // populate each channel with the same data
//        left[frame] = Float32(sin (2 * M_PI * (phase / cycleLength)))
//        
//        // increment the current frame number
//        phase += 1.0
//        
//        // the phase repeats going from zero through the cycleLength over and over
//        if phase > cycleLength { phase -= cycleLength }
//    }
//    
//    // save the current phase as the starting phase for the next iteration
//    player.pointee.phase = phase
//    
//}
//
// fill an OpenAL buffer with SineWave data
//
func fillALBuffer (player: UnsafeMutablePointer<MyStreamPlayer>, alBuffer: ALuint) {
    
    // allocate a buffer for the samples
    let sampleBuffer =  UnsafeMutablePointer<UInt16>(malloc(sizeof(UInt16.self) * Int(player.pointee.bufferSizeBytes)))
    
    // setup an AudioBufferList
    var bufferList = AudioBufferList()
    bufferList.mNumberBuffers = 1
    bufferList.mBuffers.mNumberChannels = 1
    bufferList.mBuffers.mDataByteSize = player.pointee.bufferSizeBytes
    
    // use the sample buffer as the AudioBufferList's buffer
    bufferList.mBuffers.mData = UnsafeMutablePointer<Void>(sampleBuffer)
    
    Swift.print("allocated \(player.pointee.bufferSizeBytes) byte buffer for ABL\n")
    

    
    
    // get the starting phase of the waveform
    var phase: Double = player.pointee.phase
    
    // calculate the length of one cycle (one wavelength)
    let cycleLength: Double  = kSampleRate / kSineFrequency
    
    for frame in 0..<Int(player.pointee.bufferSizeBytes) / sizeof(UInt16.self)
    {
        // get a reference to the channel data (1 channel assumed)
        let channels = UnsafeMutablePointer<Int16>(bufferList.mBuffers.mData)!
        let left = UnsafeMutableBufferPointer<Int16>(start: channels, count: Int(player.pointee.bufferSizeBytes) * sizeof(UInt16.self))
        
        // populate each channel with the same data
        left[frame] = Int16( sin (2 * M_PI * (phase / cycleLength)) * Double(Int16.max))
        
        
//        Swift.print("\(left[frame])")
        
        
        // increment the current frame number
        phase += 1.0
        
        // the phase repeats going from zero through the cycleLength over and over
        if phase > cycleLength { phase -= cycleLength }
    }
    
    // save the current phase as the starting phase for the next iteration
    player.pointee.phase = phase
    

    
    
    
    // copy from the AudioBufferList to the OpenAL buffer
    alBufferData(alBuffer, AL_FORMAT_MONO16, sampleBuffer, ALsizei(player.pointee.bufferSizeBytes), ALsizei(player.pointee.dataFormat.mSampleRate))
    
    // freee the malloc'd memory (the sample buffer)
    free(sampleBuffer)
}
//
// re-fill an OpenAL buffer
//
func refillALBuffers (player: UnsafeMutablePointer<MyStreamPlayer>) {
    var processed: ALint = 0
    
    // get a count of "processed" OpenAL buffers
    alGetSourcei(player.pointee.sources[0], AL_BUFFERS_PROCESSED, &processed)
    Utility.checkAL(operation: "couldn't get al_buffers_processed")
    
    // re-fill & re-queue as many buffers as have been processed
    while (processed > 0) {
        var freeBuffer: ALuint = 0
        
        // get a free buffer (one that was processed)
        alSourceUnqueueBuffers(player.pointee.sources[0], 1, &freeBuffer)
        Utility.checkAL(operation: "couldn't unqueue buffer")
        
        Swift.print("refilling buffer \(freeBuffer)\n")
        
        // fill the OpenAL buffer from the player buffer
        fillALBuffer(player: player, alBuffer: freeBuffer)
        
        // queue the buffer
        alSourceQueueBuffers(player.pointee.sources[0], 1, &freeBuffer)
        Utility.checkAL(operation: "couldn't queue refilled buffer")
        
        Swift.print("re-queued buffer \(freeBuffer)\n")
        
        // decrement the number of processed buffers
        processed = processed - 1
    }
    
}

//--------------------------------------------------------------------------------------------------
// MARK: Main

// create the player
var player = MyStreamPlayer()

// describe the client format - AL needs mono
player.dataFormat.mFormatID = kAudioFormatLinearPCM                                             // uncompressed PCM
player.dataFormat.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked     // signed integer & packed
player.dataFormat.mSampleRate = kSampleRate                                                     // sample rate = 44,100
player.dataFormat.mChannelsPerFrame = 1                                                         // 1 channel
player.dataFormat.mFramesPerPacket = 1                                                          // 1 frame per packet
player.dataFormat.mBitsPerChannel = 16                                                          // 16 bit signed integer
player.dataFormat.mBytesPerFrame = 2                                                            // 2 bytes per frame
player.dataFormat.mBytesPerPacket = 2                                                           // 2 bytes per packet

// calcuate the buffer needed (duration * sample rate * bytes per frame)
player.bufferSizeBytes = kBufferDuration * UInt32(player.dataFormat.mSampleRate) * player.dataFormat.mBytesPerFrame

// set up OpenAL buffers
var alDevice: OpaquePointer
alDevice = alcOpenDevice(nil)
Utility.checkAL(operation: "Couldn't open AL device") // default device

var alContext: OpaquePointer
var attrList: ALCint = 0
alContext = alcCreateContext(alDevice, &attrList)
Utility.checkAL(operation: "Couldn't open AL context")

alcMakeContextCurrent (alContext)
Utility.checkAL(operation: "Couldn't make AL context current")

var buffers = [ALuint](repeating: 0, count: kBufferCount)
alGenBuffers(ALsizei(kBufferCount), &buffers)
Utility.checkAL(operation: "Couldn't generate buffers")

// do the initial filling of the OpenAL buffers
for i in 0..<kBufferCount {
    fillALBuffer(player: &player, alBuffer: buffers[i])
}

// set up OpenAL source
alGenSources(1, &player.sources)
Utility.checkAL(operation: "Couldn't generate sources")

// set the gain
alSourcef(player.sources[0], AL_GAIN, ALfloat(AL_MAX_GAIN))
Utility.checkAL(operation: "Couldn't set source gain")

// set the initial sound position
updateSourceLocation(player: &player)
Utility.checkAL(operation: "Couldn't set initial source position")

// queue up the buffers on the source
alSourceQueueBuffers(player.sources[0],
                     ALsizei(kBufferCount),
                     buffers)
Utility.checkAL(operation: "Couldn't queue buffers on source")

// set the listener position
alListener3f (AL_POSITION, 0.0, 0.0, 0.0)
Utility.checkAL(operation: "Couldn't set listner position")

// start playing
alSourcePlayv (1, player.sources)
Utility.checkAL(operation: "Couldn't play")

// and wait
Swift.print("Playing...\n")

// start now and loop for kRunTime seconds
var startTime: time_t  = time(nil)
repeat
{
    // get next theta
    updateSourceLocation(player: &player)
    Utility.checkAL(operation: "Couldn't set source position")
    
    // refill buffers if needed
    refillALBuffers (player: &player)
    
    // pause
    CFRunLoopRunInMode(CFRunLoopMode.defaultMode, 0.1, false)
    
} while (difftime(time(nil), startTime) < kRunTime)

// cleanup
alSourceStop(player.sources[0])
alDeleteSources(1, player.sources)
alDeleteBuffers(ALsizei(kBufferCount), buffers)
alcDestroyContext(alContext)
alcCloseDevice(alDevice)

Swift.print("Bottom of main\n")
