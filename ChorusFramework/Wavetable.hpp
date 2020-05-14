//
//  Wavetable.hpp
//  Mani
//
//  Created by Chris Rivers on 16/01/2017.
//  Copyright © 2017 Chris Rivers. All rights reserved.
//

#ifndef Wavetable_hpp
#define Wavetable_hpp

#define WAVETABLE_SIZE      65584
#define ANALOG_HARMONICS    100

class Wavetable {
    double ccSinWaveTable[WAVETABLE_SIZE];
    
    public:

    void init() {
        // Sin wavetable
        for (int i = 0; i < WAVETABLE_SIZE; i++) {
            double tablePhase = (i / (float)WAVETABLE_SIZE + 1.0) * (M_PI * 2);
            double a = sin(tablePhase);
            ccSinWaveTable[i] = a;
        }
    }

    double sampleTable(double phase) {
        float sampleIndexFloat = (phase / (M_PI * 2)) * (WAVETABLE_SIZE - 1);
        
        double sampleLower = 0;
        double sampleUpper = 0;
        float remainder = 0;

        sampleLower = ccSinWaveTable[(int)floor(sampleIndexFloat)];
        sampleUpper = ccSinWaveTable[(int)ceil(sampleIndexFloat)];
        
        remainder = fmodf(sampleIndexFloat, 1);
        return sampleLower + (sampleUpper - sampleLower) * remainder;
    }
};

#endif /* Wavetable_hpp */
