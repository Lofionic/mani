//
//  TransportView.swift
//  Duplicat
//
//  Created by Chris Rivers on 23/06/2016.
//  Copyright © 2016 Lofionic. All rights reserved.
//

import UIKit

public protocol IAATransportViewDelegate {
    
    func isHostPlaying() -> Bool
    func isHostRecording() -> Bool
    func isHostConnected() -> Bool
    func getHostIcon() -> UIImage?

    func canPlay() -> Bool
    func canRewind() -> Bool
    func canRecord() -> Bool
    
    
    func goToHost()
    func hostRewind()
    func hostPlay()
    func hostRecord()
}

open class IAATransportView: UIView {
    
    var delegate : IAATransportViewDelegate? {
        didSet {
            NotificationCenter.default.addObserver(self, selector: #selector(iaaTransportStateDidChangeNotification), name: NSNotification.Name(rawValue: kIAATransportStateChangedNotification), object: delegate as AnyObject?)
        }
    }
    
    @IBOutlet var hostIcon      : UIImageView!
    @IBOutlet var rewindButton  : UIButton!
    @IBOutlet var playButton    : UIButton!
    @IBOutlet var recordButton  : UIButton!
    
    var appIsForeground : Bool?
    
    open override func awakeFromNib() {

        isHidden = true // Assume hidden by default
        
        let appstate = UIApplication.shared.applicationState
        appIsForeground = appstate != .background
        
        NotificationCenter.default.addObserver(self,
                                                         selector: #selector(appHasGoneInBackground),
                                                         name: NSNotification.Name.UIApplicationDidEnterBackground,
                                                         object: nil)
        
        NotificationCenter.default.addObserver(self,
                                                         selector: #selector(appHasGoneForeground),
                                                         name: NSNotification.Name.UIApplicationWillEnterForeground,
                                                         object: nil)
        
        hostIcon.isUserInteractionEnabled = true
        hostIcon.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(onHostImageTapped)))
    
    }
 
    @objc
    func appHasGoneInBackground(note : NSNotification) {
        appIsForeground = false
    }
    
    @objc
    func appHasGoneForeground(note : NSNotification) {
        appIsForeground = true
        updateTransportControls()
    }
    
    @objc func iaaTransportStateDidChangeNotification(note : NSNotification) {
        updateTransportControls()
    }
    
    func updateTransportControls() {
        if let delegate = delegate {
            if (delegate.isHostConnected()) {
                self.isHidden = false;
            } else {
                self.isHidden = true;
            }
            
            self.playButton.isSelected = delegate.isHostPlaying()
            self.recordButton.isSelected = delegate.isHostRecording()
            
//            self.rewindButton.enabled = delegate.canRewind()
//            self.playButton.enabled = delegate.canPlay()
//            self.recordButton.enabled = delegate.canRecord()
            
            self.hostIcon.image = delegate.getHostIcon()
        }
    }
    
    @IBAction func onRewindTapped(sender: AnyObject) {
        if let delegateUnwrapped = delegate {
            delegateUnwrapped.hostRewind()
        }
    }
    
    @IBAction func onPlayTapped(sender: AnyObject) {
        if let delegateUnwrapped = delegate {
            delegateUnwrapped.hostPlay()
        }
    }
    
    @IBAction func onRecordTapped(sender: AnyObject) {
        if let delegateUnwrapped = delegate {
            delegateUnwrapped.hostRecord()
        }
    }
    
    @objc func onHostImageTapped(uigr : UIGestureRecognizer) {
        if let delegateUnwrapped = delegate {
            delegateUnwrapped.goToHost()
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }

}
