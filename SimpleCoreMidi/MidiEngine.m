//
//  MidiEngine.m
//  SimpleCoreMidi
//
//  Created by Thierry Sansaricq on 8/18/15.
//  Copyright (c) 2015 Thierry Sansaricq. All rights reserved.
//

#import "MidiEngine.h"

/*
C prototypes
 */

#pragma mark - state struct
typedef struct MyMIDIPlayer {
    AUGraph		graph;
    AudioUnit	instrumentUnit;
    MusicPlayer musicPlayer;
} MyMIDIPlayer;


void MyMIDINotifyProc (const MIDINotification  *message, void *refCon);
static void MyMIDIReadProc(const MIDIPacketList *pktlist,
                           void *refCon,
                           void *connRefCon);



@interface MidiEngine() {
    
}

@end


#pragma mark MidiEngine implementation

@implementation MidiEngine


//MusicSequence       _musicSequence;
//MusicPlayer         _musicPlayer;
MIDIEndpointRef     _virtualEndpoint;

@synthesize processingGraph     = _processingGraph;
@synthesize samplerUnit         = _samplerUnit;
@synthesize ioUnit              = _ioUnit;
@synthesize graphSampleRate     = _graphSampleRate;
@synthesize musicSequence       = _musicSequence;
@synthesize musicPlayer         = _musicPlayer;


- (instancetype)init
{
    if (self = [super init]) {

        if(![self initAVAudioSession]){
            return nil;
        }
        
        if(![self createAUGraph]){
            return nil;
        }
        
        
        //Configure AUGraph
        if(![self configureAUGraph: self.processingGraph]){
            NSLog(@"Error configuring AUGraph");
            return nil;
        }
        
        
        
        //Initialize Audio Processing Graph
        //Start Audio Processing Graph
        if(![self activateGraph: self.processingGraph]){
            NSLog(@"Error initializing AUGraph");
            return nil;
            
        }
        
        
        CAShow(self.processingGraph);
        
        if(![self createVirtualMidiRef]){
            NSLog(@"Error Creating Virtual Midi Endpoint");
            return nil;
        }
        
        if(![self createMusicSequence]){
            NSLog(@"Error creating Music Sequence!");
            return nil;
        }
        
  
        if(![self loadSoundBank]){
            NSLog(@"Error creating Music Player!");
            return nil;
        }
        
        //[self playSequence];
        
    }
    
        
    return self;
    

}

- (void)destroy{
    
    OSStatus result = noErr;
    
    if(self.musicPlayer){
        
        result = MusicPlayerStop(self.musicPlayer);
        
        UInt32 trackCount;
        MusicSequenceGetTrackCount(_musicSequence, &trackCount);
         
        NSLog(@"Numtracks to dispose: %d", trackCount);
        MusicTrack track;
        for(int i=0;i<trackCount;i++){
            MusicSequenceGetIndTrack (_musicSequence, i, &track);
            result = MusicSequenceDisposeTrack(_musicSequence, track);
        }
        
        MusicPlayerSetTime(self.musicPlayer, 0);
        MusicPlayerSetSequence(self.musicPlayer, nil);
        result = DisposeMusicPlayer(self.musicPlayer);
        if (result == noErr) {
            self.musicPlayer = nil;
        }
        else{
            NSLog(@"Could not dispose of music player: %d", result);
        }
    }
    
    if(self.musicSequence){
        result = DisposeMusicSequence(self.musicSequence);
        self.musicSequence = nil;
       
    }
    
    if(self.processingGraph){
        result = DisposeAUGraph(self.processingGraph);
        self.processingGraph = nil;
    }
    
    
}


#pragma mark AVAudioSession

