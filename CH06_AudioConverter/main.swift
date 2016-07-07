//
//  main.swift
//  CH06_AudioConverter
//
//  Created by Douglas Adams on 7/5/16.
//

import AudioToolbox
import CoreServices

//--------------------------------------------------------------------------------------------------
// MARK: Global Struct

struct AudioConverterSettings
{
    var inputFormat = AudioStreamBasicDescription()                 // input file's data stream description
    var outputFormat = AudioStreamBasicDescription()                // output file's data stream description
    
    var inputFile: AudioFileID?                                     // reference to your input file
    var outputFile: AudioFileID?                                    // reference to your output file
    
    var inputFilePacketIndex: UInt64 = 0                            // current packet index in input file
    var inputFilePacketCount: UInt64 = 0                            // total number of packts in input file
    var inputFilePacketMaxSize: UInt32 = 0                          // maximum size a packet in the input file can be
    var inputFilePacketDescriptions:
                UnsafeMutablePointer<AudioStreamPacketDescription>? // array of packet descriptions for read buffer
}

//--------------------------------------------------------------------------------------------------
// MARK: Supporting methods

//
// audioConverterCallback
//
// AudioConverterComplexInputDataProc function
//
//      must have the following signature:
//          @convention(c) (AudioConverterRef,                                                          // in - reference to the Converter
//                          UnsafeMutablePointer<UInt32>,                                               // io - packet count
//                          UnsafeMutablePointer<AudioBufferList>,                                      // io - audio buffer list
//                          UnsafeMutablePointer<UnsafeMutablePointer<AudioStreamPacketDescription>?>?, // out - AudioStreamPacketDescription(s)
//                          UnsafeMutablePointer<Swift.Void>?) -> OSStatus                              // in - AudioConverterSettings
//

