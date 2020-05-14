//
//  Created by Chris on 20/06/2015.
//  Copyright © 2015 Lofionic. All rights reserved.
//

#ifndef ManiDSPKernel_cpp
#define ManiDSPKernel_cpp

#import "DSPKernel.hpp"
#import "ParameterRamper.hpp"
#import "Wavetable.hpp"
#import <vector>


Wavetable wavetable;


enum {
    ChorusParamMix,
    ChorusParamRate,
    ChorusParamDepth,
    ChorusParamFeedback,
    ChorusParamDelay
};

// Effect Constants
const float maximumDepthMs = 5;
const float minimumRateHz = 0.05;
const float maximumRateHz = 20.0;

// Calculated constants
const float maximumDepthS = maximumDepthMs / 1000;
const float rangeOfRateHz = maximumRateHz - minimumRateHz;
const float M_PI2 = M_PI * 2;

class ManiDSPKernel : public DSPKernel {
    
public:

    struct ChorusState {

        float *buffer;
        UInt32 bufferPosition = 0;
        UInt32 bufferSize = 0;
        
        float chorusBufferPosition = 0;
        float lfoPhase = 0;
        
        float feedback;
        
        void init(UInt32 inBufferSize) {
            
            bufferSize = inBufferSize;
            
            free(buffer);
            buffer = (float*)malloc(bufferSize * sizeof(float));
            memset(buffer, 0, bufferSize * sizeof(float));
            
            bufferPosition = 1;
            
            lfoPhase = 0;
            feedback = 0;
        }
        
        void incrementBuffer() {
            bufferPosition ++;
            if (bufferPosition == bufferSize) {
                bufferPosition = 0;
            }
        }
    };
    
    ManiDSPKernel() {}
    
    void init(int channelCount, double inSampleRate) {
        chorusStates.resize(channelCount);
        
        sampleRate = float(inSampleRate * 4);
        
        for (ChorusState& state : chorusStates) {
            state.init(sampleRate);
        }
        
        dezipperRampDuration = (AUAudioFrameCount)floor(0.02 * sampleRate);
        dezipperRampDurationRate = (AUAudioFrameCount)floor(0.02 * sampleRate) * 5;
        mixRamper.init();
        rateRamper.init();
        depthRamper.init();
        
        wavetable.init();
        
    }
    
    void setBuffers(AudioBufferList* inBufferList, AudioBufferList* outBufferList) {
        inBufferListPtr = inBufferList;
        outBufferListPtr = outBufferList;
    }

    void process(AUAudioFrameCount frameCount, AUAudioFrameCount bufferOffset) override {

        int channelCount = int(chorusStates.size());
        
        mixRamper.dezipperCheck(dezipperRampDuration);
        rateRamper.dezipperCheck(dezipperRampDurationRate);
        depthRamper.dezipperCheck(dezipperRampDurationRate);
        
        // For each sample.
        for (int frameIndex = 0; frameIndex < frameCount; ++frameIndex) {
            int frameOffset = int(frameIndex + bufferOffset);
            
            double mixLevel = double(mixRamper.getAndStep());
            double rateLevel = double(rateRamper.getAndStep());
            double depthLevel = double(depthRamper.getAndStep());
            
            bool feedbackOn = (feedback == 1);
            bool delayOn = (delay == 1);
            
            for (int channel = 0; channel < channelCount; ++channel) {
                ChorusState &state = chorusStates[channel];
                
                float *in   = (float*)inBufferListPtr->mBuffers[channel].mData  + frameOffset;
                float *out  = (float*)outBufferListPtr->mBuffers[channel].mData + frameOffset;
                
                state.buffer[state.bufferPosition] = *in;
                
                // Modulation Depth in samples = delay in ms * sample rate
                float lfoDepthInSamples = (powf(depthLevel, 3) * maximumDepthS) * sampleRate;
                
                float lfoOffset = lfoDepthInSamples * ((wavetable.sampleTable(state.lfoPhase) + 1) / 2);

                // Uncomment to add predelay
                if (delayOn) {
                    lfoOffset += (0.01 * sampleRate);
                }
                
                float delayBuffer = state.bufferPosition - lfoOffset;
                
                // Increment LFO Phase
                float lfoFreq = minimumRateHz + (rangeOfRateHz * powf(rateLevel, 4)); // LFO rate, Hz
                state.lfoPhase += lfoFreq * (M_PI2 / sampleRate);
                
                while (state.lfoPhase > 2.0 * M_PI) {
                    state.lfoPhase -= (2.0 * M_PI);
                }
                
                while (delayBuffer >= state.bufferSize) {
                    delayBuffer -= state.bufferSize;
                }
                
                while (delayBuffer < 0) {
                    delayBuffer += state.bufferSize;
                }
                
                float cleanOut = state.buffer[state.bufferPosition];
                cleanOut = *in;
                
                int delayBufferFloor = (int)floor(delayBuffer);
                while (delayBufferFloor < 0) {
                    delayBufferFloor += state.bufferSize;
                }
                
                while (delayBufferFloor >= state.bufferSize) {
                    delayBufferFloor -= state.bufferSize;
                }
                
                int delayBufferCeil = (int)ceil(delayBuffer);
                while (delayBufferCeil < 0) {
                    delayBufferCeil += state.bufferSize;
                }
                
                while (delayBufferCeil >= state.bufferSize) {
                    delayBufferCeil -= state.bufferSize;
                }

                float delayOutA = state.buffer[delayBufferFloor];
                float delayOutB = state.buffer[delayBufferCeil];
                float i = delayBuffer - floor(delayBuffer);
                float delayOutInterpolated = delayOutA + ((delayOutB - delayOutA) * i);
                
                float chorusOut = tanhf(delayOutInterpolated + cleanOut) * 1.03;
                
                // Interpolate between out and in signals.
                *out = cleanOut + ((chorusOut - cleanOut) * mixLevel);
                
                if (feedbackOn) {
                    state.buffer[state.bufferPosition] = tanhf(state.buffer[state.bufferPosition] + delayOutInterpolated * 0.8);
                }
                
                // Increment the buffer
                state.bufferPosition ++;
                if (state.bufferPosition >= state.bufferSize) {
                    state.bufferPosition -= state.bufferSize;
                }
            }
        }
    }


