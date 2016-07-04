//
//  Utility.swift
//  CH04_Recorder
//
//  Created by Douglas Adams on 6/30/16.
//

import Foundation
import AudioToolbox

class Utility {
    //
    // convert a Core Audio error code to a printable string
    //
    static func codeToString(_ error: OSStatus) -> String {
        
        let x = UInt32(bitPattern: error)
        
        // byte swap the error
        let errorCode = CFSwapInt32HostToBig(x)
        
        // separate the UInt32 into 4 bytes
        var bytes = [UInt8](repeating: 0, count: 4)
        bytes[0] = UInt8(errorCode & 0x000000ff)
        bytes[1] = UInt8( (errorCode & 0x0000ff00) >> 8)
        bytes[2] = UInt8( (errorCode & 0x00ff0000) >> 16)
        bytes[3] = UInt8( (errorCode & 0xff000000) >> 24)
        
        // do the four bytes all represent printable characters?
        if isprint(Int32(bytes[0])) != 0 && isprint(Int32(bytes[1])) != 0 &&
            isprint(Int32(bytes[2])) != 0 && isprint(Int32(bytes[3])) != 0 {
            
            // YES, return a String made from them
            return String(bytes: bytes, encoding: String.Encoding.ascii)!
            
        } else {
            
            // NO, treat the UInt32 as a number and create a String of the number
            return String(format: "%d", error)
        }
    }
    //
    // generic error handler - if error is nonzero, prints error message and exits program.
    //
    static func check(error: OSStatus , operation: String) {
    
        // return if no error
        if error == noErr { return }
        
        // print either four characters or the numeric value
        Swift.print("Error: \(operation), returned: \(codeToString(error))")
        
        // terminate the program
        exit(1)
    }
    //
    // Determine the size, in bytes, of a buffer necessary to represent the supplied number
    //      of seconds of audio data
    //
    static func bufferSizeFor(seconds: Float, usingFormat format: AudioStreamBasicDescription, andQueue queue: AudioQueueRef ) -> Int {
        var packets = 0
        var frames = 0
        var bytes = 0
    
        // rounding up, calc the number of frames in the given time
        frames = Int(ceil(Double(seconds) * format.mSampleRate))
    
        // is this a constant bit rate format?
        if format.mBytesPerFrame > 0 {
            // YES, calc the number of bytes
            bytes = frames * Int(format.mBytesPerFrame)
        
        } else {
            // NO
            var maxPacketSize: UInt32 = 0
            
            // is this a constant Packet size?
            if format.mBytesPerPacket > 0 {
                // YES,
                maxPacketSize = format.mBytesPerPacket
            
            } else {
                // NO, get the largest single packet size possible
                var propertySize: UInt32 = 4
                maxPacketSize = 4
                
                // ask for the max packet size
                check(error: AudioQueueGetProperty(queue, kAudioConverterPropertyMaximumOutputPacketSize, &maxPacketSize, &propertySize), operation: "couldn't get queue's maximum output packet size")
            }
            
            // do we have a frames per packet?
            if format.mFramesPerPacket > 0 {
                // YES
                packets = frames / Int(format.mFramesPerPacket)
            
            } else {
                // NO, worst-case scenario: 1 frame in a packet
                packets = frames
            }
            // sanity check (just in case)
            if packets == 0 { packets = 1 }
            
            // calc the number of bytes
            bytes = packets * Int(maxPacketSize)
        }
        return bytes
    }
    //
    // Copy a queue's encoder's magic cookie to an audio file.
    //
    static func applyEncoderCookie(fromQueue queue: AudioQueueRef, toFile file: AudioFileID) {
        var propertySize: UInt32 = 0
    
        // get the magic cookie, if any, from the queue's converter
        let result: OSStatus  = AudioQueueGetPropertySize(queue, kAudioConverterCompressionMagicCookie, &propertySize)
        
        // is there a cookie?
        if result == noErr && propertySize > 0 {
            
            // YES, allocate space for it
            let magicCookie = malloc(Int(propertySize))!
            
            // get the cookie
            check(error: AudioQueueGetProperty(queue, kAudioQueueProperty_MagicCookie, magicCookie, &propertySize), operation: "get audio queue's magic cookie")
    
            // now set the magic cookie on the output file
            check(error: AudioFileSetProperty(file, kAudioFilePropertyMagicCookieData, propertySize, magicCookie), operation: "set audio file's magic cookie")
    
            // release the space
            free(magicCookie);
        }
    }

}
