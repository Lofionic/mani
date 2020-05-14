//
//  SwitchControl.swift
//  Mani
//
//  Created by Chris on 18/01/2017.
//  Copyright © 2017 Chris Rivers. All rights reserved.
//

import UIKit
import Foundation

@IBDesignable
class SwitchControl : UIControl {
    
    private var switchLayer: CALayer?
    private var offImage: UIImage?
    private var onImage: UIImage?
    
    public var isOn: Bool = false {
        didSet {
            updateImage()
        }
    }
    
    func initialize() {
        backgroundColor = UIColor.clear;
        
        let sublayer = CALayer()
        sublayer.frame = self.bounds;
        self.layer.addSublayer(sublayer)
        self.switchLayer = sublayer;
        
        #if !TARGET_INTERFACE_BUILDER
            offImage = UIImage(named: "switch_off")
            onImage = UIImage(named: "switch_on")
        #else
            let bundle = Bundle(for: type(of: self))
            if let switchOff = UIImage(named: "switch_off", in: bundle, compatibleWith: self.traitCollection) {
                offImage = switchOff
            }
        #endif
        
        self.addTarget(self, action: #selector(didTouchUpInside), for: UIControlEvents.touchDown)
        
        updateImage()
    }
    
    override func awakeFromNib() {
        self.initialize()
    }
    
    @objc func didTouchUpInside() {
        if (!self.isOn) {
            self.isOn = true
        } else {
            self.isOn = false
        }
        
        self.sendActions(for: .valueChanged)
        updateImage()
    }
    
    func updateImage() {
        if let switchLayer = self.switchLayer {
            if (!self.isOn) {
                switchLayer.contents = offImage?.cgImage;
            } else {
                switchLayer.contents = onImage?.cgImage;
            }
        }
    }
    
    override func prepareForInterfaceBuilder() {
        initialize()
    }
}
