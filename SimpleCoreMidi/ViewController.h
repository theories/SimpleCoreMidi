//
//  ViewController.h
//  SimpleCoreMidi
//
//  Created by Thierry Sansaricq on 8/18/15.
//  Copyright (c) 2015 Thierry Sansaricq. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "MidiEngine.h"


@interface ViewController : UIViewController{
    MidiEngine *_midiEngine;
}

@property (unsafe_unretained, nonatomic) IBOutlet UIButton *playButton;
@property (unsafe_unretained, nonatomic) IBOutlet UIButton *stopButton;
@property (unsafe_unretained, nonatomic) IBOutlet UIButton *resumeButton;

- (IBAction) playSequence:(id)sender;
- (IBAction) stopSequence:(id)sender;
- (IBAction) resumeSequence:(id)sender;

@end