- (BOOL)initAVAudioSession
{
    // For complete details regarding the use of AVAudioSession see the AVAudioSession Programming Guide
    // https://developer.apple.com/library/ios/documentation/Audio/Conceptual/AudioSessionProgrammingGuide/Introduction/Introduction.html
    
    // Configure the audio session
    AVAudioSession *sessionInstance = [AVAudioSession sharedInstance];
    NSError *error;
    
    // set the session category
    bool success = [sessionInstance setCategory:AVAudioSessionCategoryPlayback error:&error];
    if (!success){
        NSLog(@"Error setting AVAudioSession category! %@\n", [error localizedDescription]);
        return NO;
    }
    
    //double hwSampleRate = 44100.0;
    // Request a desired hardware sample rate.
    self.graphSampleRate = 44100.0;    // Hertz
    
    success = [sessionInstance setPreferredSampleRate:self.graphSampleRate error:&error];
    if (!success){ NSLog(@"Error setting preferred sample rate! %@\n", [error localizedDescription]);
        return NO;
    }
    
    NSTimeInterval ioBufferDuration = 0.0029;
    success = [sessionInstance setPreferredIOBufferDuration:ioBufferDuration error:&error];
    if (!success) {
        NSLog(@"Error setting preferred io buffer duration! %@\n", [error localizedDescription]);
        return NO;
    }
    
    
    // add interruption handler
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleInterruption:)
                                                 name:AVAudioSessionInterruptionNotification
                                               object:sessionInstance];
    
    // we don't do anything special in the route change notification
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleRouteChange:)
                                                 name:AVAudioSessionRouteChangeNotification
                                               object:sessionInstance];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleMediaServicesReset:)
                                                 name:AVAudioSessionMediaServicesWereResetNotification
                                               object:sessionInstance];
    
    
    // activate the audio session
    success = [sessionInstance setActive:YES error:&error];
    if (!success){ NSLog(@"Error setting session active! %@\n", [error localizedDescription]);
        return NO;
    }
    
    self.graphSampleRate = [sessionInstance sampleRate];
    
    return YES;
}


//create an audio processing graph
- (BOOL) createAUGraph {
    
    OSStatus result = noErr;
    AUNode samplerNode, ioNode;
    
    //Instantiate Audio processing graph
    result = NewAUGraph(&_processingGraph);
    if(result != noErr){
        NSLog(@"Could not create AUGraph!");
        return NO;
    }

    
    //common audio component description object
    AudioComponentDescription cd = {};
    cd.componentManufacturer    = kAudioUnitManufacturer_Apple;
    cd.componentFlags           = 0;
    cd.componentFlagsMask       = 0;
    
    //sampler
    cd.componentType            = kAudioUnitType_MusicDevice;
    cd.componentSubType         = kAudioUnitSubType_Sampler;
    
    
    //add sampler unit node to the graph
    result = AUGraphAddNode(self.processingGraph, &cd, &samplerNode);
    if(result != noErr){
        NSLog(@"Could not add sampler node to graph!");
        return NO;
    }
    
    //output unit
    //configuration first
    cd.componentType = kAudioUnitType_Output;
    cd.componentSubType = kAudioUnitSubType_RemoteIO;
    
    result = AUGraphAddNode(self.processingGraph, &cd, &ioNode);
    if(result != noErr){
        NSLog(@"Could not add output node to graph!");
        return NO;
    }
    
    //open the graph
    result = AUGraphOpen(self.processingGraph);
    if(result != noErr){
        NSLog(@"Could not open graph!");
        return NO;
    }
    
    //connect the sampler node to the output node
    result = AUGraphConnectNodeInput(self.processingGraph, samplerNode, 0, ioNode, 0);
    if(result != noErr){
        NSLog(@"Could not connect sampler node to output node!");
        return NO;
    }
    
    //capture reference to sampler unit from its node
    result = AUGraphNodeInfo(self.processingGraph, samplerNode, 0, &_samplerUnit);
    if(result != noErr){
        NSLog(@"Could not capture reference to sampler unit from its node!");
        return NO;
    }
    
    result = AUGraphNodeInfo(self.processingGraph, ioNode, 0, &_ioUnit);
    if(result != noErr){
        NSLog(@"Could not capture reference to output unit from its node!");
        return NO;
    }
    
    
    return YES;
    
}



