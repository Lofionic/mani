//
//  Created by Chris on 16/06/2015.
//  Copyright © 2015 Lofionic. All rights reserved.
//

#import "Mani.h"
#import <AVFoundation/AVFoundation.h>
#import "ManiDSPKernel.hpp"
#import "BufferedAudioBus.hpp"

static const UInt8 kNumberOfPresets = 4;
static const NSInteger kDefaultFactoryPreset = 0;

typedef struct FactoryPresetParameters {
    AUValue mixValue;
    AUValue rateValue;
    AUValue depthValue;
    AUValue feedbackValue;
    AUValue delayValue;
} FactoryPresetParameters;

static const FactoryPresetParameters presetParameters[kNumberOfPresets] {
    // preset 0
    { 0.5f, 0.5f, 0.5f, 0.0f, 0.0f },
    // preset 1
    { 0.9f, 0.8f, 0.2f, 0.0f, 1.0f },
    // preset 2
    { 0.9f, 0.1f, 0.9f, 1.0f, 0.0f },
    // preset 3
    { 0.9f, 0.7f, 0.6f, 0.0f, 1.0f }
};

static AUAudioUnitPreset * NewAUPreset(NSInteger number, NSString *name) {
    AUAudioUnitPreset *aPreset = [AUAudioUnitPreset new];
    aPreset.number = number;
    aPreset.name = name;
    return aPreset;
}

@interface Mani ()

@property AUAudioUnitBus *outputBus;
@property AUAudioUnitBusArray *inputBusArray;
@property AUAudioUnitBusArray *outputBusArray;

@end

@implementation Mani {
    ManiDSPKernel     _kernel;
    BufferedInputBus    _inputBus;
    
    AUAudioUnitPreset*  _currentPreset;
    NSInteger           _currentFactoryPresetIndex;
    NSArray<AUAudioUnitPreset*>* _presets;
}

@synthesize parameterTree = _parameterTree;
@synthesize factoryPresets = _presets;

