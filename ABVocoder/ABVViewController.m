//
//  ABVViewController.m
//  ABVocoder
//
//  Created by Brian Wang on 4/22/14.
//  Copyright (c) 2014 Positive Grid LLC. All rights reserved.
//

#import "ABVViewController.h"
#import "ABVAppDelegate.h"
#import "TheAmazingAudioEngine.h"
#import "Audiobus.h"
#import <QuartzCore/QuartzCore.h>

#define CHANNEL_HEIGHT 84.0

static const int kInputChannelsChangedContext;

static CGPoint modifierIconOrigPos;
static CGPoint carrierIconOrigPos;

@interface ABVViewController ()

@property (strong, nonatomic) NSTimer *timer;

@end

@implementation ABVViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
	// Do any additional setup after loading the view, typically from a nib.
    
    AEAudioController *audioController = [[ABVAppDelegate sharedInstance] audioController];
    
    [audioController addObserver:self forKeyPath:@"numberOfInputChannels" options:0 context:(void*)&kInputChannelsChangedContext];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(audiobusConnectionsChanged:) name:ABConnectionsChangedNotification object:nil];
    
    [self updateChannelIcons];
    [self checkAndUpdateChannelAssignments];
    
    self.timer = [NSTimer scheduledTimerWithTimeInterval:0.1 target:self selector:@selector(timerTick) userInfo:nil repeats:YES];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (unsigned long)getHandlerIconChannelIndex:(UIView *)handler {
    unsigned long numChannels = 0;
    unsigned long result = 0;

    ABVAppDelegate *appDelegate = [ABVAppDelegate sharedInstance];
    ABInputPort *inputPort = [appDelegate inputPort];
    if (inputPort.sources.count > 0) {
        numChannels = inputPort.sources.count;
    } else {
        numChannels = appDelegate.audioController.numberOfInputChannels;
    }
    
    CGFloat handlerYMid = handler.frame.origin.y + handler.frame.size.height/2.0;
    
    for (unsigned long i=0; i<numChannels; i++) {
        if ((handlerYMid >= CHANNEL_HEIGHT * i + 10.0) && (handlerYMid <= CHANNEL_HEIGHT * (i+1) - 10.0)) {
            result = i+1;
            break;
        }
    }
    

    return result;
}

- (void)timerTick
{
    UIColor *color[3] = { [UIColor greenColor], [UIColor redColor], [UIColor blueColor] };
    float bandValues[3][2][NUM_BANDS];
    
    for (UIView *subview in self.bandValuesView.subviews) {
        [subview removeFromSuperview];
    }
    
    ABVAppDelegate *appDelegate = [ABVAppDelegate sharedInstance];
    [appDelegate getBandValuesToArray:(float *)bandValues];
    
    for (int m=0; m<3; m++) {
        for (int b=0; b<NUM_BANDS; b++) {
            const CGFloat maxHeight = 60.0;
            CGFloat value = bandValues[m][0][b];
            CGFloat valueDb = 20 * log10f(value);
            valueDb = MIN(valueDb, 10);
            valueDb = MAX(valueDb, -60);
            if (value == 0.0) {
                valueDb = -60.0;
            }
            CGFloat valueRatio = (valueDb+60.0) / 70.0;
            CGFloat height = valueRatio*maxHeight;
            if (0.0 == height || isnan(height)) {
                continue;
            }
            CGRect rect = CGRectMake(40.0+80.0*m+1.0*b, (maxHeight-height), 1.0, height);
            
            UIView *newView = [[UIView alloc] initWithFrame:rect];
            newView.backgroundColor = color[m];
            [self.bandValuesView addSubview:newView];
            //NSLog(@"bandValues(%d, %d): %f", i, b, bandValues[i][0][b]);
        }
    }
}