    void setParameter(AUParameterAddress address, AUValue value) {
        switch (address) {
            case ChorusParamMix:
                mixRamper.setUIValue(clamp(value, 0.0f, 1.0f));
                break;
            case ChorusParamRate:
                rateRamper.setUIValue(clamp(value, 0.0f, 1.0f));
                break;
            case ChorusParamDepth:
                depthRamper.setUIValue(clamp(value, 0.0f, 1.0f));
                break;
            case ChorusParamFeedback:
                feedback = clamp(value, 0.0f, 1.0f);
                break;
            case ChorusParamDelay:
                delay = clamp(value, 0.0f, 1.0f);
                break;
        }
    }
    
    AUValue getParameter(AUParameterAddress address) {
        switch (address) {
            case ChorusParamMix:
                return mixRamper.getUIValue();
            case ChorusParamRate:
                return rateRamper.getUIValue();
            case ChorusParamDepth:
                return depthRamper.getUIValue();
            case ChorusParamFeedback:
                return feedback;
            case ChorusParamDelay:
                return delay;
            default: return 0.0f;
        }
    }
    
    void startRamp(AUParameterAddress address, AUValue value, AUAudioFrameCount duration) override {
        switch (address) {
            case ChorusParamMix:
                mixRamper.startRamp(clamp(value, 0.0f, 1.0f), duration);
                break;
            case ChorusParamRate:
                rateRamper.startRamp(clamp(value, 0.0f, 1.0f), duration);
                break;
            case ChorusParamDepth:
                depthRamper.startRamp(clamp(value, 0.0f, 1.0f), duration);
                break;
            case ChorusParamFeedback:
                feedback = clamp(value, 0.0f, 1.0f);
                break;
            case ChorusParamDelay:
                delay = clamp(value, 0.0f, 1.0f);
                break;
        }
    }
    
    void reset() {
        for (ChorusState& state : chorusStates) {
            state.init(sampleRate * 4);
        }
    }
    
    
private:
    std::vector<ChorusState> chorusStates;
    
    float sampleRate = 44100.0;
    
    AudioBufferList* inBufferListPtr = nullptr;
    AudioBufferList* outBufferListPtr = nullptr;
    
    AUAudioFrameCount dezipperRampDuration;
    AUAudioFrameCount dezipperRampDurationRate;
    
public:
    ParameterRamper mixRamper = 0.0;
    ParameterRamper rateRamper = 0.0;
    ParameterRamper depthRamper = 0.0;
    
    float feedback;
    float delay;
};


#endif /* ManiDSPKernel_cpp */