-(instancetype)initWithComponentDescription:(AudioComponentDescription)componentDescription options:(AudioComponentInstantiationOptions)options error:(NSError * __nullable __autoreleasing * __nullable)outError {
    
    self = [super initWithComponentDescription:componentDescription options:options error:outError];
    
    if (self == nil) {
        return nil;
    }
    
    // Initialize default format for the busses
    AVAudioFormat *defaultFormat = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:44100. channels:2];
    
    // Create a DSP kernel to handle the signal processing
    _kernel.init(defaultFormat.channelCount, defaultFormat.sampleRate);
    
    // Create parameter objects
    AUParameter *mix = [AUParameterTree createParameterWithIdentifier:@"mix" name:@"Mix"
                                                              address:ChorusParamMix
                                                                  min:0.0
                                                                  max:1.0
                                                                 unit:kAudioUnitParameterUnit_LinearGain
                                                             unitName:nil
                                                                flags:0
                                                         valueStrings:nil
                                                  dependentParameters:nil];
    
    AUParameter *rate = [AUParameterTree createParameterWithIdentifier:@"rate" name:@"Rate"
                                                              address:ChorusParamRate
                                                                  min:0.0
                                                                  max:1.0
                                                                 unit:kAudioUnitParameterUnit_LinearGain
                                                             unitName:nil
                                                                flags:0
                                                         valueStrings:nil
                                                  dependentParameters:nil];
    
    AUParameter *depth = [AUParameterTree createParameterWithIdentifier:@"depth" name:@"Depth"
                                                              address:ChorusParamDepth
                                                                  min:0.0
                                                                  max:1.0
                                                                 unit:kAudioUnitParameterUnit_LinearGain
                                                             unitName:nil
                                                                flags:0
                                                         valueStrings:nil
                                                  dependentParameters:nil];
    
    AUParameter *feedback = [AUParameterTree createParameterWithIdentifier:@"feedback" name:@"Feedback"
                                                                   address:ChorusParamFeedback
                                                                       min:0.0
                                                                       max:1.0
                                                                      unit:kAudioUnitParameterUnit_Boolean
                                                                  unitName:nil
                                                                     flags:0
                                                              valueStrings:nil
                                                       dependentParameters:nil];
    
    AUParameter *delay = [AUParameterTree createParameterWithIdentifier:@"delay" name:@"Delay"
                                                                   address:ChorusParamDelay
                                                                       min:0.0
                                                                       max:1.0
                                                                      unit:kAudioUnitParameterUnit_Boolean
                                                                  unitName:nil
                                                                     flags:0
                                                               valueStrings:nil
                                                       dependentParameters:nil];

    // Initialize parameter values
    mix.value       = 0.5;
    rate.value      = 0.5;
    depth.value     = 0.5;
    feedback.value  = 0.0;
    delay.value     = 0.0;

    _kernel.setParameter(ChorusParamMix, mix.value);
    _kernel.setParameter(ChorusParamRate, rate.value);
    _kernel.setParameter(ChorusParamDepth, depth.value);
    _kernel.setParameter(ChorusParamFeedback, feedback.value);
    _kernel.setParameter(ChorusParamDelay, delay.value);
    
    // Create factory preset array
    _currentFactoryPresetIndex = kDefaultFactoryPreset;
    _presets = @[NewAUPreset(0, @"Factori"), NewAUPreset(1, @"Minimi"), NewAUPreset(2, @"Flangi"), NewAUPreset(3, @"Nauti")];
    
    // Create the parameter tree
    _parameterTree = [AUParameterTree createTreeWithChildren:@[mix, rate, depth, feedback, delay]];
    
    // Create the input and output busses.
    _inputBus.init(defaultFormat, 8);
    _outputBus = [[AUAudioUnitBus alloc] initWithFormat:defaultFormat error:nil];
    
    // Create the input and output bus arrays
    _inputBusArray = [[AUAudioUnitBusArray alloc] initWithAudioUnit:self busType:AUAudioUnitBusTypeInput busses:@[_inputBus.bus]];
    _outputBusArray = [[AUAudioUnitBusArray alloc] initWithAudioUnit:self busType:AUAudioUnitBusTypeOutput busses:@[_outputBus]];
    
    // Make a local pointer to the kernel to avoid capturing self
    __block ManiDSPKernel *chorusKernel = &_kernel;
    
    // implementorValueObserver is called when a parameter changes value.
    _parameterTree.implementorValueObserver = ^(AUParameter *param, AUValue value) {
        chorusKernel->setParameter(param.address, value);
    };
    
    // implementorValueProvider is called when the value needs to be refreshed.
    _parameterTree.implementorValueProvider = ^(AUParameter *param) {
        return chorusKernel->getParameter(param.address);
    };
    
    // A function to provide string representations of parameter values
    _parameterTree.implementorStringFromValueCallback = ^(AUParameter *param, const AUValue *__nullable valuePtr) {
        AUValue value = valuePtr == nil ? param.value : *valuePtr;
        
        switch (param.address) {
            case ChorusParamMix:
            case ChorusParamDepth:
            case ChorusParamRate:
                return [NSString stringWithFormat:@"%.2f", value];
            case ChorusParamFeedback:
            case ChorusParamDelay:
                return (value == 0.1 ? @"On" : @"Off");
            default:
                return @"?";
            }
    };

    self.maximumFramesToRender = 512;
    self.currentPreset = _presets.firstObject;
    
    return self;
}

#pragma mark - AVAudioUnit overrides

- (AUAudioUnitBusArray *)inputBusses {
    return _inputBusArray;
}

- (AUAudioUnitBusArray *)outputBusses {
    return _outputBusArray;
}

-(BOOL)allocateRenderResourcesAndReturnError:(NSError * __nullable __autoreleasing * __nullable)outError {
    if (![super allocateRenderResourcesAndReturnError:outError]) {
        return NO;
    }
    
    if (self.outputBus.format.channelCount != _inputBus.bus.format.channelCount) {
        if (outError) {
            *outError = [NSError errorWithDomain:NSOSStatusErrorDomain code:kAudioUnitErr_FailedInitialization userInfo:nil];
        }
        
        return NO;
    }
    
    _inputBus.allocateRenderResources(self.maximumFramesToRender);
    
    _kernel.init(self.outputBus.format.channelCount, self.outputBus.format.sampleRate);
    _kernel.reset();
    
    return YES;
}

-(void)deallocateRenderResources {
    [super deallocateRenderResources];
    
    _inputBus.deallocateRenderResources();
}

