//
//  main.swift
//  CH04_Recorder
//
//  Created by Douglas Adams on 6/30/16.
//  Copyright © 2016 Douglas Adams. All rights reserved.
//

import AudioToolbox

let kNumberRecordBuffers = 3            //

struct Recorder {                       // Struct to use in the Callback
    
    var recordFile: AudioFileID?		// reference to your output file
    var recordPacket: Int64	= 0         // current packet index in output file
    var running = false                 // recording state
}
//
// set the output sample rate to be the same as the default input Device
//
func setOutputSampleRate(_ outSampleRate: UnsafeMutablePointer<Void>) -> OSStatus {
    var error: OSStatus = noErr
    var deviceID: AudioDeviceID  = 0
    
    var propertyAddress: AudioObjectPropertyAddress = AudioObjectPropertyAddress()
    var propertySize: UInt32 = 0
    
    // get the default input device
    propertyAddress.mSelector = kAudioHardwarePropertyDefaultInputDevice
    propertyAddress.mScope = kAudioObjectPropertyScopeGlobal
    propertyAddress.mElement = 0
    propertySize = 4
    
    error = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &propertySize, &deviceID)
    
    if error != noErr { return error }
    
    // get its sample rate
    propertyAddress.mSelector = kAudioDevicePropertyNominalSampleRate;
    propertyAddress.mScope = kAudioObjectPropertyScopeGlobal;
    propertyAddress.mElement = 0;
    propertySize = 8
    
    error = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &propertySize, outSampleRate)
    
    return error;
}
//
// Callback function
//
func inputCallback(inUserData: UnsafeMutablePointer<Void>?,
                   inQueue: AudioQueueRef,
                   inBuffer: UnsafeMutablePointer<AudioQueueBuffer>,
                   inStartTime: UnsafePointer<AudioTimeStamp>,
                   inNumPackets: UInt32,
                   inPacketDesc: UnsafePointer<AudioStreamPacketDescription>?) {
    
    let recorder = UnsafeMutablePointer<Recorder>(inUserData)
    
    // if inNumPackets is greater then zero, our buffer contains audio data
    // in the format we specified (AAC)
    if inNumPackets > 0 {
        // write packets to file
        var ioNumPackets = inNumPackets
        Utility.check(error: AudioFileWritePackets(recorder!.pointee.recordFile!,
                                                   false,
                                                   inBuffer.pointee.mAudioDataByteSize,
                                                   inPacketDesc,
                                                   recorder!.pointee.recordPacket,
                                                   &ioNumPackets,
                                                   inBuffer.pointee.mAudioData),
                      operation: "AudioFileWritePackets failed")
        
        // increment packet index
        recorder!.pointee.recordPacket = recorder!.pointee.recordPacket + Int(inNumPackets)
    }
    
    // if we're not stopping, re-enqueue the buffer so that it gets filled again
    if recorder!.pointee.running {
        Utility.check(error: AudioQueueEnqueueBuffer(inQueue, inBuffer, 0, nil), operation: "AudioQueueEnqueueBuffer failed")
    }
}

var recorder = Recorder()                                               // Callback struct
var recordFormat = AudioStreamBasicDescription()                        // ASBD
var error: OSStatus = noErr                                             // error code

// Configure the output data format to be AAC
recordFormat.mFormatID = kAudioFormatMPEG4AAC
recordFormat.mChannelsPerFrame = 2

// set the output sample rate to be the same as the default input Device
Utility.check(error: setOutputSampleRate(&recordFormat.mSampleRate),
              operation: "Unable to get Sample Rate")

// ProTip: Use the AudioFormat API to trivialize ASBD creation.
//         input: at least the mFormatID, however, at this point we already have
//                mSampleRate, mFormatID, and mChannelsPerFrame
//         output: the remainder of the ASBD will be filled out as much as possible
//                 given the information known about the format
var propSize: UInt32  = UInt32(sizeof(AudioStreamBasicDescription))
Utility.check(error: AudioFormatGetProperty(kAudioFormatProperty_FormatInfo,
                                            0,
                                            nil,
                                            &propSize,
                                            &recordFormat),
              operation: "AudioFormatGetProperty failed")

// create an input (recording) queue
var queue: AudioQueueRef?
Utility.check(error: AudioQueueNewInput(&recordFormat,                  // asbd
    inputCallback,                  // callback
    &recorder,                      // user data
    nil,                            // run loop
    nil,                            // run loop mode
    0,                              // flags
    &queue),                        // input queue
    operation: "AudioQueueNewInput failed")

// since the queue is now initilized, we ask it's Audio Converter object
// for the ASBD it has configured itself with. The file may require a more
// specific stream description than was necessary to create the audio queue.
//
// for example: certain fields in an ASBD cannot possibly be known until it's
// codec is instantiated (in this case, by the AudioQueue's Audio Converter object)
var size: UInt32  = UInt32(sizeof(AudioStreamBasicDescription))
Utility.check(error: AudioQueueGetProperty(queue!,
                                           kAudioConverterCurrentOutputStreamDescription,
                                           &recordFormat,
                                           &size),
              operation: "couldn't get queue's format")

// create the audio file
guard let fileURL = CFURLCreateWithFileSystemPath(kCFAllocatorDefault, "./output.caf", .cfurlposixPathStyle, false) else {
    
    // unable to create file
    exit(-1)
}
Utility.check(error: AudioFileCreateWithURL(fileURL,
                                            kAudioFileCAFType,
                                            &recordFormat,
                                            .eraseFile,
                                            &recorder.recordFile),
              operation: "AudioFileCreateWithURL failed")

Swift.print("\(fileURL)")

// many encoded formats require a 'magic cookie'. we set the cookie first
// to give the file object as much info as we can about the data it will be receiving
Utility.applyEncoderCookie(fromQueue: queue!, toFile: recorder.recordFile!)

// allocate and enqueue buffers
let bufferByteSize = Utility.bufferSizeFor(seconds: 0.5, usingFormat: recordFormat, andQueue: queue!)
var bufferIndex = 0

// for each buffer
for bufferIndex in 0..<kNumberRecordBuffers {
    
    // allocate a buffer
    var buffer: AudioQueueBufferRef?
    Utility.check(error: AudioQueueAllocateBuffer(queue!, UInt32(bufferByteSize), &buffer),
                  operation: "AudioQueueAllocateBuffer failed")
    
    // enqueue the buffer
    Utility.check(error: AudioQueueEnqueueBuffer(queue!, buffer!, 0, nil),
                  operation: "AudioQueueEnqueueBuffer failed")
}

// start the queue. this function return immedatly and begins
// invoking the callback, as needed, asynchronously.
recorder.running = true
Utility.check(error: AudioQueueStart(queue!, nil),
              operation: "AudioQueueStart failed")

Swift.print("Recording, press <return> to stop:\n")

// wait for a key to be pressed
getchar()

// end recording
Swift.print("* recording done *\n")
recorder.running = false

// stop the Queue
Utility.check(error: AudioQueueStop(queue!, true),
              operation: "AudioQueueStop failed")

// a codec may update its magic cookie at the end of an encoding session
// so reapply it to the file now
Utility.applyEncoderCookie(fromQueue: queue!, toFile: recorder.recordFile!)

AudioQueueDispose(queue!, true)
AudioFileClose(recorder.recordFile!)

exit(0)
