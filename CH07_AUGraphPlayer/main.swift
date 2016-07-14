//
//  main.swift
//  CH07_AUGraphPlayer
//
//  Created by Douglas Adams on 7/14/16.
//

import AudioToolbox


//
// NOTE: This is needed because (apparently) the initializer for ScheduledAudioFileRegion is currently missing in Swift 3
//
public extension ScheduledAudioFileRegion {
    
    init(mTimeStamp: AudioTimeStamp, mCompletionProc: ScheduledAudioFileRegionCompletionProc?, mCompletionProcUserData: UnsafeMutablePointer<Void>?, mAudioFile: OpaquePointer, mLoopCount: UInt32, mStartFrame: Int64, mFramesToPlay: UInt32) {
        
        self.mTimeStamp = mTimeStamp
        self.mCompletionProc = mCompletionProc
        self.mCompletionProcUserData = mCompletionProcUserData
        self.mAudioFile = mAudioFile
        self.mLoopCount = mLoopCount
        self.mStartFrame = mStartFrame
        self.mFramesToPlay = mFramesToPlay
    }
}

//--------------------------------------------------------------------------------------------------
// MARK: Struct definition

struct AUGraphPlayer
{
    var inputFormat = AudioStreamBasicDescription() // input file's data stream description
    var inputFile: AudioFileID?                     // Opaque pointer to the input file's AudioFileID
    var graph: AUGraph?                             // Opaque pointer to the AUGraph
    var fileAU: AudioUnit?                          // pointer to a ComponentInstanceRecord
}

//--------------------------------------------------------------------------------------------------
// MARK: Supporting methods

//
// create and setup the AUGraph
//
func CreateAUGraph(player: UnsafeMutablePointer<AUGraphPlayer>)
{
    // create a new AUGraph
    Utility.check( error: NewAUGraph(&player.pointee.graph),
                   operation: "NewAUGraph failed")
    
    // generate description that will match out output device (speakers)
    var outputCd = AudioComponentDescription()
    outputCd.componentType = kAudioUnitType_Output
    outputCd.componentSubType = kAudioUnitSubType_DefaultOutput
    outputCd.componentManufacturer = kAudioUnitManufacturer_Apple
    
    // adds a node with above description to the graph
    var outputNode = AUNode()
    Utility.check( error: AUGraphAddNode(player.pointee.graph!,
                                         &outputCd,
                                         &outputNode),
                   operation: "AUGraphAddNode[kAudioUnitSubType_DefaultOutput] failed")
    
    // generate description that will match a generator AU of type: audio file player
    var fileplayerCd = AudioComponentDescription()
    fileplayerCd.componentType = kAudioUnitType_Generator
    fileplayerCd.componentSubType = kAudioUnitSubType_AudioFilePlayer
    fileplayerCd.componentManufacturer = kAudioUnitManufacturer_Apple
    
    // adds a node with above description to the graph
    var fileNode = AUNode()
    Utility.check( error: AUGraphAddNode(player.pointee.graph!,
                                         &fileplayerCd,
                                         &fileNode),
               operation: "AUGraphAddNode[kAudioUnitSubType_AudioFilePlayer] failed")
    
    // opening the graph opens all contained audio units but does not allocate any resources yet
    Utility.check( error: AUGraphOpen(player.pointee.graph!),
               operation: "AUGraphOpen failed")
    
    // get the reference to the AudioUnit object for the file player graph node
    Utility.check( error: AUGraphNodeInfo(player.pointee.graph!,
                                          fileNode,
                                          nil,
                                          &player.pointee.fileAU),
               operation: "AUGraphNodeInfo failed")

    // connect the output source of the file player AU to the input source of the output node
    Utility.check( error: AUGraphConnectNodeInput(player.pointee.graph!,
                                                  fileNode,
                                                  0,
                                                  outputNode,
                                                  0),
               operation: "AUGraphConnectNodeInput")
    
    // now initialize the graph (causes resources to be allocated)
    Utility.check( error: AUGraphInitialize(player.pointee.graph!),
               operation: "AUGraphInitialize failed")
}
//
// configure the Player
//
func PrepareFileAU(player: UnsafeMutablePointer<AUGraphPlayer>) -> Double
{
    
    // tell the file player unit to load the file we want to play
    Utility.check( error: AudioUnitSetProperty(player.pointee.fileAU!,
                                               kAudioUnitProperty_ScheduledFileIDs,
                                               kAudioUnitScope_Global,
                                               0,
                                               &player.pointee.inputFile,
                                               UInt32(sizeof(AudioFileID))),
               operation: "AudioUnitSetProperty[kAudioUnitProperty_ScheduledFileIDs] failed")
    
    var nPackets: UInt64 = 0
    var propsize  = UInt32(sizeof(UInt64))
    Utility.check( error: AudioFileGetProperty(player.pointee.inputFile!,
                                               kAudioFilePropertyAudioDataPacketCount,
                                               &propsize,
                                               &nPackets),
                   operation: "AudioFileGetProperty[kAudioFilePropertyAudioDataPacketCount] failed")
    
    
    
    // tell the file player AU to play the entire file
    let timeStamp = AudioTimeStamp(mSampleTime: 0, mHostTime: 0, mRateScalar: 0, mWordClockTime: 0, mSMPTETime: SMPTETime(), mFlags: .sampleTimeValid, mReserved: 0)
    var rgn = ScheduledAudioFileRegion(mTimeStamp: timeStamp, mCompletionProc: nil, mCompletionProcUserData: nil, mAudioFile: player.pointee.inputFile!, mLoopCount: 1, mStartFrame: 0, mFramesToPlay: UInt32(nPackets) * player.pointee.inputFormat.mFramesPerPacket)
    
    Utility.check( error: AudioUnitSetProperty(player.pointee.fileAU!,
                                               kAudioUnitProperty_ScheduledFileRegion,
                                               kAudioUnitScope_Global,
                                               0,
                                               &rgn,
                                               UInt32(sizeof(ScheduledAudioFileRegion))),
                   operation: "AudioUnitSetProperty[kAudioUnitProperty_ScheduledFileRegion] failed")
    
    // prime the file player AU with default values
    var defaultVal: UInt32  = 0
    Utility.check( error: AudioUnitSetProperty(player.pointee.fileAU!,
                                               kAudioUnitProperty_ScheduledFilePrime,
                                               kAudioUnitScope_Global,
                                               0,
                                               &defaultVal,
                                               UInt32(sizeof(UInt32))),
                   operation: "AudioUnitSetProperty[kAudioUnitProperty_ScheduledFilePrime] failed")
    
    // tell the file player AU when to start playing (-1 sample time means next render cycle)
    var startTime = AudioTimeStamp(mSampleTime: -1, mHostTime: 0, mRateScalar: 0, mWordClockTime: 0, mSMPTETime: SMPTETime(), mFlags: .sampleTimeValid, mReserved: 0)
    Utility.check( error: AudioUnitSetProperty(player.pointee.fileAU!,
                                               kAudioUnitProperty_ScheduleStartTimeStamp,
                                               kAudioUnitScope_Global,
                                               0,
                                               &startTime,
                                               UInt32(sizeof(AudioTimeStamp))),
                   operation: "AudioUnitSetProperty[kAudioUnitProperty_ScheduleStartTimeStamp]")
    
    // file duration
    return Double( UInt32(nPackets) * player.pointee.inputFormat.mFramesPerPacket) / player.pointee.inputFormat.mSampleRate
}