- (BOOL) configureAUGraph: (AUGraph) graph{
    
    OSStatus result = noErr;
    
    
    /*
     Apparently, it's unnecessary to set the sampleRate and Frames
     for the ioUnit and samplerUnit.
     Removing for now...
     */
    /*
    UInt32 framesPerSlice = 0;
    UInt32 framesPerSlicePropertySize = sizeof (framesPerSlice);
    UInt32 sampleRatePropertySize = sizeof (self.graphSampleRate);
    */
    
    // Initialize Audio Units
    
    //ioUnit first
    result = AudioUnitInitialize(self.ioUnit);
    if(result != noErr){
        NSLog(@"Could not initialize ioUnit! Error code: %d '%.4s'", (int) result, (const char *)&result);
        return NO;
    }
    
    
    
    /*
     Apparently, it's unnecessary to set the sampleRate and Frames
     for the ioUnit and samplerUnit.
     Removing for now...
     */
    
    /*
     
    //set the output unit's output sample rate to value of graphSampleRate
    result = AudioUnitSetProperty(self.ioUnit, kAudioUnitProperty_SampleRate, kAudioUnitScope_Output, 0, &_graphSampleRate, sampleRatePropertySize);
    if(result != noErr){
        NSLog(@"Could not set ioUnit Sample Rate to %f!  Error code: %d '%.4s'", self.graphSampleRate, (int) result, (const char *)&result);
        return NO;
    }
    
    //retrieve the value of maximum frames per slice from the output unit
    result = AudioUnitGetProperty(self.ioUnit, kAudioUnitProperty_MaximumFramesPerSlice, kAudioUnitScope_Global, 0, &framesPerSlice, &framesPerSlicePropertySize);
    if(result != noErr){
        NSLog(@"Could not retrieve value of max frame per slice from output unit! Error code: %d '%.4s'", (int) result, (const char *)&result);
        return NO;
    }
    
    
    */
    
    result = AudioUnitInitialize(self.samplerUnit);
    if(result != noErr){
        NSLog(@"Could not initialize samplerUnit! Error code: %d '%.4s'", (int) result, (const char *)&result);
        return NO;
    }
    
    
    /*
    //set the sampler unit's output sample rate property
    result = AudioUnitSetProperty(self.samplerUnit, kAudioUnitProperty_SampleRate, kAudioUnitScope_Output, 0, &_graphSampleRate, sampleRatePropertySize);
    if(result != noErr){
        NSLog(@"Could not set output sample rate on sampler unit! Error code: %d '%.4s'", (int) result, (const char *)&result);
        return NO;
    }
    
    //set the sampler unit's max frames per slice property
    result = AudioUnitSetProperty(self.samplerUnit, kAudioUnitProperty_MaximumFramesPerSlice, kAudioUnitScope_Global, 0, &framesPerSlice, framesPerSlicePropertySize);
    if(result != noErr){
        NSLog(@"Could not set max frames per slice on sampler unit! Error code: %d '%.4s'", (int) result, (const char *)&result);
        return NO;
    }
     */
    
    return YES;
}


- (BOOL) activateGraph: (AUGraph) graph{
    
    OSStatus result = noErr;
    
    result = AUGraphInitialize(graph);
    if(result != noErr){
        NSLog(@"Could not initialize AUGraph! Error code: %d '%.4s'", (int) result, (const char *)&result);
        return NO;
    }
    
    result = AUGraphStart(graph);
    if(result != noErr){
        NSLog(@"Could not start AUGraph! Error code: %d '%.4s'", (int) result, (const char *)&result);
        return NO;
    }
    
    return YES;
}


