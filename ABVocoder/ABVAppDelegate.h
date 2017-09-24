//
//  ABVAppDelegate.h
//  ABVocoder
//
//  Created by Brian Wang on 4/22/14.
//  Copyright (c) 2014 Positive Grid LLC. All rights reserved.
//

#import <UIKit/UIKit.h>

#define NUM_BANDS   64
#define MIN_FREQ    20.0
#define MAX_FREQ    20000.0
#define NUM_FRAME   64

#define OUTPUT_GAIN_DB_MIN  -60.0f
#define OUTPUT_GAIN_DB_MAX  10.0f

void processModifierAudioBudder(void *inList, int frames);
void processCarrierAudioBudder(void *inList, int frames);

@class AEAudioController;
@class ABAudiobusController;
@class ABInputPort;
@class AEBlockChannel;
@class ABPort;

@interface ABVAppDelegate : UIResponder <UIApplicationDelegate>

@property (strong, nonatomic) UIWindow *window;
@property (strong, nonatomic) AEAudioController *audioController;
@property (strong, nonatomic) ABAudiobusController *audiobusController;
@property (strong, nonatomic) ABInputPort *inputPort;
@property (weak, nonatomic) ABPort *modifierPort;
@property (weak, nonatomic) ABPort *carrierPort;
@property (assign, nonatomic) BOOL audiobusConnected;
@property (assign, nonatomic) unsigned long carrierChannelIndex;
@property (assign, nonatomic) unsigned long modifierChannelIndex;
@property (strong, nonatomic) AEBlockChannel *channel;

@property (assign, nonatomic) float outputGain;

+ (id)sharedInstance;
- (void)getBandValuesToArray:(float *)outArray;

@end
