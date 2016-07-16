//
//  main.swift
//  CH06_ExtAudioFileConverter
//
//  Created by Douglas Adams on 7/15/16.
//

import AudioToolbox

//--------------------------------------------------------------------------------------------------
// MARK: Struct definition

struct AudioConverterSettings
{
    var outputFormat = AudioStreamBasicDescription()    // output file's data stream description
    var inputFile: ExtAudioFileRef?                     // reference to your input file
    var outputFile: AudioFileID?                        // reference to your output file
}

//--------------------------------------------------------------------------------------------------
// MARK: Supporting methods

//
//
//
func Convert(mySettings: UnsafeMutablePointer<AudioConverterSettings>) {
    
    let outputBufferSize: UInt32  = 32 * 1024           // 32 KB is a good starting point
    let sizePerPacket: UInt32  = mySettings.pointee.outputFormat.mBytesPerPacket
    let packetsPerBuffer: UInt32  = outputBufferSize / sizePerPacket
    
    // allocate destination buffer
    let outputBuffer = malloc(sizeof(UInt8.self) * Int(outputBufferSize))
    
    var outputFilePacketPosition: UInt32 = 0            //in bytes
    while(true)
    {
        // wrap the destination buffer in an AudioBufferList
        var convertedData = AudioBufferList()
        convertedData.mNumberBuffers = 1
        convertedData.mBuffers.mNumberChannels = mySettings.pointee.outputFormat.mChannelsPerFrame
        convertedData.mBuffers.mDataByteSize = outputBufferSize
        convertedData.mBuffers.mData = outputBuffer
        
        var frameCount: UInt32  = packetsPerBuffer
        
        // read from the extaudiofile
        Utility.check(error: ExtAudioFileRead(mySettings.pointee.inputFile!,
                                              &frameCount,
                                              &convertedData),
                      operation: "Couldn't read from input file")
        
        if frameCount == 0 {
            Swift.print("done reading from file")
            return
        }
        
        // write the converted data to the output file
        Utility.check(error: AudioFileWritePackets(mySettings.pointee.outputFile!,
                                                   false,
                                                   frameCount,
                                                   nil,
                                                   Int64(outputFilePacketPosition / mySettings.pointee.outputFormat.mBytesPerPacket),
                                                   &frameCount,
                                                   convertedData.mBuffers.mData!),
                     operation: "Couldn't write packets to file")
        
        // advance the output file write location
        outputFilePacketPosition += (frameCount * mySettings.pointee.outputFormat.mBytesPerPacket)
    }
}

//--------------------------------------------------------------------------------------------------
// MARK: Properties

let kInputFileLocation = CFStringCreateWithCString(kCFAllocatorDefault, "/Users/Doug/x.mp3", CFStringBuiltInEncodings.UTF8.rawValue)
let kOutputFileLocation = CFStringCreateWithCString(kCFAllocatorDefault, "/Users/Doug/x.aif", CFStringBuiltInEncodings.UTF8.rawValue)

//--------------------------------------------------------------------------------------------------
// MARK: Main

var audioConverterSettings = AudioConverterSettings()

// open the input with ExtAudioFile
let inputFileURL = CFURLCreateWithFileSystemPath(kCFAllocatorDefault, kInputFileLocation, .cfurlposixPathStyle, false)
Utility.check(error: ExtAudioFileOpenURL(inputFileURL!,
                                         &audioConverterSettings.inputFile),
              operation: "ExtAudioFileOpenURL failed")

// define the ouput format. AudioConverter requires that one of the data formats be LPCM
audioConverterSettings.outputFormat.mSampleRate = 44100.0
audioConverterSettings.outputFormat.mFormatID = kAudioFormatLinearPCM
audioConverterSettings.outputFormat.mFormatFlags = kAudioFormatFlagIsBigEndian | kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked
audioConverterSettings.outputFormat.mBytesPerPacket = 4
audioConverterSettings.outputFormat.mFramesPerPacket = 1
audioConverterSettings.outputFormat.mBytesPerFrame = 4
audioConverterSettings.outputFormat.mChannelsPerFrame = 2
audioConverterSettings.outputFormat.mBitsPerChannel = 16

    // create output file
let outputFileURL = CFURLCreateWithFileSystemPath(kCFAllocatorDefault, kOutputFileLocation, .cfurlposixPathStyle, false)!
Utility.check(error: AudioFileCreateWithURL(outputFileURL,
                                            kAudioFileAIFFType,
                                            &audioConverterSettings.outputFormat,
                                            .eraseFile,
                                            &audioConverterSettings.outputFile),
              operation: "AudioFileCreateWithURL failed")

// set the PCM format as the client format on the input ext audio file
Utility.check(error: ExtAudioFileSetProperty(audioConverterSettings.inputFile!,
                                             kExtAudioFileProperty_ClientDataFormat,
                                             UInt32(sizeof (AudioStreamBasicDescription.self)),
                                             &audioConverterSettings.outputFormat),
              operation: "Couldn't set client data format on input ext file")

Swift.print("Converting...\n")

Convert(mySettings: &audioConverterSettings)

// cleanup
AudioFileClose(audioConverterSettings.inputFile!)
ExtAudioFileDispose(audioConverterSettings.inputFile!)
AudioFileClose(audioConverterSettings.outputFile!)

exit(0)
