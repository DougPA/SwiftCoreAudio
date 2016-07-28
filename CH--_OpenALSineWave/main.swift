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

let kBufferDuration: Double = 0.01          // duration in seconds of a buffer
let kBufferCount = 8                        // number of buffers
let kRefreshInterval: CFTimeInterval = 1.0  // interval in seconds between buffer processing
let kRunTime = 10.0                         // program run time in seconds

let kSampleRate: Double = 24_000.0          // sample rate
let kSineFrequency: Double = 440.0          // sine wave frequency


//--------------------------------------------------------------------------------------------------
// MARK: Struct definition

struct MyStreamPlayer {
    var dataFormat = AudioStreamBasicDescription()      // stream AudioStreamBasicDescription
    var bufferSizeBytes: UInt32	= 0                     // buffer size in bytes
    var bufferList: AudioBufferList!
    var sources = [ALuint](repeating: 0, count: 1)      // OpenAL source handles
    var phase: Double = 0.0                             // current phase of sine wave
}

//--------------------------------------------------------------------------------------------------
// MARK: Supporting methods

//
// fill an OpenAL buffer with Sine Wave data
//
func fillALBuffer (player: UnsafeMutablePointer<MyStreamPlayer>, alBuffer: ALuint) {
    
    // get the starting phase of the waveform
    var phase: Double = player.pointee.phase
    
    // calculate the length of one cycle (one wavelength)
    let cycleLength: Double  = kSampleRate / kSineFrequency
    
    for frame in 0..<Int(player.pointee.bufferSizeBytes) / sizeof(UInt16.self)
    {
        // get a reference to the channel data (1 channel assumed)
        let channels = UnsafeMutablePointer<Int16>(player.pointee.bufferList.mBuffers.mData)!
        let left = UnsafeMutableBufferPointer<Int16>(start: channels, count: Int(player.pointee.bufferSizeBytes) / sizeof(UInt16.self))
        
        // populate each channel with the same data
        left[frame] = Int16( sin (2 * M_PI * (phase / cycleLength)) * Double(Int16.max))
        
        // increment the current frame number
        phase += 1.0
        
        // the phase repeats going from zero through the cycleLength over and over
        if phase > cycleLength { phase -= cycleLength }
    }
    
    // save the current phase as the starting phase for the next iteration
    player.pointee.phase = phase
    
    // copy from the AudioBufferList to the OpenAL buffer
    alBufferData(alBuffer, AL_FORMAT_MONO16, player.pointee.bufferList.mBuffers.mData, ALsizei(player.pointee.bufferSizeBytes), ALsizei(player.pointee.dataFormat.mSampleRate))
    
    // freee the malloc'd memory (the sample buffer)
//    free(sampleBuffer)
}
//
// re-fill an OpenAL buffer
//
func refillALBuffers (player: UnsafeMutablePointer<MyStreamPlayer>) {
    var processed: ALint = 0
    
    // get a count of "processed" OpenAL buffers
    alGetSourcei(player.pointee.sources[0], AL_BUFFERS_PROCESSED, &processed)
    Utility.checkAL(operation: "couldn't get al_buffers_processed")
    
//    Swift.print("processed = \(processed)")
    
    // re-fill & re-queue as many buffers as have been processed
    while (processed > 0) {
        var freeBuffer: ALuint = 0
        
        // get a free buffer (one that was processed)
        alSourceUnqueueBuffers(player.pointee.sources[0], 1, &freeBuffer)
        Utility.checkAL(operation: "couldn't unqueue buffer")
        
//        Swift.print("refilling buffer \(freeBuffer)\n")
        
        // fill the OpenAL buffer from the player buffer
        fillALBuffer(player: player, alBuffer: freeBuffer)
        
        // queue the buffer
        alSourceQueueBuffers(player.pointee.sources[0], 1, &freeBuffer)
        Utility.checkAL(operation: "couldn't queue refilled buffer")
        
//        Swift.print("re-queued buffer \(freeBuffer)\n")
        
        // decrement the number of processed buffers
        processed = processed - 1
    }
    
}

//--------------------------------------------------------------------------------------------------
// MARK: Main

var	bufferDataStaticProc: alBufferDataStaticProcPtr

var sourceAddNotificationProc: alSourceAddNotificationProcPtr
var sourceNotificationProc: @convention(c) (sid: ALuint, notificationID: ALuint, userData: UnsafeMutablePointer<Void>?) -> Swift.Void

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

