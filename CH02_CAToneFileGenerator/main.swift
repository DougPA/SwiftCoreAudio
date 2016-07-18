//
//  main.swift
//  CH02_CAToneFileGenerator
//
//  Created by Douglas Adams on 6/29/16.
//

import Foundation
import AudioToolbox

//--------------------------------------------------------------------------------------------------
// MARK: Properties

let kSampleRate: Double = 44100.0
let kDuration: Double = 5.0
//let kFilenameFormat = "%0.3f-square.aif"
//let kFilenameFormat = "%0.3f-saw.aif"
let kFilenameFormat = "%0.3f-sine.aif"
let kMinValue: UInt16 = 0x8000
let kMaxValue: UInt16 = 0x7fff

//--------------------------------------------------------------------------------------------------
// MARK: Main

// if command line argument missing, show usage
if Process.arguments.count < 2 {
    Swift.print("Usage: CAToneFileGenerator n (where n is tone in Hz)")
    exit(-1)
}

// make the command line argument into a Double (check for 0)
var tone: Double = atof(Process.arguments[1])
assert (tone > 0)

Swift.print("generating \(tone) hz tone")

// convert the file path into a URL
let fileName = String(format: kFilenameFormat, tone)
let filePath = NSString(string: FileManager.default.currentDirectoryPath).appendingPathComponent( fileName)
let fileURL = URL(fileURLWithPath: filePath)

Swift.print("path: \(fileURL)")

// prepare the format (an Audio Stream Basic Description)
var asbd: AudioStreamBasicDescription? = AudioStreamBasicDescription()
asbd!.mSampleRate = kSampleRate
asbd!.mFormatID = kAudioFormatLinearPCM
asbd!.mFormatFlags = kAudioFormatFlagIsBigEndian | kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked
asbd!.mChannelsPerFrame = 1
asbd!.mFramesPerPacket = 1
asbd!.mBitsPerChannel = 16
asbd!.mBytesPerFrame = 2
asbd!.mBytesPerPacket = 2

// create the file using the URL
var audioFile: AudioFileID?
var audioErr: OSStatus = noErr
audioErr = AudioFileCreateWithURL(fileURL, UInt32(kAudioFileAIFFType), &asbd!, .eraseFile, &audioFile)
assert (audioErr == noErr);

var maxSampleCount = CLong(kSampleRate * kDuration)
var sampleCount = 0
var bytesToWrite: UInt32 = 2
var wavelengthInSamples = kSampleRate / tone

Swift.print("wavelengthInSamples = \(wavelengthInSamples)")

// start writing samples to the file
while sampleCount < maxSampleCount {
    for i in 0..<Int(wavelengthInSamples){
        
        //        // generate a Square Wave
        //        var sample:Int16 = i < Int(wavelengthInSamples) / 2 ? Int16.max : Int16.min
        
        //        // generate a Sawtooth Wave
        //        var sample = Int16(((Double(i) / wavelengthInSamples) * Double(Int16.max) * 2) - Double(Int16.max))
        
        // generate a Sin Wave
        var sample = Int16(Double(Int16.max) * sin(2 * M_PI * (Double(i) / wavelengthInSamples)))
        
        audioErr = AudioFileWriteBytes(audioFile!, false, Int64(sampleCount * 2), &bytesToWrite, &sample)
        
        sampleCount += 1
    }
}

// Close the file
audioErr = AudioFileClose(audioFile!)
assert (audioErr == noErr)

Swift.print("wrote \(sampleCount) samples")

exit(0)
