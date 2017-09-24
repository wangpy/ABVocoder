//
//  ABVAppDelegate.m
//  ABVocoder
//
//  Created by Brian Wang on 4/22/14.
//  Copyright (c) 2014 Positive Grid LLC. All rights reserved.
//

#import "ABVAppDelegate.h"
#import "TheAmazingAudioEngine.h"
#import "Audiobus.h"
#import <Accelerate/Accelerate.h>

#define AUDIOBUS_URL @"pgabvocoder.audiobus://"
#define AUDIOBUS_KEY @"MTQwMDc1NDYwMioqKkFCVm9jb2RlcioqKnBnYWJ2b2NvZGVyLmF1ZGlvYnVzOi8v:kuBfmP6cDZwrsqD62wISlXU+w9FTwwhebo/RtbTChEgBJ7DxKku8JN4LqQrYfYt4dzEzD9nhY44+dPp52z83qzBxaS2oNbNV5vWJofkS+2FiOPY3pnJL4RzpTWUeuWue"

static const int kCoreAudioInputTag; // The tag we'll use to identify the core audio input stream
static const int kCoreAudioInputCarrierTag;
static const int kCoreAudioInputModifierTag;
static const int kInputChannelsChangedContext;

static float outputGain;
static float processBuffer[3][2][NUM_FRAME];
static float processBuffer2[3][2][NUM_FRAME];
static float delay[3][2][NUM_BANDS][NUM_FRAME];
static float delay2[3][2][NUM_BANDS][NUM_FRAME];
static float bandValues[3][2][NUM_BANDS];
static float filterOut[3][2][NUM_BANDS][NUM_FRAME];
static vDSP_biquad_Setup setup[NUM_BANDS];
static long numInputChannels;

@interface ABVAppDelegate ()

@property (strong, nonatomic) NSMutableArray *inputReceiverArray;
@property (strong, nonatomic) ABMultiStreamBuffer *multiStreamBuffer;
@property (strong, nonatomic) ABLiveBuffer *liveBuffer;

@end

@implementation ABVAppDelegate

@synthesize audioController = _audioController;
@synthesize audiobusController = _audiobusController;
@synthesize inputPort = _inputPort;
@synthesize modifierChannelIndex = _modifierChannelIndex;
@synthesize carrierChannelIndex = _carrierChannelIndex;
@synthesize audiobusConnected = _audiobusConnected;
@synthesize modifierPort = _modifierPort;
@synthesize carrierPort = _carrierPort;
@synthesize outputGain = _outputGain;
@synthesize multiStreamBuffer = _multiStreamBuffer;
@synthesize liveBuffer = _liveBuffer;

void calcBandPassCoeff(double Fc, double Fs, double Q, double peakGain, double *outCoeffArr)
{
    // http://www.earlevel.com/main/2011/01/02/biquad-formulas/
    double a0,a1,a2,b1,b2,norm;
    double K = tan(M_PI * Fc / Fs);
    
    norm = 1 / (1 + K / Q + K * K);
    a0 = K / Q * norm;
    a1 = 0;
    a2 = -a0;
    b1 = 2 * (K * K - 1) * norm;
    b2 = (1 - K / Q + K * K) * norm;
    
    outCoeffArr[0] = a0;
    outCoeffArr[1] = a1;
    outCoeffArr[2] = a2;
    outCoeffArr[3] = b1;
    outCoeffArr[4] = b2;
    NSLog(@"Fc=%-5.2f Q=%-5.2f: %f %f %f %f %f", Fc, Q, a0, a1, a2, b1, b2);
}

void prepareBiquadSetup(double Fmin, double Fmax, double Fs)
{
    double lmin = log(Fmin);
    double lmax = log(Fmax);
    double dl = (lmax - lmin) / (NUM_BANDS - 1);
    double filterCoeffs[5];
    for (int i=0; i<NUM_BANDS; i++) {
        double Fc = exp(lmin+i*dl);
        double Fcut = exp(lmin+(i-1)*dl);
        double df = 2 * (Fc - Fcut);
        double q = Fc / df;
        NSLog(@"band %02d: Fc=%-5.2f, q=%-5.2f", i, Fc, q);
        calcBandPassCoeff(Fc, Fs, q, 1.0, filterCoeffs);
        setup[i] = vDSP_biquad_CreateSetup(filterCoeffs, 1);
    }
    memset(processBuffer, 0, sizeof(float)*3*2*NUM_FRAME);
    memset(processBuffer2, 0, sizeof(float)*3*2*NUM_FRAME);
    memset(delay, 0, sizeof(float)*3*2*NUM_BANDS*NUM_FRAME);
    memset(delay2, 0, sizeof(float)*3*2*NUM_BANDS*NUM_FRAME);
    outputGain = 1.0;
}

