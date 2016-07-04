//
//  main.swift
//  CH05_Player
//
//  Created by Douglas Adams on 7/3/16.
//

import CoreFoundation
import AudioToolbox

let kPlaybackFileLocation = CFStringCreateWithCString(kCFAllocatorDefault, "/Users/Doug/x.mp3", CFStringBuiltInEncodings.UTF8.rawValue)

//#define kPlaybackFileLocation	CFSTR("/Users/cadamson/Library/Developer/Xcode/DerivedData/CH04_Recorder-dvninfofohfiwcgyndnhzarhsipp/Build/Products/Debug/output.caf")
//#define kPlaybackFileLocation	CFSTR("/Users/cadamson/audiofile.m4a")
//#define kPlaybackFileLocation	CFSTR("/Volumes/Sephiroth/iTunes/iTunes Media/Music/The Tubes/Tubes World Tour 2001/Wild Women of Wongo.m4p")
//#define kPlaybackFileLocation	CFSTR("/Volumes/Sephiroth/iTunes/iTunes Media/Music/Compilations/ESCAFLOWNE - ORIGINAL MOVIE SOUNDTRACK/21 We're flying.m4a")


let kNumberPlaybackBuffers = 3

let kMaxBufferSize: UInt32 = 0x10000                    // limit size to 64K
let kMinBufferSize: UInt32 = 0x4000                     // limit size to 16K

struct Player {
    var playbackFile: AudioFileID?                                          // reference to your output file
    var packetPosition: Int64 = 0                                           // current packet index in output file
    var numPacketsToRead: UInt32 = 0                                        // number of packets to read from file
    var packetDescs: UnsafeMutablePointer<AudioStreamPacketDescription>?    // array of packet descriptions for read buffer
    var isDone = false                                                      // playback has completed
}

// we only use time here as a guideline
// we're really trying to get somewhere between 16K and 64K buffers, but not allocate too much if we don't need it
func CalculateBytesForTime (inAudioFile: AudioFileID,
                            inDesc: AudioStreamBasicDescription,
                            inSeconds: Double,
                            outBufferSize: UnsafeMutablePointer<UInt32>,
                            outNumPackets: UnsafeMutablePointer<UInt32>)
{
    
    // we need to calculate how many packets we read at a time, and how big a buffer we need.
    // we base this on the size of the packets in the file and an approximate duration for each buffer.
    //
    // first check to see what the max size of a packet is, if it is bigger than our default
    // allocation size, that needs to become larger
    var maxPacketSize: UInt32 = 0
    var propSize: UInt32  = 4
    Utility.check(error: AudioFileGetProperty(inAudioFile,
                                              kAudioFilePropertyPacketSizeUpperBound,
                                              &propSize,
                                              &maxPacketSize),
                  operation: "couldn't get file's max packet size")
    
    
    if inDesc.mFramesPerPacket > 0 {
        
        let numPacketsForTime = UInt32(inDesc.mSampleRate / (Double(inDesc.mFramesPerPacket) * inSeconds))
        
        outBufferSize.pointee = numPacketsForTime * maxPacketSize
    
    } else {
        // if frames per packet is zero, then the codec has no predictable packet == time
        // so we can't tailor this (we don't know how many Packets represent a time period
        // we'll just return a default buffer size
        outBufferSize.pointee = (kMaxBufferSize > maxPacketSize ? kMaxBufferSize : maxPacketSize)
    }
    
    // we're going to limit our size to our default
    if outBufferSize.pointee > kMaxBufferSize && outBufferSize.pointee > maxPacketSize {
        
        outBufferSize.pointee = kMaxBufferSize
    
    } else {
        // also make sure we're not too small - we don't want to go the disk for too small chunks
        if outBufferSize.pointee < kMinBufferSize {
            outBufferSize.pointee = kMinBufferSize
        }
    }
    outNumPackets.pointee = outBufferSize.pointee / maxPacketSize
}
//
//
//
func outputCallback(inUserData: UnsafeMutablePointer<Void>?, inAQ: AudioQueueRef, inCompleteAQBuffer: AudioQueueBufferRef) {

    if let player = UnsafeMutablePointer<Player>(inUserData) {
        
        if player.pointee.isDone { return }
        
        // read audio data from file into supplied buffer
        var numBytes: UInt32 = inCompleteAQBuffer.pointee.mAudioDataBytesCapacity
        var nPackets = player.pointee.numPacketsToRead
        
        Utility.check(error: AudioFileReadPacketData(player.pointee.playbackFile!,
                                                     false,
                                                     &numBytes,
                                                     player.pointee.packetDescs,
                                                     player.pointee.packetPosition,
                                                     &nPackets,
                                                     inCompleteAQBuffer.pointee.mAudioData),
                      operation: "AudioFileReadPacketData failed")

        // enqueue buffer into the Audio Queue
        // if nPackets == 0 it means we are EOF (all data has been read from file)
        if nPackets > 0 {
            inCompleteAQBuffer.pointee.mAudioDataByteSize = numBytes
            
            Utility.check(error: AudioQueueEnqueueBuffer(inAQ,
                                                         inCompleteAQBuffer,
                                                         (player.pointee.packetDescs == nil ? 0 : nPackets),
                                                         player.pointee.packetDescs),
                          operation: "AudioQueueEnqueueBuffer failed")
            
            player.pointee.packetPosition += Int64(nPackets)
            
        } else {
            
            Utility.check(error: AudioQueueStop(inAQ, false),
                          operation: "AudioQueueStop failed")
            
            player.pointee.isDone = true
        }
    }
}

