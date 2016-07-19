//
//  main.swift
//  CH09_OpenALOrbitStream
//
//  Created by Douglas Adams on 7/19/16.
//

import AudioToolbox
import OpenAL

let streamPath = CFStringCreateWithCString(kCFAllocatorDefault, "/Library/Audio/Apple Loops/Apple/iLife Sound Effects/Jingles/Kickflip Long.caf", CFStringBuiltInEncodings.UTF8.rawValue)
//#define STREAM_PATH CFSTR ("/Volumes/Sephiroth/Tunes/Yes/Highlights - The Very Best Of Yes/Long Distance Runaround.m4a")

let kBufferDuration: UInt32 = 1
let kBufferCount = 3
let kOrbitSpeed: Double = 1
let kRunTime = 20.0

//--------------------------------------------------------------------------------------------------
// MARK: Struct definition

struct MyStreamPlayer {
    var dataFormat = AudioStreamBasicDescription()
    var bufferSizeBytes: UInt32	= 0
    var fileLengthFrames: Int64 = 0
    var totalFramesRead: Int64 = 0
    var sources = [ALuint](repeating: 0, count: 1)
    var extAudioFile: ExtAudioFileRef?
}

//--------------------------------------------------------------------------------------------------
// MARK: Supporting methods

func updateSourceLocation(player: UnsafeMutablePointer<MyStreamPlayer>) {
    
    let theta: Double  = fmod(CFAbsoluteTimeGetCurrent() * kOrbitSpeed, M_PI * 2)
    // printf ("%f\n", theta);
    let x = ALfloat(3.0 * cos(theta))
    let y = ALfloat(0.5 * sin (theta))
    let z = ALfloat(1.0 * sin (theta))
    
    Swift.print("x = \(x), y = \(y), z = \(z)\n")
    
    alSource3f(player.pointee.sources[0], AL_POSITION, x, y, z)
}


func setUpExtAudioFile (player: UnsafeMutablePointer<MyStreamPlayer>) -> OSStatus {

    let streamFileURL: CFURL  = CFURLCreateWithFileSystemPath(kCFAllocatorDefault, streamPath, .cfurlposixPathStyle, false)
    
    // describe the client format - AL needs mono
    memset(&player.pointee.dataFormat, 0, sizeof(AudioStreamBasicDescription.self))
    player.pointee.dataFormat.mFormatID = kAudioFormatLinearPCM
    player.pointee.dataFormat.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked
    player.pointee.dataFormat.mSampleRate = 44100.0
    player.pointee.dataFormat.mChannelsPerFrame = 1
    player.pointee.dataFormat.mFramesPerPacket = 1
    player.pointee.dataFormat.mBitsPerChannel = 16
    player.pointee.dataFormat.mBytesPerFrame = 2
    player.pointee.dataFormat.mBytesPerPacket = 2
    
    Utility.check(error: ExtAudioFileOpenURL(streamFileURL, &player.pointee.extAudioFile),
                  operation: "Couldn't open ExtAudioFile for reading")
    
    // tell extAudioFile about our format
    Utility.check(error: ExtAudioFileSetProperty(player.pointee.extAudioFile!,
                                                 kExtAudioFileProperty_ClientDataFormat,
                                                 UInt32(sizeof (AudioStreamBasicDescription.self)),
                                                 &player.pointee.dataFormat),
                  operation: "Couldn't set client format on ExtAudioFile")
    
    // figure out how big file is
    var propSize = UInt32(sizeof(Int64.self))
    ExtAudioFileGetProperty(player.pointee.extAudioFile!,
                            kExtAudioFileProperty_FileLengthFrames,
                            &propSize,
                            &player.pointee.fileLengthFrames);
    
    Swift.print("fileLengthFrames = \(player.pointee.fileLengthFrames) frames\n")
    
    player.pointee.bufferSizeBytes = kBufferDuration *
        UInt32(player.pointee.dataFormat.mSampleRate) *
        player.pointee.dataFormat.mBytesPerFrame;
    
    Swift.print("bufferSizeBytes = \(player.pointee.bufferSizeBytes)\n")
    
    Swift.print("Bottom of setUpExtAudioFile\n")
    
    return noErr
}