-(AUInternalRenderBlock)internalRenderBlock {
    /*
     Capture in locals to avoid ObjC member lookups. If "self" is captured in
     render, we're doing it wrong.
     */
    __block ManiDSPKernel *state = &_kernel;
    __block BufferedInputBus *input = &_inputBus;
    
    return ^AUAudioUnitStatus(
                              AudioUnitRenderActionFlags *actionFlags,
                              const AudioTimeStamp       *timestamp,
                              AVAudioFrameCount           frameCount,
                              NSInteger                   outputBusNumber,
                              AudioBufferList            *outputData,
                              const AURenderEvent        *realtimeEventListHead,
                              AURenderPullInputBlock      pullInputBlock) {
        
        AudioUnitRenderActionFlags pullFlags = 0;
        
        AUAudioUnitStatus err = input->pullInput(&pullFlags, timestamp, frameCount, 0, pullInputBlock);
        
        if (err != 0) {
            return err;
        }
        
        AudioBufferList *inAudioBufferList = input->mutableAudioBufferList;
        
        /*
         If the caller passed non-nil output pointers, use those. Otherwise,
         process in-place in the input buffer. If your algorithm cannot process
         in-place, then you will need to preallocate an output buffer and use
         it here.
         */
        AudioBufferList *outAudioBufferList = outputData;
        if (outAudioBufferList->mBuffers[0].mData == nullptr) {
            for (UInt32 i = 0; i <= outAudioBufferList->mNumberBuffers; ++i) {
                outAudioBufferList->mBuffers[i].mData = inAudioBufferList->mBuffers[i].mData;
            }
        }

        state->setBuffers(inAudioBufferList, outAudioBufferList);
        state->processWithEvents(timestamp, frameCount, realtimeEventListHead);
        
        return noErr;
    };
}

- (BOOL)canProcessInPlace {
    return true;
}

#pragma mark AUAudioUnit (Preset Management)

- (AUAudioUnitPreset *)currentPreset
{
    if (_currentPreset.number >= 0) {
        NSLog(@"Returning Current Factory Preset: %ld\n", (long)_currentFactoryPresetIndex);
        return [_presets objectAtIndex:_currentFactoryPresetIndex];
    } else {
        NSLog(@"Returning Current Custom Preset: %ld, %@\n", (long)_currentPreset.number, _currentPreset.name);
        return _currentPreset;
    }
}

- (void)setCurrentPreset:(AUAudioUnitPreset *)currentPreset
{
    if (nil == currentPreset) { NSLog(@"nil passed to setCurrentPreset!"); return; }
    
    if (currentPreset.number >= 0) {
        // factory preset
        for (AUAudioUnitPreset *factoryPreset in _presets) {
            if (currentPreset.number == factoryPreset.number) {
                
                AUParameter *mixParameter = [self.parameterTree valueForKey:@"mix"];
                AUParameter *rateParameter = [self.parameterTree valueForKey:@"rate"];
                AUParameter *depthParameter = [self.parameterTree valueForKey:@"depth"];
                AUParameter *feedbackParameter = [self.parameterTree valueForKey:@"feedback"];
                AUParameter *delayParameter = [self.parameterTree valueForKey:@"delay"];
                
                mixParameter.value = presetParameters[factoryPreset.number].mixValue;
                rateParameter.value = presetParameters[factoryPreset.number].rateValue;
                depthParameter.value = presetParameters[factoryPreset.number].depthValue;
                feedbackParameter.value = presetParameters[factoryPreset.number].feedbackValue;
                delayParameter.value = presetParameters[factoryPreset.number].delayValue;
                
                // set factory preset as current
                _currentPreset = currentPreset;
                _currentFactoryPresetIndex = factoryPreset.number;
                NSLog(@"currentPreset Factory: %ld, %@\n", (long)_currentFactoryPresetIndex, factoryPreset.name);
                
                break;
            }
        }
    } else if (nil != currentPreset.name) {
        // set custom preset as current
        _currentPreset = currentPreset;
        NSLog(@"currentPreset Custom: %ld, %@\n", (long)_currentPreset.number, _currentPreset.name);
    } else {
        NSLog(@"setCurrentPreset not set! - invalid AUAudioUnitPreset\n");
    }
}

@end
