//
//  ChorusViewController.swift
//  Chorus
//
//  Created by Chris Rivers on 12/09/2016.
//  Copyright © 2016 Chris Rivers. All rights reserved.
//

import UIKit
import CoreAudioKit

public class ManiViewController: AUViewController, AUAudioUnitFactory {

    @IBOutlet var mixControl: RotaryControl?
    @IBOutlet var rateControl: RotaryControl?
    @IBOutlet var depthControl: RotaryControl?
    @IBOutlet var feedbackControl: SwitchControl?
    @IBOutlet var delayControl: SwitchControl?
    
    var mixParameter:   AUParameter?
    var rateParameter: AUParameter?
    var depthParameter: AUParameter?
    var feedbackParameter: AUParameter?
    var delayParameter: AUParameter?
    var parameterObserverToken: AUParameterObserverToken?

    public var audioUnit: Mani? {
        didSet {
            DispatchQueue.main.async {
                // If the view has already been loaded, we need to connect it to this audio unit.
                if self.isViewLoaded {
                    if let audioUnit = self.audioUnit {
                        self.connectViewWithAU(audioUnit: audioUnit)
                    }
                }
            }
        }
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()

        // If the audiounit has already been initialized, we need to connect to it.
        if (audioUnit != nil) {
            connectViewWithAU(audioUnit: audioUnit)
        }
        
        // Wire up UI events
        mixControl?.addTarget(self, action: #selector(mixControlDidChangeValue), for: .valueChanged)
        rateControl?.addTarget(self, action: #selector(rateControlDidChangeValue), for: .valueChanged)
        depthControl?.addTarget(self, action: #selector(depthControlDidChangeValue), for: .valueChanged)
        
        feedbackControl?.addTarget(self, action: #selector(feedbackControlDidChangeValue), for: .valueChanged)
        delayControl?.addTarget(self, action: #selector(delayControlDidChangeValue), for: .valueChanged)
    }
    
    public override func viewWillAppear(_ animated: Bool) {
        // Initialize UI if we have a the parameters
        guard let mixParameter = mixParameter, let rateParameter = rateParameter, let depthParameter = depthParameter else {
            return
        }
        
        mixControl?.value = Double(mixParameter.value)
        rateControl?.value = Double(rateParameter.value)
        depthControl?.value = Double(depthParameter.value)
        feedbackControl?.isOn = (feedbackParameter?.value ?? 0.0 == 1.0)
        delayControl?.isOn = (delayParameter?.value ?? 0.0 == 1.0)
        
        
    }
    
    @objc func mixControlDidChangeValue() {
        mixParameter?.setValue(AUValue(mixControl!.value), originator: parameterObserverToken);
    }
    
    @objc func rateControlDidChangeValue() {
        rateParameter?.setValue(AUValue(rateControl!.value), originator: parameterObserverToken);
    }

    @objc func depthControlDidChangeValue() {
        depthParameter?.setValue(AUValue(depthControl!.value), originator: parameterObserverToken);
    }
    
    @objc func feedbackControlDidChangeValue() {
        feedbackParameter?.setValue((feedbackControl?.isOn ?? false) ? AUValue(1.0) : AUValue(0.0), originator: parameterObserverToken);
    }
 
    @objc func delayControlDidChangeValue() {
        delayParameter?.setValue((delayControl?.isOn ?? false) ? AUValue(1.0) : AUValue(0.0), originator: parameterObserverToken);
    }
    
    public func createAudioUnit(with desc: AudioComponentDescription) throws -> AUAudioUnit {        
        audioUnit = try Mani(componentDescription: desc, options: [])
        return audioUnit!
    }

    private func connectViewWithAU(audioUnit: AUAudioUnit?) {
        // Make sure we have a param tree from the audio unit
        guard let paramTree = audioUnit?.parameterTree else {
            return
        }
        
        // References to parameters
        mixParameter = paramTree.value(forKey: "mix") as? AUParameter
        rateParameter = paramTree.value(forKey: "rate") as? AUParameter
        depthParameter = paramTree.value(forKey: "depth") as? AUParameter
        feedbackParameter = paramTree.value(forKey: "feedback") as? AUParameter
        delayParameter = paramTree.value(forKey: "delay") as? AUParameter
        
        // Observer for parameter changes
        parameterObserverToken = paramTree.token(byAddingParameterObserver: {
            [weak self] address, value in
            
            guard let strongSelf = self else { return }
            
            DispatchQueue.main.async {
                if address == strongSelf.mixParameter!.address {
                    strongSelf.updateMixControl()
                } else if address == strongSelf.rateParameter!.address {
                    strongSelf.updateRateControl()
                } else if address == strongSelf.depthParameter!.address {
                    strongSelf.updateDepthControl()
                } else if address == strongSelf.feedbackParameter!.address {
                    strongSelf.updateFeedbackControl()
                } else if address == strongSelf.delayParameter!.address {
                    strongSelf.updateDelayControl()
                }
            }
        })
        
        updateMixControl()
        updateRateControl()
        updateDepthControl()
        updateFeedbackControl()
        updateDelayControl()
    }
    
    private func updateMixControl() {
        mixControl?.value = Double(mixParameter!.value)
    }
    
    private func updateRateControl() {
        rateControl?.value = Double(rateParameter!.value);
    }
    
    private func updateDepthControl() {
        depthControl?.value = Double(depthParameter!.value)
    }
    
    private func updateFeedbackControl() {
        feedbackControl?.isOn = feedbackParameter?.value ?? 0 == 1
    }
    
    private func updateDelayControl() {
        delayControl?.isOn = delayParameter?.value ?? 0 == 1
    }

}