func fillALBuffer (player: UnsafeMutablePointer<MyStreamPlayer>, alBuffer: ALuint) {
    
    var bufferList: UnsafeMutablePointer<AudioBufferList>
    let ablSize  = sizeof(UInt32.self) + (sizeof(AudioBuffer.self) * 1) // 1 channel
    bufferList = UnsafeMutablePointer<AudioBufferList>(malloc(ablSize))
    
    // allocate sample buffer
    let sampleBuffer =  UnsafeMutablePointer<UInt16>(malloc(sizeof(UInt16.self) * Int(player.pointee.bufferSizeBytes)))
    
    bufferList.pointee.mNumberBuffers = 1
    bufferList.pointee.mBuffers.mNumberChannels = 1
    bufferList.pointee.mBuffers.mDataByteSize = player.pointee.bufferSizeBytes
    bufferList.pointee.mBuffers.mData = UnsafeMutablePointer<Void>(sampleBuffer)
    Swift.print("allocated \(player.pointee.bufferSizeBytes) byte buffer for ABL\n")
    
    // read from ExtAudioFile into sampleBuffer
    // TODO: handle end-of-file wraparound
    var framesReadIntoBuffer: UInt32 = 0
    repeat {
        var framesRead = UInt32(player.pointee.fileLengthFrames) - framesReadIntoBuffer
        bufferList.pointee.mBuffers.mData = UnsafeMutablePointer<Void>(sampleBuffer?.advanced(by: Int(framesReadIntoBuffer) * sizeof(UInt16.self)))
        Utility.check(error: ExtAudioFileRead(player.pointee.extAudioFile!,
                                              &framesRead,
                                              bufferList),
                      operation: "ExtAudioFileRead failed")
        
        framesReadIntoBuffer += framesRead
        
        player.pointee.totalFramesRead = player.pointee.totalFramesRead + Int64(framesRead)
        
        Swift.print("read \(framesRead) frames\n")
        
    } while (framesReadIntoBuffer < (player.pointee.bufferSizeBytes / UInt32(sizeof(UInt16.self))))
    
    // copy from sampleBuffer to AL buffer
    alBufferData(alBuffer, AL_FORMAT_MONO16, sampleBuffer, ALsizei(player.pointee.bufferSizeBytes), ALsizei(player.pointee.dataFormat.mSampleRate))
    
    free(bufferList)
    free(sampleBuffer)
}

func refillALBuffers (player: UnsafeMutablePointer<MyStreamPlayer>) {
    var processed: ALint = 0
    alGetSourcei(player.pointee.sources[0], AL_BUFFERS_PROCESSED, &processed)
    Utility.checkAL(operation: "couldn't get al_buffers_processed")
    
    while (processed > 0) {
        var freeBuffer: ALuint = 0
        
        alSourceUnqueueBuffers(player.pointee.sources[0], 1, &freeBuffer)
        Utility.checkAL(operation: "couldn't unqueue buffer");

        Swift.print("refilling buffer \(freeBuffer)\n")
        
        fillALBuffer(player: player, alBuffer: freeBuffer)
        
        alSourceQueueBuffers(player.pointee.sources[0], 1, &freeBuffer)
        Utility.checkAL(operation: "couldn't queue refilled buffer")
        
        Swift.print("re-queued buffer \(freeBuffer)\n")
        processed = processed - 1
    }
    
}

//--------------------------------------------------------------------------------------------------
// MARK: Main

var player = MyStreamPlayer()

// prepare the ExtAudioFile for reading
Utility.check(error: setUpExtAudioFile(player: &player),
              operation: "Couldn't open ExtAudioFile")

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

for i in 0..<kBufferCount {
    fillALBuffer(player: &player, alBuffer: buffers[i])
}

// set up streaming source
alGenSources(1, &player.sources)
Utility.checkAL(operation: "Couldn't generate sources")

alSourcef(player.sources[0], AL_GAIN, ALfloat(AL_MAX_GAIN))
Utility.checkAL(operation: "Couldn't set source gain")

updateSourceLocation(player: &player)
Utility.checkAL(operation: "Couldn't set initial source position")

// queue up the buffers on the source
alSourceQueueBuffers(player.sources[0],
                     ALsizei(kBufferCount),
                     buffers)
Utility.checkAL(operation: "Couldn't queue buffers on source")

// set up listener
alListener3f (AL_POSITION, 0.0, 0.0, 0.0)
Utility.checkAL(operation: "Couldn't set listner position")

// start playing
alSourcePlayv (1, player.sources)
Utility.checkAL(operation: "Couldn't play")

// and wait
Swift.print("Playing...\n")

var startTime: time_t  = time(nil)
repeat
{
    // get next theta
    updateSourceLocation(player: &player)
    Utility.checkAL(operation: "Couldn't set source position")
    
    // refill buffers if needed
    refillALBuffers (player: &player)
    
    CFRunLoopRunInMode(CFRunLoopMode.defaultMode, 0.1, false)
    
} while (difftime(time(nil), startTime) < kRunTime)

// cleanup:
alSourceStop(player.sources[0])
alDeleteSources(1, player.sources)
alDeleteBuffers(ALsizei(kBufferCount), buffers)
alcDestroyContext(alContext)
alcCloseDevice(alDevice)

Swift.print("Bottom of main\n")


// from chris' openal streaming article... just leaving as notes so I can move between computers
// and have this in svn/dropbox

/*
 // set up and use function pointer to alBufferDataStaticProcPtr
 ALvoid  alBufferDataStaticProc(const ALint bid, ALenum format, ALvoid* data, ALsizei size, ALsizei freq)
 {
 static	alBufferDataStaticProcPtr	proc = NULL;
 
 if (proc == NULL) {
 proc = (alBufferDataStaticProcPtr) alGetProcAddress((const ALCchar*) "alBufferDataStatic");
 }
 
 if (proc)
 proc(bid, format, data, size, freq);
 
 return;
 }
 */