- (void)checkAndUpdateChannelAssignments
{
    ABVAppDelegate *appDelegate = [ABVAppDelegate sharedInstance];
    ABInputPort *inputPort = [appDelegate inputPort];

    BOOL newAudobusConnected = (inputPort.sources.count > 0) ? YES : NO;
    unsigned long newCarrierChannelIndex = [self getHandlerIconChannelIndex:self.carrierIcon];
    unsigned long newModifierChannelIndex = [self getHandlerIconChannelIndex:self.modifierIcon];
    if (newCarrierChannelIndex == newModifierChannelIndex) {
        newCarrierChannelIndex = 0;
        newModifierChannelIndex = 0;
    }

    if ((appDelegate.audiobusConnected != newAudobusConnected)
        || (appDelegate.carrierChannelIndex != newCarrierChannelIndex)
        || (appDelegate.modifierChannelIndex != newModifierChannelIndex)) {
        appDelegate.audiobusConnected = newAudobusConnected;
        appDelegate.carrierChannelIndex = newCarrierChannelIndex;
        appDelegate.modifierChannelIndex = newModifierChannelIndex;
        if (newCarrierChannelIndex > 0 && (newCarrierChannelIndex-1) < inputPort.sources.count) {
            appDelegate.carrierPort = [inputPort.sources objectAtIndex:newCarrierChannelIndex-1];
            NSLog(@"carrier port = 0x%0lX (%@)", (unsigned long)appDelegate.carrierPort, appDelegate.carrierPort.title);
        } else {
            appDelegate.carrierPort = nil;
        }
        if (newModifierChannelIndex > 0 && (newModifierChannelIndex-1) < inputPort.sources.count) {
            appDelegate.modifierPort = [inputPort.sources objectAtIndex:newModifierChannelIndex-1];
            NSLog(@"modifier port = 0x%0lX (%@)", (unsigned long)appDelegate.modifierPort, appDelegate.modifierPort.title);
        } else {
            appDelegate.modifierPort = nil;
        }
        
        [self updateChannelIcons];
    }
}

- (void)updateChannelIcons
{
    for (UIView *subview in self.portIconContainerView.subviews) {
        [subview removeFromSuperview];
    }
    
    ABVAppDelegate *appDelegate = [ABVAppDelegate sharedInstance];
    ABInputPort *inputPort = appDelegate.inputPort;
    AEAudioController *audioController = appDelegate.audioController;

    if (inputPort.sources.count > 0) {
        self.numberOfInputLabel.text = [NSString stringWithFormat:@"From Audiobus, %lu source%@ %lu, %lu %lu", inputPort.sources.count, (inputPort.sources.count != 1) ? @"s" : @"", audioController.numberOfInputChannels, appDelegate.carrierChannelIndex, appDelegate.modifierChannelIndex];
        unsigned long i = 0;
        for (ABPort *source in inputPort.sources) {
            UIImageView *portImageView = [[UIImageView alloc] initWithImage:source.peer.icon];
            portImageView.frame = CGRectMake(10.0, CHANNEL_HEIGHT*i+10.0, CHANNEL_HEIGHT-20.0, CHANNEL_HEIGHT-20.0);
            portImageView.layer.masksToBounds = YES;
            portImageView.layer.cornerRadius = (10.0/57.0) * 64.0;
            [self.portIconContainerView addSubview:portImageView];
            
            UIButton *portIconView = [UIButton buttonWithType:UIButtonTypeRoundedRect];
            portIconView.frame = CGRectMake(CHANNEL_HEIGHT, CHANNEL_HEIGHT*i+10.0, 310.0-CHANNEL_HEIGHT, CHANNEL_HEIGHT-20.0);
            //[portIconView setImage:source.peer.icon forState:UIControlStateNormal];
            [portIconView setTitle:source.title forState:UIControlStateNormal];
            portIconView.userInteractionEnabled = NO;
            [self.portIconContainerView addSubview:portIconView];
            
            if ((i+1) == appDelegate.modifierChannelIndex) {
                [portIconView setTitleColor:[self.modifierIcon titleColorForState:UIControlStateNormal] forState:UIControlStateNormal];
                [portIconView setBackgroundColor:self.modifierIcon.backgroundColor];
            } else if ((i+1) == appDelegate.carrierChannelIndex) {
                [portIconView setTitleColor:[self.carrierIcon titleColorForState:UIControlStateNormal] forState:UIControlStateNormal];
                [portIconView setBackgroundColor:self.carrierIcon.backgroundColor];
            }
            
            i++;
        }
    } else {
        self.numberOfInputLabel.text = [NSString stringWithFormat:@"From System Input, %lu channel%@, %lu, %lu", audioController.numberOfInputChannels, (audioController.numberOfInputChannels != 1) ? @"s" : @"", appDelegate.carrierChannelIndex, appDelegate.modifierChannelIndex];
        for (unsigned long i=0; i<audioController.numberOfInputChannels; i++) {
            UIButton *portIconView = [UIButton buttonWithType:UIButtonTypeRoundedRect];
            portIconView.frame = CGRectMake(10.0, CHANNEL_HEIGHT*i+10.0, 300.0, CHANNEL_HEIGHT-20.0);
            [portIconView setTitle:[NSString stringWithFormat:@"Channel %lu", i] forState:UIControlStateNormal];
            portIconView.userInteractionEnabled = NO;
            [self.portIconContainerView addSubview:portIconView];
            
            if ((i+1) == appDelegate.modifierChannelIndex) {
                [portIconView setTitleColor:[self.modifierIcon titleColorForState:UIControlStateNormal] forState:UIControlStateNormal];
                [portIconView setBackgroundColor:self.modifierIcon.backgroundColor];
            } else if ((i+1) == appDelegate.carrierChannelIndex) {
                [portIconView setTitleColor:[self.carrierIcon titleColorForState:UIControlStateNormal] forState:UIControlStateNormal];
                [portIconView setBackgroundColor:self.carrierIcon.backgroundColor];
            }
        }
    }
}