void performVocoderCalculation()
{
    for (int m=0; m<2; m++) {
        for (int c=0; c<2; c++) {
            for (int i=0; i<NUM_FRAME; i++) {
                if (isnan(processBuffer[m][c][i])) {
                    processBuffer[m][c][i] = 0.0;
                }
            }
            for (int b=0; b<NUM_BANDS; b++) {
                for (int i=0; i<NUM_FRAME; i++) {
                    if (isnan(delay[m][c][b][i])) {
                        delay[m][c][b][i] = 0.0;
                    }
                    if (isnan(delay2[m][c][b][i])) {
                        delay2[m][c][b][i] = 0.0;
                    }
                }
                vDSP_biquad(setup[b], delay[m][c][b], processBuffer[m][c], 1, processBuffer2[m][c], 1, NUM_FRAME);
                vDSP_biquad(setup[b], delay2[m][c][b], processBuffer2[m][c], 1, filterOut[m][c][b], 1, NUM_FRAME);
                for (int i=0; i<NUM_FRAME; i++) {
                    if (isnan(delay[m][c][b][i])) {
                        delay[m][c][b][i] = 0.0;
                    }
                    if (isnan(delay2[m][c][b][i])) {
                        delay2[m][c][b][i] = 0.0;
                    }
                    if (isnan(filterOut[m][c][b][i])) {
                        filterOut[m][c][b][i] = 0.0;
                    }
                }
                vDSP_rmsqv(filterOut[m][c][b], 1, &bandValues[m][c][b], NUM_FRAME);
                if (isnan(bandValues[m][c][b])) {
                    bandValues[m][c][b] = 0.0;
                }
            }
        }
    }
    int m = 2;
    for (int c=0; c<2; c++) {
        vDSP_mmul((float*)bandValues[1][c], 1, (float*)filterOut[0][c], 1, processBuffer[m][c], 1, 1, NUM_BANDS, NUM_FRAME);
        vDSP_vsmul(processBuffer[m][c], 1, &outputGain, processBuffer[m][c], 1, NUM_FRAME);
        if (NO) {
            float lowLimit = -1.0, highLimit = 1.0;
            vDSP_vclip(processBuffer[m][c], 1, &lowLimit, &highLimit, processBuffer[m][c], 1, NUM_FRAME);
        }
        for (int i=0; i<NUM_FRAME; i++) {
            if (isnan(processBuffer[m][c][i])) {
                processBuffer[m][c][i] = 0.0;
            }
        }
        for (int b=0; b<NUM_BANDS; b++) {
            vDSP_biquad(setup[b], delay[m][c][b], processBuffer[m][c], 1, filterOut[m][c][b], 1, NUM_FRAME);
            for (int i=0; i<NUM_FRAME; i++) {
                if (isnan(delay[m][c][b][i])) {
                    delay[m][c][b][i] = 0.0;
                }
                if (isnan(filterOut[m][c][b][i])) {
                    filterOut[m][c][b][i] = 0.0;
                }
            }
            vDSP_svesq(filterOut[m][c][b], 1, &bandValues[m][c][b], NUM_FRAME);
            bandValues[m][c][b] = MIN(1.0, sqrt(bandValues[m][c][b] / NUM_FRAME));
            if (isnan(bandValues[m][c][b])) {
                bandValues[m][c][b] = 0.0;
            }
        }
    }
}

void cleanBiquadSetup()
{
    for (int i=0; i<NUM_BANDS; i++) {
        vDSP_biquad_DestroySetup(setup[i]);
    }
}

+ (id)sharedInstance
{
    return [[UIApplication sharedApplication] delegate];
}