- (BOOL)createMusicSequence{
    
    //from
    //http://www.deluge.co/?q=midi-driven-animation-core-audio-objective-c
    
    NSURL *midiFileURL;
    @try {
        midiFileURL = [NSURL fileURLWithPath:[[NSBundle mainBundle] pathForResource:@"Bee_Gees_-_Jive_Talkin'" ofType:@"mid"]];
    }
    @catch (NSException *exception) {
        /*
         Handle an exception thrown in the @try block
         */
        NSLog(@"Exception thrown loading midi file %@", [exception reason]);
        return NO;
    }
    @finally {
        /*
         Code that gets executed whether or not an exception is thrown
         */
    }
    
    
    NewMusicSequence(&(_musicSequence));
    
    OSStatus status = MusicSequenceFileLoad(_musicSequence, (__bridge CFURLRef)(midiFileURL), kMusicSequenceFile_MIDIType, kMusicSequenceLoadSMF_ChannelsToTracks);
    
    
    NSLog(@"Sequence load status: %d", (int)status);
    if(status != noErr){
        NSLog(@"Could not load midi file!");
        return NO;
    }
    
    //MusicSequenceSetAUGraph(_musicSequence, self.processingGraph);
    MusicSequenceSetMIDIEndpoint(_musicSequence, _virtualEndpoint);


    
    UInt32 numTracks = 0;
    MusicSequenceGetTrackCount(_musicSequence, &numTracks);
    NSLog(@"Numtracks in sequence: %d", numTracks);
    
    
    
    /*
     
     // Create a new music player
     MusicPlayer  p;
     // Initialise the music player
     NewMusicPlayer(&p);
     
     // Load the sequence into the music player
     MusicPlayerSetSequence(p, _musicSequence);
     // Called to do some MusicPlayer setup. This just
     // reduces latency when MusicPlayerStart is called
     MusicPlayerPreroll(p);
     // Starts the music playing
     MusicPlayerStart(p);
     
     
     */
    
    return YES;
    
}

- (BOOL)createVirtualMidiRef{
    
    OSStatus result = noErr;
    
    // Create a client
    MIDIClientRef virtualMidi;
    result = MIDIClientCreate(CFSTR("Virtual Client"),
                              MyMIDINotifyProc,
                              NULL,
                              &virtualMidi);
    
    NSAssert( result == noErr, @"MIDIClientCreate failed. Error code: %d '%.4s'", (int) result, (const char *)&result);
    
    // Create an endpoint
    //MIDIEndpointRef virtualEndpoint;
    result = MIDIDestinationCreate(virtualMidi, CFSTR("Virtual Destination"), MyMIDIReadProc, self.samplerUnit, &_virtualEndpoint);
    
    if( result != noErr){
        NSError *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:result userInfo:nil];
        NSLog(@"MIDIDestinationCreate failed. Error code: %d '%@'", (int) result, error);
        return NO;
    }
    
    
    return YES;
}

- (void)playSequence{
    
    OSStatus result;
    
    if(!_musicPlayer){
        NewMusicPlayer(&(_musicPlayer));
        
    }
    
    if(_musicSequence){
        MusicPlayerSetSequence(_musicPlayer, _musicSequence);
    }
    
    
    MusicTimeStamp currTime;
    result = MusicPlayerGetTime(_musicPlayer, &currTime);
    NSLog(@"Current time before play: %f", currTime);
    
    Boolean isPlaying;
    MusicPlayerIsPlaying(_musicPlayer, &isPlaying);
    if(!isPlaying){
        MusicPlayerPreroll(_musicPlayer);
        MusicPlayerStart(_musicPlayer);
    }
    
    
    result = MusicPlayerGetTime(_musicPlayer, &currTime);
    NSLog(@"Current time after play: %f", currTime);
    
    
}


- (void)resumeSequence{
    
    OSStatus result;
    
    if(!_musicPlayer){
        return;
    }
    
    
    MusicTimeStamp currTime;
    result = MusicPlayerGetTime(_musicPlayer, &currTime);
    NSLog(@"Current time before play: %f", currTime);
    
    Boolean isPlaying;
    MusicPlayerIsPlaying(_musicPlayer, &isPlaying);
    if(!isPlaying){
        MusicPlayerPreroll(_musicPlayer);
        MusicPlayerStart(_musicPlayer);
    }
    
    
    result = MusicPlayerGetTime(_musicPlayer, &currTime);
    NSLog(@"Current time after play: %f", currTime);
    
    
}