func audioConverterCallback(inAudioConverter: AudioConverterRef,
                            ioDataPacketCount: UnsafeMutablePointer<UInt32>,
                            ioData: UnsafeMutablePointer<AudioBufferList>,
                            outDataPacketDescription: UnsafeMutablePointer<UnsafeMutablePointer<AudioStreamPacketDescription>?>?,
                            inUserData: UnsafeMutablePointer<Void>?) -> OSStatus {
    
    // cast the inUserData Void pointer to an AudioConverterSettings struct pointer
    if let settings = UnsafeMutablePointer<AudioConverterSettings>(inUserData) {
        
        // initialize in case of failure (there will be only one buffer in the AudioBufferList)
        ioData.pointee.mBuffers.mData = nil
        ioData.pointee.mBuffers.mDataByteSize = 0
        
        // are there enough packets to satisfy request?
        if settings.pointee.inputFilePacketIndex + UInt64(ioDataPacketCount.pointee) > settings.pointee.inputFilePacketCount {
            
            // YES
            ioDataPacketCount.pointee = UInt32(settings.pointee.inputFilePacketCount - settings.pointee.inputFilePacketIndex)
        }
        // return if no packets available
        if ioDataPacketCount.pointee == 0 { return noErr }
        
        // calculate the intended size & allocate a buffer
        var outByteCount: UInt32  = ioDataPacketCount.pointee * settings.pointee.inputFilePacketMaxSize
        let sourceBuffer = calloc(1, Int(outByteCount))
        
        // read packets into the buffer
        var result = AudioFileReadPacketData(settings.pointee.inputFile!,                       // AudioFileID
            true,                                              // use cache?
            &outByteCount,                                     // initially - buffer capacity, after - bytes actually read
            settings.pointee.inputFilePacketDescriptions,      // pointer to an array of PacketDescriptors
            Int64(settings.pointee.inputFilePacketIndex),      // index of first packet to be read
            ioDataPacketCount,                                 // number of packets
            sourceBuffer)                                      // output buffer
        
        
        // did we just read the remainder of the file?
        if result == kAudioFileEndOfFileError && (ioDataPacketCount.pointee > 0) {
            
            // YES, it's not an error
            result = noErr
            
        } else if result != noErr {
            
            // some other error occurred
            return result
        }
        // update the position in the file
        settings.pointee.inputFilePacketIndex += UInt64(ioDataPacketCount.pointee)
        
        // capture the data and byte count
        ioData.pointee.mBuffers.mData = sourceBuffer
        ioData.pointee.mBuffers.mDataByteSize = outByteCount
        
        // copy over the PacketDescriptors
        outDataPacketDescription?.pointee = settings.pointee.inputFilePacketDescriptions
        
        return result
    }
    
    // nothing was done
    return noErr
}
    //
    // convert from input to output format
    //
    func Convert(settings: UnsafeMutablePointer<AudioConverterSettings>) {

        // create audioConverter object
        var audioConverter: AudioConverterRef?
        Utility.check(error: AudioConverterNew(&settings.pointee.inputFormat,
                                               &settings.pointee.outputFormat,
                                               &audioConverter),
                      operation: "AudioConveterNew failed")
        
        // allocate packet descriptions if the input file is variable-bit-rate (VBR)
        var packetsPerBuffer: UInt32  = 0
        var outputBufferSize: UInt32  = 32 * 1024                   // 32 KB is a good starting point
        var sizePerPacket: UInt32  = settings.pointee.inputFormat.mBytesPerPacket

        // is the format VBR?
        if sizePerPacket == 0 {
            
            // YES, get the packet size
            var size: UInt32  = UInt32(sizeof(UInt32))
            Utility.check(error: AudioConverterGetProperty(audioConverter!,
                                                           kAudioConverterPropertyMaximumOutputPacketSize,
                                                           &size,
                                                           &sizePerPacket),
                          operation: "Couldn't get kAudioConverterPropertyMaximumOutputPacketSize")
            
            // make sure the buffer is large enough to hold at least one packet
            if sizePerPacket > outputBufferSize { outputBufferSize = sizePerPacket }
            
            // calculate the number of packets that fit into the buffer
            packetsPerBuffer = outputBufferSize / sizePerPacket
            
            // allocate space for the AudioStreamPacketDescription(s)
            settings.pointee.inputFilePacketDescriptions = UnsafeMutablePointer<AudioStreamPacketDescription>(malloc(sizeof(AudioStreamPacketDescription) * Int(packetsPerBuffer)))
            
        }
        else
        {
            // NO, calculate the number of packets that fit into the buffer
            packetsPerBuffer = outputBufferSize / sizePerPacket
        }
        
        // allocate space for the output buffer
        let outputBuffer = malloc(Int(outputBufferSize))
        
        // loop until the convertion is complete (or an error occurs)
        var outputFilePacketPosition: UInt32  = 0                           //in bytes
        while(true)
        {
            // wrap the destination buffer in an AudioBufferList
            var convertedData = AudioBufferList()
            convertedData.mNumberBuffers = 1
            convertedData.mBuffers.mNumberChannels = settings.pointee.inputFormat.mChannelsPerFrame
            convertedData.mBuffers.mDataByteSize = outputBufferSize
            convertedData.mBuffers.mData = outputBuffer
            
            // now call the audioConverter to transcode the data. This function will call
            // the callback function as many times as required to fulfill the request.
            var ioOutputDataPackets: UInt32  = packetsPerBuffer
            let error = AudioConverterFillComplexBuffer(audioConverter!,
                                                        audioConverterCallback,
                                                        settings,
                                                        &ioOutputDataPackets,
                                                        &convertedData,
                                                        settings.pointee.inputFilePacketDescriptions)
            
            if error != noErr || ioOutputDataPackets == 0  {
                break;	// this is our termination condition
            }
            
            // write the converted data to the output file
            // KEVIN: QUESTION: 3rd arg seems like it should be a byte count, not packets. why does this work?
            Utility.check(error: AudioFileWritePackets(settings.pointee.outputFile!,
                                                       false,
                                                       ioOutputDataPackets,
                                                       nil,
                                                       Int64(outputFilePacketPosition / settings.pointee.outputFormat.mBytesPerPacket),
                                                       &ioOutputDataPackets,
                                                       convertedData.mBuffers.mData!),
                          operation: "Couldn't write packets to file")
            
            // advance the output file write location
            outputFilePacketPosition += (ioOutputDataPackets * settings.pointee.outputFormat.mBytesPerPacket)
        }
        
        // cleanup
        AudioConverterDispose(audioConverter!)
        free(outputBuffer)
}

