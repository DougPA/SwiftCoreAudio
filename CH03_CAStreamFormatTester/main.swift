//
//  main.swift
//  CH03_CAStreamFormatTester
//
//  Created by Douglas Adams on 6/30/16.
//

import Foundation
import AudioToolbox

func idToString(_ formatId: UInt32) -> String {
    
    var x = [UInt8](repeating: 0, count: 4)
    x[0] = UInt8(formatId & 0x000000ff)
    x[1] = UInt8( (formatId & 0x0000ff00) >> 8)
    x[2] = UInt8( (formatId & 0x00ff0000) >> 16)
    x[3] = UInt8( (formatId & 0xff000000) >> 24)
    
    return String(bytes: x, encoding: String.Encoding.utf8)!
}

var fileTypeAndFormat = AudioFileTypeAndFormatID()

fileTypeAndFormat.mFileType = kAudioFileAIFFType
fileTypeAndFormat.mFormatID = kAudioFormatLinearPCM

var audioErr: OSStatus  = noErr
var infoSize: UInt32  = 0

audioErr = AudioFileGetGlobalInfoSize(kAudioFileGlobalInfo_AvailableStreamDescriptionsForFormat,
                                      UInt32(strideof(AudioFileTypeAndFormatID)),
                                      &fileTypeAndFormat,
                                      &infoSize);

if audioErr != noErr {
    let err4cc: UInt32  = CFSwapInt32HostToBig(UInt32(audioErr))
    Swift.print(String(format: "%4.4s",  err4cc))
}

assert (audioErr == noErr)

var asbdArrayPtr: UnsafeMutablePointer<Void> = malloc(Int(infoSize))

audioErr = AudioFileGetGlobalInfo(kAudioFileGlobalInfo_AvailableStreamDescriptionsForFormat,
                                  UInt32(sizeof (AudioFileTypeAndFormatID)),
                                  &fileTypeAndFormat,
                                  &infoSize,
                                  asbdArrayPtr)

assert (audioErr == noErr)

let asbdCount: Int = Int(infoSize) / sizeof (AudioStreamBasicDescription)

for i in 0..<asbdCount {
    
    let asbdPtr = UnsafeMutablePointer<AudioStreamBasicDescription>(asbdArrayPtr.advanced(by: i * sizeof (AudioStreamBasicDescription)))
    
    let idString = idToString(CFSwapInt32HostToBig(asbdPtr.pointee.mFormatID))
    
    Swift.print("\(i): mFormatId: \(idString), mFormatFlags: \(asbdPtr.pointee.mFormatFlags), mBitsPerChannel: \(asbdPtr.pointee.mBitsPerChannel)")
}

free (asbdArrayPtr);

exit(0)