//--------------------------------------------------------------------------------------------------
// MARK: Main

var player = Player()
    
let fileURL: CFURL  = CFURLCreateWithFileSystemPath(kCFAllocatorDefault, kPlaybackFileLocation, .cfurlposixPathStyle, false)

    // open the audio file
Utility.check(error: AudioFileOpenURL(fileURL,
                                      .readPermission,
                                      0,
                                      &player.playbackFile),
              operation: "AudioFileOpenURL failed")


// get the audio data format from the file
var dataFormat = AudioStreamBasicDescription()
var propSize = UInt32(sizeof(AudioStreamBasicDescription))

Utility.check(error: AudioFileGetProperty(player.playbackFile!,
                                          kAudioFilePropertyDataFormat,
                                          &propSize,
                                          &dataFormat),
              operation: "couldn't get file's data format");
    
// create an output (playback) queue
var queue: AudioQueueRef?
Utility.check(error: AudioQueueNewOutput(&dataFormat,
                                         outputCallback,
                                         &player,
                                         nil,
                                         nil,
                                         0,
                                         &queue),
              operation: "AudioQueueNewOutput failed");
    
    
    // adjust buffer size to represent about a half second (0.5) of audio based on this format
var bufferByteSize: UInt32 = 0

CalculateBytesForTime(inAudioFile: player.playbackFile!, inDesc: dataFormat,  inSeconds: 0.5, outBufferSize: &bufferByteSize, outNumPackets: &player.numPacketsToRead)

// check if we are dealing with a VBR file. ASBDs for VBR files always have
// mBytesPerPacket and mFramesPerPacket as 0 since they can fluctuate at any time.
// If we are dealing with a VBR file, we allocate memory to hold the packet descriptions
let isFormatVBR = (dataFormat.mBytesPerPacket == 0 || dataFormat.mFramesPerPacket == 0);

if isFormatVBR {
    player.packetDescs = UnsafeMutablePointer<AudioStreamPacketDescription>(malloc(sizeof(AudioStreamPacketDescription) * Int(player.numPacketsToRead)))
} else {
    player.packetDescs = nil; // we don't provide packet descriptions for constant bit rate formats (like linear PCM)
}

// get magic cookie from file and set on queue
Utility.applyEncoderCookie(fromFile: player.playbackFile!, toQueue: queue!)

// allocate the buffers and prime the queue with some data before starting
var buffers = [AudioQueueBufferRef?](repeating: nil, count: kNumberPlaybackBuffers)

player.isDone = false
player.packetPosition = 0

for i in 0..<kNumberPlaybackBuffers where !player.isDone {
        Utility.check(error: AudioQueueAllocateBuffer(queue!,
                                                      bufferByteSize,
                                                      &buffers[i]),
                      operation: "AudioQueueAllocateBuffer failed");
        
        // manually invoke callback to fill buffers with data
        outputCallback(inUserData: &player, inAQ: queue!, inCompleteAQBuffer: buffers[i]!)
}

// start the queue. this function returns immedatly and begins
// invoking the callback, as needed, asynchronously.
Utility.check(error: AudioQueueStart(queue!, nil), operation: "AudioQueueStart failed");

// and wait
Swift.print("Playing...\n");
repeat
{
    CFRunLoopRunInMode(CFRunLoopMode.defaultMode, 0.25, false)
} while !player.isDone

// isDone represents the state of the Audio File enqueuing. This does not mean the
// Audio Queue is actually done playing yet. Since we have 3 half-second buffers in-flight
// run for continue to run for a short additional time so they can be processed
CFRunLoopRunInMode(CFRunLoopMode.defaultMode, 2, false)

// end playback
player.isDone = true
Utility.check(error: AudioQueueStop(queue!, true), operation: "AudioQueueStop failed");

AudioQueueDispose(queue!, true)
AudioFileClose(player.playbackFile!)

exit(0)


