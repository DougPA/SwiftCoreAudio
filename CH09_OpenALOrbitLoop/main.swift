//
//  main.swift
//  CH09_OpenALOrbitLoop
//
//  Created by Douglas Adams on 7/17/16.
//

import AudioToolbox
import OpenAL

//--------------------------------------------------------------------------------------------------
// MARK: Constants

let loopPath = CFStringCreateWithCString(kCFAllocatorDefault,
                                         "/Library/Audio/Apple Loops/Apple/iLife Sound Effects/Transportation/Bicycle Coasting.caf",
                                         CFStringBuiltInEncodings.UTF8.rawValue)

let kOrbitSpeed: Double = 1                 // speed in seconds
let kRunTime = 20.0                         // run time in seconds

//--------------------------------------------------------------------------------------------------
// MARK: Struct definition

struct MyLoopPlayer {
    var dataFormat = AudioStreamBasicDescription()                      // loop AudioStreamBasicDescription
    var sampleBuffer: UnsafeMutablePointer<UInt16>?                     // pointer to the Sample buffer
    var bufferSizeBytes: UInt32 = 0                                     // buffer size in bytes
    var sources = [ALuint](repeating: 0, count: 1)                      // OpenAL source handles
}

//--------------------------------------------------------------------------------------------------
// MARK: Supporting methods

//
// calculate and set a new player position
//
func updateSourceLocation(player: UnsafeMutablePointer<MyLoopPlayer>) {
    
    let theta: Double  = fmod(CFAbsoluteTimeGetCurrent() * kOrbitSpeed, M_PI * 2)
    let x = ALfloat(3.0 * cos(theta))
    let y = ALfloat(0.5 * sin (theta))
    let z = ALfloat(1.0 * sin (theta))
    
    Swift.print("x = \(x), y = \(y), z = \(z)\n")
    
    alSource3f(player.pointee.sources[0], AL_POSITION, x, y, z)
}
//
// use ExtAudioFile to load a loop into the Player's buffer
//
func loadLoopIntoBuffer(player: UnsafeMutablePointer<MyLoopPlayer>) -> OSStatus {
    
    let loopFileURL: CFURL  = CFURLCreateWithFileSystemPath(kCFAllocatorDefault, loopPath, .cfurlposixPathStyle, false)
    
    // describe the client format - AL needs mono
    player.pointee.dataFormat.mFormatID = kAudioFormatLinearPCM
    player.pointee.dataFormat.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked
    player.pointee.dataFormat.mSampleRate = 44100.0
    player.pointee.dataFormat.mChannelsPerFrame = 1
    player.pointee.dataFormat.mFramesPerPacket = 1
    player.pointee.dataFormat.mBitsPerChannel = 16
    player.pointee.dataFormat.mBytesPerFrame = 2
    player.pointee.dataFormat.mBytesPerPacket = 2
    
    var extAudioFile: ExtAudioFileRef?
    Utility.check(error: ExtAudioFileOpenURL(loopFileURL,
                                             &extAudioFile),
                  operation: "Couldn't open ExtAudioFile for reading")
    
    // tell extAudioFile about our format
    Utility.check(error: ExtAudioFileSetProperty(extAudioFile!,
                                                 kExtAudioFileProperty_ClientDataFormat,
                                                 UInt32(sizeof(AudioStreamBasicDescription.self)),
                                                 &player.pointee.dataFormat),
                  operation: "Couldn't set client format on ExtAudioFile")
    
    // figure out how big a buffer we need
    var fileLengthFrames: Int64 = 0
    var propSize = UInt32(sizeof(Int64.self))
    ExtAudioFileGetProperty(extAudioFile!,
                            kExtAudioFileProperty_FileLengthFrames,
                            &propSize,
                            &fileLengthFrames)
    
    Swift.print("plan on reading \(fileLengthFrames) frames\n")
    
    player.pointee.bufferSizeBytes = UInt32(fileLengthFrames) * player.pointee.dataFormat.mBytesPerFrame
    
    // allocate sample buffer
    player.pointee.sampleBuffer =  UnsafeMutablePointer<UInt16>(malloc(sizeof(UInt16.self) * Int(player.pointee.bufferSizeBytes))) // 4/18/11 - fix 1

    var bufferList = AudioBufferList()
    bufferList.mNumberBuffers = 1
    bufferList.mBuffers.mNumberChannels = 1
    bufferList.mBuffers.mDataByteSize = player.pointee.bufferSizeBytes
    bufferList.mBuffers.mData = UnsafeMutablePointer<Void>(player.pointee.sampleBuffer)
    
    Swift.print("created AudioBufferList\n")
    
    // loop reading into the ABL until buffer is full
    var totalFramesRead: UInt32 = 0
    repeat {
        var framesRead: UInt32  = UInt32(fileLengthFrames) - totalFramesRead
        bufferList.mBuffers.mData = UnsafeMutablePointer<Void>(player.pointee.sampleBuffer?.advanced(by: Int(totalFramesRead) * sizeof(UInt16.self)))
        Utility.check(error: ExtAudioFileRead(extAudioFile!,
                                              &framesRead,
                                              &bufferList),
                      operation: "ExtAudioFileRead failed")
        
        totalFramesRead += framesRead
        
        Swift.print("read \(framesRead) frames\n")
        
    } while (totalFramesRead < UInt32(fileLengthFrames))
    
    return noErr
}