- (void)stopSequence{
    if (!_musicPlayer)
        return;
    
    //OSStatus disposeResult;
    
    
    Boolean isPlaying;
    MusicPlayerIsPlaying(_musicPlayer, &isPlaying);
    if (isPlaying) {
        //MusicPlayerStop(_musicPlayer);
        
        OSStatus result = noErr;
        
        result = MusicPlayerStop(_musicPlayer);
        /*
        UInt32 trackCount;
        MusicSequenceGetTrackCount(_musicSequence, &trackCount);
        
        NSLog(@"Numtracks to dispose: %d", trackCount);
        MusicTrack track;
        for(int i=0;i<trackCount;i++)
        {
            MusicSequenceGetIndTrack (_musicSequence, i, &track);
            result = MusicSequenceDisposeTrack(_musicSequence, track);
        }
        */
        
        MusicTimeStamp currTime;
        result = MusicPlayerGetTime(_musicPlayer, &currTime);
        NSLog(@"Current time after stop: %f", currTime);
        
        /*
        MusicPlayerSetTime(_musicPlayer, 0);
        MusicPlayerSetSequence(_musicPlayer, nil);
        disposeResult = DisposeMusicPlayer(_musicPlayer);
        if (disposeResult == noErr) {
            _musicPlayer = nil;
        }
         */
       
        //result = DisposeMusicSequence(_musicSequence);
        //result = DisposeAUGraph(_processingGraph);
    }
}


- (BOOL) loadSoundBank{
    
    /*
    NSURL *presetURL = [[NSURL alloc] initFileURLWithPath:[[NSBundle mainBundle] pathForResource:@"shakyC2" ofType:@"aupreset"]];
    if(presetURL){
        [self loadFromPresetURL:presetURL];
    }
    */
    
    NSURL *sbURL = [[NSBundle mainBundle] URLForResource:@"Yamaha_XG_Sound_Set" withExtension:@"sf2"];
    if(sbURL){
        [self loadSoundBankFromURL:sbURL];
    }else
        return NO;
    
    return YES;
}



- (OSStatus) loadSoundBankFromURL: (NSURL *) presetURL {
    /*
    CFDataRef propertyResourceData = 0;
    Boolean status;
    SInt32 errorCode = 0;
    */
    
    OSStatus result = noErr;
    
#pragma TODO: CFURLCreateDataAndPropertiesFromResource is DEPRECATED
    /*
     TODO: CFURLCreateDataAndPropertiesFromResource is deprecated
     */
    
    
    AUSamplerInstrumentData bankData;
    bankData.instrumentType = kInstrumentType_SF2Preset;
    bankData.fileURL = (__bridge CFURLRef)(presetURL);
    //bankData.bankURL = (__bridge CFURLRef)(presetURL);
    bankData.bankMSB  = kAUSampler_DefaultMelodicBankMSB;
    bankData.bankLSB  = kAUSampler_DefaultBankLSB;
    bankData.presetID = 2;
    

    //status = CFURLCreateDataAndPropertiesFromResource(kCFAllocatorDefault, (__bridge CFURLRef) presetURL, &propertyResourceData, NULL, NULL, &errorCode);
    //CFURLCopyResourcePropertiesForKeys(
    
    /*
    if(!(status == YES) && !(propertyResourceData != 0)){
        NSLog(@"Could not create data from presetURL! Error code: %d '%.4s'", (int) errorCode, (const char *)&errorCode);
        return errorCode;
    }
    
    // Convert the data object into a property list
    CFPropertyListRef presetPropertyList = 0;
    CFPropertyListFormat dataFormat = 0;
    CFErrorRef errorRef = 0;
    
    presetPropertyList = CFPropertyListCreateWithData(kCFAllocatorDefault, propertyResourceData, kCFPropertyListImmutable, &dataFormat, &errorRef);
    
    if(presetPropertyList != 0){
        result = AudioUnitSetProperty(self.samplerUnit, kAudioUnitProperty_ClassInfo, kAudioUnitScope_Global, 0, &presetPropertyList, sizeof(CFPropertyListRef));
        CFRelease(presetPropertyList);
    }
    */
    
    // set the kAUSamplerProperty_LoadPresetFromBank property
    result = AudioUnitSetProperty(self.samplerUnit,
                                  kAUSamplerProperty_LoadInstrument,
                                  kAudioUnitScope_Global,
                                  0,
                                  &bankData,
                                  sizeof(bankData));
    
    /*
    if(errorRef) CFRelease(errorRef);
    CFRelease(propertyResourceData);
    */
    
    // check for errors
    NSCAssert (result == noErr,
               @"Unable to set the preset property on the Sampler. Error code:%d '%.4s'",
               (int) result,
               (const char *)&result);
    
    return result;
}




