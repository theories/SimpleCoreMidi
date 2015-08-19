//
//  ViewController.h
//  SimpleCoreMidi
//
//  Created by Thierry Sansaricq on 8/18/15.
//  Copyright (c) 2015 Thierry Sansaricq. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "MidiEngine.h"

@class MidiEngine;

@interface ViewController : UIViewController{
    MidiEngine *_midiEngine;
}

@end