- (void)setOutputGain:(float)inOutputGain
{
    _outputGain = inOutputGain;
    outputGain = inOutputGain;
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    // Override point for customization after application launch.

    // Create an instance of the audio controller, set it up and start it running
    _carrierChannelIndex = 0;
    _modifierChannelIndex = 0;
    prepareBiquadSetup(MIN_FREQ, MAX_FREQ, 44100.0);
    
    self.audioController = [[AEAudioController alloc] initWithAudioDescription:[AEAudioController nonInterleavedFloatStereoAudioDescription] inputEnabled:YES];
    _audioController.preferredBufferDuration = 0.005;
    [_audioController start:NULL];
    __weak typeof(self) weakSelf = self;
    self.channel = [AEBlockChannel channelWithBlock:^(const AudioTimeStamp *time, UInt32 frames, AudioBufferList *audio) {
        for (int i=0; i<audio->mNumberBuffers; i++) {
            memset(audio->mBuffers[i].mData, 0, audio->mBuffers[i].mDataByteSize);
        }
        if (nil == _inputPort || nil == _multiStreamBuffer) {
            return;
        }
        ABInputPortEndReceiveTimeInterval(_inputPort);
        ABMultiStreamBufferEndTimeInterval(_multiStreamBuffer);

        if (_carrierChannelIndex == 0 || _modifierChannelIndex == 0) {
            return;
        }

        char audioBufferListSpace[sizeof(AudioBufferList)+sizeof(AudioBuffer)]; // Space for 2 audio buffers within list
        AudioBufferList *bufferList = (AudioBufferList*)audioBufferListSpace;
        bufferList->mNumberBuffers = 2;
        
        AudioTimeStamp timestamp;
        UInt32 availableFrames = ABMultiStreamBufferPeek(_multiStreamBuffer, &timestamp);

        unsigned long processedFrames = 0;
        UInt32 outFrame;
        while (processedFrames < availableFrames) {
            unsigned long numFrame = MIN(NUM_FRAME, (availableFrames-processedFrames));

            for (int m=0; m<2; m++) {
                for ( int i=0; i<bufferList->mNumberBuffers; i++ ) {
                    bufferList->mBuffers[i].mData = NULL; // Use NULL data; Audiobus will provide the buffers
                    bufferList->mBuffers[i].mDataByteSize = 0; // Audiobus will set this for us.
                    bufferList->mBuffers[i].mNumberChannels = 1;
                }
                outFrame = (UInt32)numFrame;
                ABMultiStreamBufferSource fromPort = NULL;
                if (_audiobusConnected) {
                    fromPort = (0 == m) ? (__bridge ABMultiStreamBufferSource)_carrierPort : (__bridge ABMultiStreamBufferSource)_modifierPort;
                } else {
                    fromPort = (0 == m) ? (void *)&kCoreAudioInputCarrierTag : (void *)&kCoreAudioInputModifierTag;
                }
                AudioTimeStamp outTimestamp;
                ABMultiStreamBufferDequeueSingleSource(_multiStreamBuffer,
                                                       fromPort,
                                                       bufferList,
                                                       &outFrame,
                                                       &outTimestamp);
                if (outFrame > 0) {
                    for (int c=0; c<2; c++) {
                        memcpy(processBuffer[m][c], bufferList->mBuffers[c].mData, sizeof(float)*numFrame);
                    }
                    timestamp = outTimestamp;
                } else {
                    for (int c=0; c<2; c++) {
                        memset(processBuffer[m][c], 0, sizeof(float)*numFrame);
                    }
                }
            }
            
            performVocoderCalculation();
            
            for (int c=0; c<2; c++) {
                bufferList->mBuffers[c].mData = processBuffer[2][c];
                bufferList->mBuffers[c].mDataByteSize = sizeof(float)*(UInt32)numFrame;
            }
            ABLiveBufferEnqueue(_liveBuffer,
                                (ABLiveBufferSource)&kCoreAudioInputTag,
                                bufferList,
                                (UInt32)numFrame,
                                &timestamp);
            
            processedFrames += numFrame;
        }
        ABLiveBufferDequeue(_liveBuffer, audio, frames, NULL);
    }];
    [_audioController addChannels:@[_channel]];
    
    [_audioController addObserver:self forKeyPath:@"numberOfInputChannels" options:0 context:(void*)&kInputChannelsChangedContext];
    numInputChannels = -1;
    self.inputReceiverArray = [NSMutableArray arrayWithCapacity:2];
    [self updateInputChannels];
    
    self.audiobusController = [[ABAudiobusController alloc] initWithAppLaunchURL:[NSURL URLWithString:AUDIOBUS_URL] apiKey:AUDIOBUS_KEY];
    self.inputPort = [self.audiobusController addInputPortNamed:@"input" title:@"input"];
    self.inputPort.receiveMixedAudio = NO;
    self.inputPort.attributes = ABInputPortAttributePlaysLiveAudio;
    self.inputPort.clientFormat = _audioController.audioDescription;
    
    self.inputPort.audioInputBlock = ^(ABInputPort *inputPort, UInt32 lengthInFrames, AudioTimeStamp *nextTimestamp, ABPort *sourcePortOrNil) {
        if (nil == sourcePortOrNil) {
            return;
        }

        // Prepare an audio buffer list
        char audioBufferListSpace[sizeof(AudioBufferList) + sizeof(AudioBuffer)];
        AudioBufferList *bufferList = (AudioBufferList*)&audioBufferListSpace;
        bufferList->mNumberBuffers = 2;
        for ( int i=0; i<bufferList->mNumberBuffers; i++ ) {
            bufferList->mBuffers[i].mNumberChannels = 1;
            bufferList->mBuffers[i].mDataByteSize = 0;
            bufferList->mBuffers[i].mData = 0;
        }

        // Receive audio
        UInt32 inputFrames = lengthInFrames;
        AudioTimeStamp audiobusTimestamp = *nextTimestamp;
        ABInputPortReceive(inputPort, sourcePortOrNil, bufferList, &inputFrames, nextTimestamp, NULL);

        ABMultiStreamBufferEnqueue(weakSelf.multiStreamBuffer,
                                   (__bridge ABMultiStreamBufferSource)sourcePortOrNil, // We use the port to identify the stream
                                   bufferList,
                                   inputFrames,
                                   &audiobusTimestamp);
    };
    self.audioController.audiobusInputPort = self.inputPort;
    
    // Create an instance of the multi-stream buffer, for synchronizing audio streams
    self.multiStreamBuffer = [[ABMultiStreamBuffer alloc] initWithClientFormat:_audioController.audioDescription];
    // Create an instance of the live buffer, for managing the live monitoring audio
    self.liveBuffer = [[ABLiveBuffer alloc] initWithClientFormat:_audioController.audioDescription];

    return YES;
}

