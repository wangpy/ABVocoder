//
//  ABVViewController.h
//  ABVocoder
//
//  Created by Brian Wang on 4/22/14.
//  Copyright (c) 2014 Positive Grid LLC. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface ABVViewController : UIViewController

@property (nonatomic, strong) IBOutlet UILabel *numberOfInputLabel;
@property (nonatomic, strong) IBOutlet UIView *portIconContainerView;
@property (nonatomic, strong) IBOutlet UIView *bandValuesView;
@property (nonatomic, strong) IBOutlet UISlider *outputGainSlider;
@property (nonatomic, strong) IBOutlet UILabel *outputGainLabel;
@property (nonatomic, strong) IBOutlet UIButton *carrierIcon;
@property (nonatomic, strong) IBOutlet UIButton *modifierIcon;

@end
