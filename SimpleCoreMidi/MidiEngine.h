//
//  MidiEngine.h
//  SimpleCoreMidi
//
//  Created by Thierry Sansaricq on 8/18/15.
//  Copyright (c) 2015 Thierry Sansaricq. All rights reserved.
//

#ifndef SimpleCoreMidi_MidiEngine_h
#define SimpleCoreMidi_MidiEngine_h


#endif


#import <Foundation/Foundation.h>
#import <AudioToolbox/MusicPlayer.h>
#import <CoreAudio/CoreAudioTypes.h>
#import <AVFoundation/AVFoundation.h>
//#import <AudioUnit/AudioUnitProperties.h>
#import <Accelerate/Accelerate.h>


@protocol MidiEngineDelegate <NSObject>

@optional
- (void)engineWasInterrupted;
- (void)engineConfigurationHasChanged;
- (void)mixerOutputFilePlayerHasStopped;

@end


@interface MidiEngine : NSObject

@property (readwrite) AUGraph       processingGraph;
@property (readwrite) AudioUnit     samplerUnit;
@property (readwrite) AudioUnit     ioUnit;
@property (readwrite) Float64       graphSampleRate;
@property (readwrite) MusicSequence musicSequence;
@property (readwrite) MusicPlayer   musicPlayer;


@property (weak) id<MidiEngineDelegate> delegate;

- (void)playSequence;
- (void)stopSequence;
- (void)resumeSequence;

- (void)handleInterruption:(NSNotification *)notification;
- (void)handleRouteChange:(NSNotification *)notification;
- (void)handleMediaServicesReset:(NSNotification *)notification;

@end