- (void)updateInputChannels
{
    long newInputChannels = _audioController.numberOfInputChannels;
    
    if (newInputChannels > numInputChannels) {
        for (long i=numInputChannels; i<newInputChannels; i++) {
            if (-1 == i) {
                continue;
            }
            
            AEBlockAudioReceiver *receiver =
            [AEBlockAudioReceiver audioReceiverWithBlock:^(void                     *source,
                                                           const AudioTimeStamp     *time,
                                                           UInt32                    frames,
                                                           AudioBufferList          *audio) {
                void *portRef = NULL;
                if (i == _carrierChannelIndex-1) {
                    portRef = (void *)&kCoreAudioInputCarrierTag;
                } else if (i == _modifierChannelIndex-1) {
                    portRef = (void *)&kCoreAudioInputModifierTag;
                }
                if (portRef) {
                    char audioBufferListSpace[sizeof(AudioBufferList) + sizeof(AudioBuffer)];
                    AudioBufferList *bufferList = (AudioBufferList*)&audioBufferListSpace;
                    bufferList->mNumberBuffers = 2;
                    for ( int i=0; i<bufferList->mNumberBuffers; i++ ) {
                        bufferList->mBuffers[i].mNumberChannels = 1;
                        bufferList->mBuffers[i].mDataByteSize = audio->mBuffers[0].mDataByteSize;
                        bufferList->mBuffers[i].mData = audio->mBuffers[0].mData;
                    }
                    ABMultiStreamBufferEnqueue(_multiStreamBuffer,
                                               (ABMultiStreamBufferSource)portRef, // We use the port to identify the stream
                                               bufferList,
                                               frames,
                                               time);
                }
            }];
            [_audioController addInputReceiver:receiver forChannels:[NSArray arrayWithObject:[NSNumber numberWithLong:i]]];
            [self.inputReceiverArray addObject:receiver];
        }
    } else if (newInputChannels < numInputChannels) {
        for (long i=numInputChannels-1; i>=newInputChannels; i--) {
            AEBlockAudioReceiver *receiver = [self.inputReceiverArray objectAtIndex:i];
            [_audioController removeInputReceiver:receiver];
            [self.inputReceiverArray removeObjectAtIndex:i];
        }
    }
    
    numInputChannels = newInputChannels;
}

- (void)getBandValuesToArray:(float *)outArray
{
    memcpy(outArray, bandValues, sizeof(float)*3*2*NUM_BANDS);
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if ( context == &kInputChannelsChangedContext ) {
        [self updateInputChannels];
    }
}

- (void)applicationWillResignActive:(UIApplication *)application
{
    // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
    // Use this method to pause ongoing tasks, disable timers, and throttle down OpenGL ES frame rates. Games should use this method to pause the game.
}

- (void)applicationDidEnterBackground:(UIApplication *)application
{
    // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later. 
    // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
}

- (void)applicationWillEnterForeground:(UIApplication *)application
{
    // Called as part of the transition from the background to the inactive state; here you can undo many of the changes made on entering the background.
}

- (void)applicationDidBecomeActive:(UIApplication *)application
{
    // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
}

- (void)applicationWillTerminate:(UIApplication *)application
{
    // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
    cleanBiquadSetup();
}

@end