//--------------------------------------------------------------------------------------------------
// MARK: Main

// create the player
var player = MyLoopPlayer()
    
// convert to an OpenAL-friendly format and read into memory
Utility.check(error: loadLoopIntoBuffer(player: &player),
              operation: "Couldn't load loop into buffer")
    
// set up OpenAL buffer
var alDevice: OpaquePointer
alDevice = alcOpenDevice(nil)
Utility.checkAL(operation: "Couldn't open AL device") // default device

var alContext: OpaquePointer
var attrList: ALCint = 0
alContext = alcCreateContext(alDevice, &attrList)
Utility.checkAL(operation: "Couldn't open AL context")

alcMakeContextCurrent(alContext)
Utility.checkAL(operation: "Couldn't make AL context current")

var buffers: ALuint = 0     // only one buffer
alGenBuffers(1, &buffers)
Utility.checkAL(operation: "Couldn't generate buffers")

alBufferData(buffers,
             AL_FORMAT_MONO16,
             player.sampleBuffer,
             ALsizei(player.bufferSizeBytes),
             ALsizei(player.dataFormat.mSampleRate))
    
// AL copies the samples, so we can free them now
free(player.sampleBuffer)

// set up OpenAL source
alGenSources(1, &player.sources)
Utility.checkAL(operation: "Couldn't generate sources")

// set the source to Looping mode
alSourcei(player.sources[0], AL_LOOPING, AL_TRUE)
Utility.checkAL(operation: "Couldn't set source looping property")

// set the gain
alSourcef(player.sources[0], AL_GAIN, ALfloat(AL_MAX_GAIN))
Utility.checkAL(operation: "Couldn't set source gain")

// set the initial sound position
updateSourceLocation(player: &player)
Utility.checkAL(operation: "Couldn't set initial source position")

// connect buffer to source
alSourcei(player.sources[0], AL_BUFFER, ALint(buffers))
Utility.checkAL(operation: "Couldn't connect buffer to source")
    
// set up listener
alListener3f (AL_POSITION, 0.0, 0.0, 0.0)
Utility.checkAL(operation: "Couldn't set listner position")
    
    //	ALfloat listenerOrientation[6]; // 3 vectors: forward x,y,z components, then up x,y,z
    //	listenerOrientation[2] = -1.0;
    //	listenerOrientation[0] = listenerOrientation [1] = 0.0;
    //	listenerOrientation[3] = listenerOrientation [4] =  listenerOrientation[5] = 0.0;
    //	alListenerfv (AL_ORIENTATION, listenerOrientation);
    
// start playing
// alSourcePlayv (1, player.sources);
alSourcePlay(player.sources[0])
Utility.checkAL(operation: "Couldn't play")
    
// and wait
Swift.print("Playing...\n")

// start now and loop for kRunTime seconds
var startTime: time_t  = time(nil)
repeat
{
    // get next theta
    updateSourceLocation(player: &player)
    Utility.checkAL(operation: "Couldn't set looping source position")
    
    // pause
    CFRunLoopRunInMode(CFRunLoopMode.defaultMode, 0.1, false)
    
} while (difftime(time(nil), startTime) < kRunTime)

// cleanup
alSourceStop(player.sources[0])
alDeleteSources(1, player.sources)
alDeleteBuffers(1, &buffers)
alcDestroyContext(alContext)
alcCloseDevice(alDevice)

Swift.print("Bottom of main\n")
