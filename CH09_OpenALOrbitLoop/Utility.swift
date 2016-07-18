//
//  Utility.swift
//  CH09_OpenALOrbitLoop
//
//  Created by Douglas Adams on 6/30/16.
//

import Foundation
import OpenAL

class Utility {
    //
    // convert a Core Audio error code to a printable string
    //
    static func codeToString(_ error: OSStatus) -> String {
        
        // byte swap the error
        let errorCode = CFSwapInt32HostToBig(UInt32(bitPattern: error))

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
    // OpenAL error handler
    //
    static func checkAL(operation: String) {
        
        let alErr = alGetError()
        
        if alErr == AL_NO_ERROR { return }
    
    var errFormat = ""
    switch alErr {
    case AL_INVALID_NAME:
        errFormat = "OpenAL Error: AL_INVALID_NAME"
    case AL_INVALID_VALUE:
        errFormat = "OpenAL Error: AL_INVALID_VALUE"
    case AL_INVALID_ENUM:
        errFormat = "OpenAL Error: AL_INVALID_ENUM"
    case AL_INVALID_OPERATION:
        errFormat = "OpenAL Error: AL_INVALID_OPERATION"
    case AL_OUT_OF_MEMORY:
        errFormat = "OpenAL Error: AL_OUT_OF_MEMORY"
    default:
        errFormat = "OpenAL Error: unknown error"
    }
    
    Swift.print("\(errFormat), \(operation)")
        
    exit(1)
    
    }
}