#pragma mark C functions for midi notifications

// Get general midi notifications
void MyMIDINotifyProc (const MIDINotification  *message, void *refCon) {
    printf("MIDI Notify, messageId=%d,", message->messageID);
}

// Get the MIDI messages as they're sent
static void MyMIDIReadProc(const MIDIPacketList *pktlist,
                           void *refCon,
                           void *connRefCon) {
    
    // Cast our Sampler unit back to an audio unit
    //AudioUnit player = (AudioUnit) &refCon;
    AudioUnit *player = (AudioUnit*) refCon;
    MIDIPacket *packet = (MIDIPacket *)pktlist->packet;
    for (int i=0; i < pktlist->numPackets; i++) {
        Byte midiStatus = packet->data[0];
        Byte midiCommand = midiStatus >> 4;
        
        
        BOOL isNote = NO;
        
        
        // If the command is note-on
        if ((midiCommand == 0x09) ||
            (midiCommand == 0x08)) {
            
            isNote = YES;
            
            
            Byte note = packet->data[1] & 0x7F;
            Byte velocity = packet->data[2] & 0x7F;
            
            
            // Log the note letter in a readable format
            int noteNumber = ((int) note) % 12;
            NSString *noteType;
            switch (noteNumber) {
                case 0:
                    noteType = @"C";
                    break;
                case 1:
                    noteType = @"C#";
                    break;
                case 2:
                    noteType = @"D";
                    break;
                case 3:
                    noteType = @"D#";
                    break;
                case 4:
                    noteType = @"E";
                    break;
                case 5:
                    noteType = @"F";
                    break;
                case 6:
                    noteType = @"F#";
                    break;
                case 7:
                    noteType = @"G";
                    break;
                case 8:
                    noteType = @"G#";
                    break;
                case 9:
                    noteType = @"A";
                    break;
                case 10:
                    noteType = @"Bb";
                    break;
                case 11:
                    noteType = @"B";
                    break;
                default:
                    break;
            }
            
            if(isNote)
            {
                //NSLog(@"Note type: %@, note number: %d", noteType, noteNumber);
                
                // Use MusicDeviceMIDIEvent to send our MIDI message to the sampler to be played
                OSStatus result = noErr;
                result = MusicDeviceMIDIEvent((AudioUnit)player, midiStatus, note, velocity, 0);
                if(result != noErr){
                    NSError *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:result userInfo:nil];
                    NSLog(@"MIDIDestinationCreate failed. Error code: %d '%@'", (int) result, error);
                    
                }
            }
        }
        packet = MIDIPacketNext(packet);
    }
}


#pragma mark end C functions for midi notifications




#pragma mark notifications

- (void)handleInterruption:(NSNotification *)notification
{
    UInt8 theInterruptionType = [[notification.userInfo valueForKey:AVAudioSessionInterruptionTypeKey] intValue];
    
    NSLog(@"Session interrupted > --- %s ---\n", theInterruptionType == AVAudioSessionInterruptionTypeBegan ? "Begin Interruption" : "End Interruption");
    
    if (theInterruptionType == AVAudioSessionInterruptionTypeBegan) {
        //[_drumPlayer stop];
        //[_marimbaPlayer stop];
        //[self stopPlayingRecordedFile];
        //[self stopRecordingMixerOutput];
        
        if ([self.delegate respondsToSelector:@selector(engineWasInterrupted)]) {
            [self.delegate engineWasInterrupted];
        }
        
    }
    if (theInterruptionType == AVAudioSessionInterruptionTypeEnded) {
        // make sure to activate the session
        NSError *error;
        bool success = [[AVAudioSession sharedInstance] setActive:YES error:&error];
        if (!success) NSLog(@"AVAudioSession set active failed with error: %@", [error localizedDescription]);
        
        // start the engine once again
        //[self startEngine];
    }
}