// calcuate the buffer needed (buffer duration * sample rate * bytes per frame = number of bytes)
player.bufferSizeBytes = UInt32(kBufferDuration * player.dataFormat.mSampleRate * Double(player.dataFormat.mBytesPerFrame))

// create & setup an AudioBufferList for the samples
var audioBuffer = AudioBuffer(mNumberChannels: 1, mDataByteSize: player.bufferSizeBytes, mData: nil)
player.bufferList = AudioBufferList(mNumberBuffers: 1, mBuffers: audioBuffer)

// allocate a buffer for the samples
let sampleBuffer =  UnsafeMutablePointer<UInt16>(malloc( Int(player.bufferSizeBytes) ))

// use the sample buffer as the AudioBufferList's buffer
player.bufferList.mBuffers.mData = UnsafeMutablePointer<Void>(sampleBuffer)

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

// create kBufferCount OpenAL buffers
var buffers = [ALuint](repeating: 0, count: kBufferCount)
alGenBuffers(ALsizei(kBufferCount), &buffers)
Utility.checkAL(operation: "Couldn't generate buffers")

// set up OpenAL source
alGenSources(1, &player.sources)
Utility.checkAL(operation: "Couldn't generate sources")

// set the gain
alSourcef(player.sources[0], AL_GAIN, ALfloat(AL_MAX_GAIN))
Utility.checkAL(operation: "Couldn't set source gain")

// set the initial sound position
alSource3f(player.sources[0], AL_POSITION, 0.0, 0.0, 0.0)
Utility.checkAL(operation: "Couldn't set sound position")

// create a closure to use as the callback proc for AL_EXT_SOURCE_NOTIFICATIONS
//      NOTE: may be called while previous callback is still executing
//
sourceNotificationProc = {sid, notificationID, userData in

    // is it an AL_BUFFER_PROCESSED notification?
    if notificationID == ALuint(AL_BUFFERS_PROCESSED) {

        // YES, refill buffers if needed (enforce sequential order)
        DispatchQueue.main.async {
            refillALBuffers (player: UnsafeMutablePointer<MyStreamPlayer>(userData!))
        }
    }
}

// determine if the AL_EXT_SOURCE_NOTIFICATIONS extension is present
var extName = "AL_EXT_SOURCE_NOTIFICATIONS"
if alIsExtensionPresent(extName) == ALboolean(AL_TRUE) {
    
    // can we get the Proc's address?
    if let ptr = alGetProcAddress("alSourceAddNotification") {
        
        // YES, cast it
        sourceAddNotificationProc = unsafeBitCast(ptr, to: alSourceAddNotificationProcPtr.self)
        
        // set the callback (exit if unsuccessful)
        let x = sourceAddNotificationProc(player.sources[0], ALuint(AL_BUFFERS_PROCESSED), sourceNotificationProc, &player)
        if x != AL_NO_ERROR {
            
            Swift.print("Couldn't perform alSourceAddNotification")
            exit(1)
        }
    
    } else {
        
        // NO, exit
        Swift.print("Couldn't get alSourceAddNotification ProcAddress")
        exit(1)
    }
}

// determine if the AL_EXT_STATIC_BUFFER extension is present
extName = "AL_EXT_STATIC_BUFFER"
if alIsExtensionPresent("AL_EXT_STATIC_BUFFER") == ALboolean(AL_TRUE) {
    
    // can we get the Proc's address?
    if let ptr = alGetProcAddress("alBufferDataStatic") {
        
        // YES, cast it
        bufferDataStaticProc = unsafeBitCast(ptr, to: alBufferDataStaticProcPtr.self)
        
        for i in 0..<kBufferCount {
            
            // setup the buffer to use Static data
            bufferDataStaticProc(ALint(buffers[i]), AL_FORMAT_MONO16, &buffers[i], ALsizei(player.bufferSizeBytes), ALsizei(player.dataFormat.mSampleRate) )

            // do the initial fill of the buffer
            fillALBuffer(player: &player, alBuffer: buffers[i])
        }

    } else {
        
        // NO, exit
        Swift.print("Couldn't get alBufferDataStatic ProcAddress")
        exit(1)
    }
}

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
    
    // pause
    CFRunLoopRunInMode(CFRunLoopMode.defaultMode, kRefreshInterval, false)
    
} while (difftime(time(nil), startTime) < kRunTime)

// cleanup

free(sampleBuffer)

alSourceStop(player.sources[0])
alDeleteSources(1, player.sources)
alDeleteBuffers(ALsizei(kBufferCount), buffers)
alcDestroyContext(alContext)
alcCloseDevice(alDevice)

Swift.print("Bottom of main\n")
