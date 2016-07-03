//
//  main.swift
//  CH01_CAMetadata
//
//  Created by Douglas Adams on 6/28/16.
//

import CoreFoundation
import AudioToolbox

if Process.arguments.count < 2 {
    Swift.print("Usage: CAMetadata /full/path/to/audiofile\n")
    exit(-1)
}


var audioFile: AudioFileID?
var theErr: OSStatus = noErr
var dictionarySize: UInt32 = 0
var isWritable: UInt32 = 0
var dictionary: CFDictionary = [:]

let audioFilePath = (Process.arguments[1] as NSString).expandingTildeInPath

Swift.print("audioFilePath = \(audioFilePath)")

let audioURL = URL(fileURLWithPath: audioFilePath as String)

Swift.print("audioURL: \(audioURL)")

theErr = AudioFileOpenURL(audioURL, .readPermission, 0, &audioFile)

assert (theErr == noErr)

theErr = AudioFileGetPropertyInfo(audioFile!, kAudioFilePropertyInfoDictionary,  &dictionarySize, &isWritable)

assert (theErr == noErr)

theErr = AudioFileGetProperty(audioFile!, kAudioFilePropertyInfoDictionary, &dictionarySize, &dictionary)

assert (theErr == noErr)

Swift.print("dictionary: \(dictionary)")

theErr = AudioFileClose(audioFile!)

assert (theErr == noErr)