//--------------------------------------------------------------------------------------------------
// MARK: Properties

let kInputFileLocation = CFStringCreateWithCString(kCFAllocatorDefault, "/Users/Doug/x.mp3", CFStringBuiltInEncodings.UTF8.rawValue)

//--------------------------------------------------------------------------------------------------
// MARK: Main

let inputFileURL: CFURL  = CFURLCreateWithFileSystemPath(kCFAllocatorDefault, kInputFileLocation, .cfurlposixPathStyle, false)
var player = AUGraphPlayer()

// open the input audio file
Utility.check( error: AudioFileOpenURL(inputFileURL,
                                       .readPermission,
                                       0,
                                       &player.inputFile),
               operation: "AudioFileOpenURL failed")

// get the audio data format from the file
var propSize  = UInt32(sizeof(AudioStreamBasicDescription))
Utility.check( error: AudioFileGetProperty(player.inputFile!,
                                           kAudioFilePropertyDataFormat,
                                           &propSize,
                                           &player.inputFormat),
               operation: "couldn't get file's data format")

// build a basic fileplayer->speakers graph
CreateAUGraph(player: &player)

// configure the file player
var fileDuration: Float64  = PrepareFileAU(player: &player)

// start playing
Utility.check( error: AUGraphStart(player.graph!),
               operation: "AUGraphStart failed")

// sleep until the file is finished
usleep(useconds_t(fileDuration * 1000.0 * 1000.0))

// cleanup
AUGraphStop (player.graph!)
AUGraphUninitialize (player.graph!)
AUGraphClose(player.graph!)
AudioFileClose(player.inputFile!)

exit(0)