//--------------------------------------------------------------------------------------------------
// MARK: Constants

let kInputFileLocation = CFStringCreateWithCString(kCFAllocatorDefault, "/Users/Doug/x.mp3", CFStringBuiltInEncodings.UTF8.rawValue)

//--------------------------------------------------------------------------------------------------
// MARK: Main

var audioConverterSettings = AudioConverterSettings()

// open the input audio file
let inputFileURL = CFURLCreateWithFileSystemPath(kCFAllocatorDefault, kInputFileLocation, .cfurlposixPathStyle, false)!
Utility.check(error: AudioFileOpenURL(inputFileURL,
                                      .readPermission ,
                                      0,
                                      &audioConverterSettings.inputFile),
              operation: "AudioFileOpenURL failed")

// get the audio data format from the file
var propSize: UInt32 = UInt32(sizeof(AudioStreamBasicDescription))
Utility.check(error: AudioFileGetProperty(audioConverterSettings.inputFile!,
                                          kAudioFilePropertyDataFormat,
                                          &propSize,
                                          &audioConverterSettings.inputFormat),
              operation: "couldn't get file's data format")

// get the total number of packets in the file
propSize = UInt32(sizeof(UInt64))
Utility.check(error: AudioFileGetProperty(audioConverterSettings.inputFile!,
                                          kAudioFilePropertyAudioDataPacketCount,
                                          &propSize,
                                          &audioConverterSettings.inputFilePacketCount),
              operation: "couldn't get file's packet count")

// get size of the largest possible packet
propSize = UInt32(sizeof(UInt32))
Utility.check(error: AudioFileGetProperty(audioConverterSettings.inputFile!,
                                          kAudioFilePropertyMaximumPacketSize,
                                          &propSize, &audioConverterSettings.inputFilePacketMaxSize),
              operation: "couldn't get file's max packet size")

// define the ouput format. AudioConverter requires that one of the data formats be LPCM
audioConverterSettings.outputFormat.mSampleRate = 44100.0
audioConverterSettings.outputFormat.mFormatID = kAudioFormatLinearPCM
audioConverterSettings.outputFormat.mFormatFlags = kAudioFormatFlagIsBigEndian | kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked
audioConverterSettings.outputFormat.mBytesPerPacket = 4
audioConverterSettings.outputFormat.mFramesPerPacket = 1
audioConverterSettings.outputFormat.mBytesPerFrame = 4
audioConverterSettings.outputFormat.mChannelsPerFrame = 2
audioConverterSettings.outputFormat.mBitsPerChannel = 16

// create output file (overwrites any existing file)
let outputFileURL: CFURL  = CFURLCreateWithFileSystemPath(kCFAllocatorDefault, "output.aif", .cfurlposixPathStyle, false)
Utility.check(error: AudioFileCreateWithURL(outputFileURL,
                                            kAudioFileAIFFType,
                                            &audioConverterSettings.outputFormat,
                                            .eraseFile,
                                            &audioConverterSettings.outputFile),
              operation: "AudioFileCreateWithURL failed");

Swift.print("Converting...\n")

// perform the convertion
Convert(settings: &audioConverterSettings)

// cleanup
AudioFileClose(audioConverterSettings.inputFile!)
AudioFileClose(audioConverterSettings.outputFile!)

Swift.print("Done\r")

exit(0)