- (void)audiobusConnectionsChanged:(NSNotification*)notification
{
    [self updateChannelIcons];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if ( context == &kInputChannelsChangedContext ) {
        [self updateChannelIcons];
        [self checkAndUpdateChannelAssignments];
    }
}

- (IBAction)iconTouchedDown:(id)sender forEvent:(UIEvent *)event
{
    UIView *icon = (UIView *)sender;
    UITouch *touch = [[event touchesForView:icon] anyObject];
    CGPoint location = [touch locationInView:self.view];
    //NSLog(@"TouchDown in button %ld: %f, %f", icon.tag, location.x, location.y);
    if (self.modifierIcon == sender) {
        modifierIconOrigPos = location;
    } else if (self.carrierIcon == sender) {
        carrierIconOrigPos = location;
    }
}

- (IBAction)iconTouchedMove:(id)sender forEvent:(UIEvent *)event
{
    UIView *icon = (UIView *)sender;
    UITouch *touch = [[event touchesForView:icon] anyObject];
    CGPoint location = [touch locationInView:self.view];
    //NSLog(@"TouchMove in button %ld: %f, %f", (long)icon.tag, location.x, location.y);
    CGRect iconFrame = icon.frame;
    CGPoint origPos;
    if (self.modifierIcon == sender) {
        origPos = modifierIconOrigPos;
    } else if (self.carrierIcon == sender) {
        origPos = carrierIconOrigPos;
    }
    iconFrame.origin.x += location.x - origPos.x;
    iconFrame.origin.y += location.y - origPos.y;
    icon.frame = iconFrame;
    if (self.modifierIcon == sender) {
        modifierIconOrigPos = location;
    } else if (self.carrierIcon == sender) {
        carrierIconOrigPos = location;
    }

    [self checkAndUpdateChannelAssignments];
}

- (IBAction)iconTouchedUp:(id)sender forEvent:(UIEvent *)event
{
    UIView *icon = (UIView *)sender;
    UITouch *touch = [[event touchesForView:icon] anyObject];
    CGPoint location = [touch locationInView:self.view];
    //NSLog(@"TouchUp in button %ld: %f, %f", icon.tag, location.x, location.y);
}

- (IBAction)outputGainSliderValueChanged:(id)sender
{
    float sliderValue = self.outputGainSlider.value;
    //float outputDbValue = (sliderValue - OUTPUT_GAIN_DB_MIN) / (OUTPUT_GAIN_DB_MAX - OUTPUT_GAIN_DB_MIN);
    float outputDbValue = sliderValue;
    float outputValue = powf(10.0f, outputDbValue / 20.0);
    ABVAppDelegate *appDelegate = [ABVAppDelegate sharedInstance];
    appDelegate.outputGain = outputValue;
    self.outputGainLabel.text = [NSString stringWithFormat:@"%.2f dB", outputDbValue];
}

@end
