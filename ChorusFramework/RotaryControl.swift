//
//  RotaryControl.swfit
//  RotaryControl
//
//  Created by Chris on 04/07/2015.
//  Copyright © 2015 Lofionic. All rights reserved.
//
import UIKit
import Foundation
import QuartzCore

@IBDesignable
class RotaryControl : UIControl {

    public var value : Double = 0.0 {
        didSet {
            updateNeedle(animated: false)
        }
    }
    private(set) var defaultValue : Double = 0.0
    
    var doubleTapForDefault : Bool = true
    
    private var previousTrackingLocation : CGFloat?
    private var trackingTouches : Bool = false
    
    private var rotateLayer: CALayer = CALayer()
    
    let rotationalPlay: Double = (M_PI * 10) / 6.0
    let offset: Double = M_PI * (2 / 3.0)
    
    override func awakeFromNib() {
        self.initialize()
    }
    
    func initialize() {
        // Initialize properties
        self.backgroundColor = UIColor.clear
        self.isUserInteractionEnabled = true
        
        // Set up the double tap gesture
        let doubleTapGesture = UITapGestureRecognizer(target: self, action: #selector(doubleTap))
        doubleTapGesture.numberOfTapsRequired = 2
        self.addGestureRecognizer(doubleTapGesture)
        
        if let imageBase = UIImage(named: "knob_base") {
            let baseLayer: CALayer = CALayer()
            baseLayer.frame = self.bounds
            baseLayer.contents = imageBase.cgImage
            self.layer.addSublayer(baseLayer)
        }

        if let imageRotate = UIImage(named:"knob_rotate") {
            rotateLayer.frame = self.bounds
            rotateLayer.contents = imageRotate.cgImage
            self.layer.addSublayer(rotateLayer)
        }
        
        if let imageOverlay = UIImage(named:"knob_overlay") {
            let overlayLayer: CALayer = CALayer()
            overlayLayer.frame = self.bounds
            overlayLayer.contents = imageOverlay.cgImage
            self.layer.addSublayer(overlayLayer)
        }

        updateNeedle(animated: false)
    }

    @objc func doubleTap(gesture: UIGestureRecognizer) {
        if (gesture.state == UIGestureRecognizerState.ended && self.doubleTapForDefault) {
            value = defaultValue
        }
    }
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        // Begin touch tracking
        let firstTouch = touches.first
        previousTrackingLocation = firstTouch?.location(in: self).y
        trackingTouches = true
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        if (trackingTouches) {
            if let firstTouch = touches.first {
                let firstTouchLocation = firstTouch.location(in: self).y
                let delta = Double((firstTouchLocation - previousTrackingLocation!) / 300.0)
                value -= delta
                previousTrackingLocation = firstTouchLocation
            }
            
            if (value > 1.0) {
                value = 1.0
            } else if (value < 0) {
                value = 0
            }
            
            sendActions(for: .valueChanged)
        }
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        trackingTouches = false
        resignFirstResponder()
    }
    
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        touchesEnded(touches, with: event)
    }
    
    
    func updateNeedle(animated: Bool) {

        let disableAnimations: Bool = CATransaction.disableActions()
        CATransaction.setDisableActions(!animated)
        let theta: Double = rotationalPlay * value + offset
        rotateLayer.setAffineTransform(CGAffineTransform.identity.rotated(by: CGFloat(theta)))
        CATransaction.setDisableActions(disableAnimations)
    }
    
    override func prepareForInterfaceBuilder() {
        self.backgroundColor = UIColor.clear
        let bundle = Bundle(for: type(of: self))
        if let imageBase = UIImage(named: "knob_base", in: bundle, compatibleWith: self.traitCollection) {
            let baseLayer: CALayer = CALayer()
            baseLayer.frame = self.bounds
            baseLayer.contents = imageBase.cgImage
            self.layer.addSublayer(baseLayer)
        }
        
        if let imageRotate = UIImage(named:"knob_rotate", in: bundle, compatibleWith: self.traitCollection)  {
            rotateLayer.frame = self.bounds
            rotateLayer.contents = imageRotate.cgImage
            self.layer.addSublayer(rotateLayer)
        }
        
        if let imageOverlay = UIImage(named:"knob_overlay", in: bundle, compatibleWith: self.traitCollection)  {
            let overlayLayer: CALayer = CALayer()
            overlayLayer.frame = self.bounds
            overlayLayer.contents = imageOverlay.cgImage
            self.layer.addSublayer(overlayLayer)
        }
        
        updateNeedle(animated: false)
    }
}