- (void)handleRouteChange:(NSNotification *)notification
{
    UInt8 reasonValue = [[notification.userInfo valueForKey:AVAudioSessionRouteChangeReasonKey] intValue];
    AVAudioSessionRouteDescription *routeDescription = [notification.userInfo valueForKey:AVAudioSessionRouteChangePreviousRouteKey];
    
    NSLog(@"Route change:");
    switch (reasonValue) {
        case AVAudioSessionRouteChangeReasonNewDeviceAvailable:
            NSLog(@"     NewDeviceAvailable");
            break;
        case AVAudioSessionRouteChangeReasonOldDeviceUnavailable:
            NSLog(@"     OldDeviceUnavailable");
            break;
        case AVAudioSessionRouteChangeReasonCategoryChange:
            NSLog(@"     CategoryChange");
            NSLog(@" New Category: %@", [[AVAudioSession sharedInstance] category]);
            break;
        case AVAudioSessionRouteChangeReasonOverride:
            NSLog(@"     Override");
            break;
        case AVAudioSessionRouteChangeReasonWakeFromSleep:
            NSLog(@"     WakeFromSleep");
            break;
        case AVAudioSessionRouteChangeReasonNoSuitableRouteForCategory:
            NSLog(@"     NoSuitableRouteForCategory");
            break;
        default:
            NSLog(@"     ReasonUnknown");
    }
    
    NSLog(@"Previous route:\n");
    NSLog(@"%@", routeDescription);
}

- (void)handleMediaServicesReset:(NSNotification *)notification
{
    // if we've received this notification, the media server has been reset
    // re-wire all the connections and start the engine
    NSLog(@"Media services have been reset!");
    NSLog(@"Re-wiring connections and starting once again");
    

    #pragma mark TODO: Put In Some Re-wiring code here
    //[self createEngineAndAttachNodes];
    //[self initAVAudioSession];
    //[self makeEngineConnections];
    //self startEngine];
    
    
    
    
    // post notification
    if ([self.delegate respondsToSelector:@selector(engineConfigurationHasChanged)]) {
        [self.delegate engineConfigurationHasChanged];
    }
    
    
}



@end


#pragma mark steps for implementing Midi playback in iOS

/*!
 create audio session
	set sample rate
	Activate the session
	extract actual sample rate from session
 create AuGraph (aka processing graph)
	contains ioNode and sampleNode
	connect nodes
	extract ioUnit and samplerUnit from respective nodes
 ConfigureAuGraph
	initialize ioUnit and samplerUnit
 ActivateAuGraph
	Initialize AuGraph
	Start AuGraph
 CreateMusicSequence
	Create a new music sequence
	Load a midi file into it
	Associate the Sequence with the AuGraph (aka processing graph) -- MusicSequenceSetAUGraph
 Note: MusicSequenceSetAUGraph targets the first
 Load a SoundBank (aka soundfont) and connect it to the SamplerUnit
	Load a sf2 file containing instrument data
	Associate it with the samplerUnit via AudioUnitSetProperty
 Play the Sequence
	Create a musicPlayer
	Associate the MusicPlayer with the MusicSequence
	Pre-roll the MusicPlayer
	Start the MusicPlayer
	
 
 
	
 */

/*!

 Create Audio Session
 Create AUGraph
 ** Create AudioComponentDescription
 ** NewAUGraph
 ** Add Nodes to the graph
 ** Open the graph
 ** Connect the nodes to each other
 ** Get references to the AudioUnits from nodes
 Configure Graph
 ** Initialize Audio Units
 ** Set Properties on Audio Units
 Initialize Audio Processing graph
 Start Audio Processing graph
 
*/

#pragma mark useful links

/*!

 http://www.deluge.co/?q=midi-driven-animation-core-audio-objective-c
 http://sound.stackexchange.com/a/24233
 http://teragonaudio.com/article/How-to-do-realtime-recording-with-effect-processing-on-iOS.html
*/



