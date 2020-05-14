//
//  ViewController.swift
//  Chorus
//
//  Created by Chris Rivers on 12/09/2016.
//  Copyright © 2016 Chris Rivers. All rights reserved.
//

import UIKit
import ManiFramework

class ViewController: UIViewController {
    
    let appextensionBundleId = "ManiAppex.appex"
    
    @IBOutlet var transportView: IAATransportView?
    @IBOutlet var backgroundImageView: UIImageView?
    @IBOutlet var auContainerView: UIView?
    @IBOutlet var auContainerBevelView: UIImageView?
    @IBOutlet var auBackgroundImageView: UIImageView?
    
    @IBOutlet var userGuideView             : UIImageView?
    @IBOutlet var userGuideZoomConstraint   : NSLayoutConstraint?
    
    var pluginViewController: ManiViewController?
    var userGuideZoomed: Bool = false {
        didSet {
            if userGuideZoomed != oldValue {
                userGuideZoomConstraint?.isActive = userGuideZoomed
                view.setNeedsUpdateConstraints()
                
                UIView.animate(withDuration: 0.2, animations: {
                    self.view.layoutIfNeeded()
                })
                
            }
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Configure images
        if let auContainerBevelView = auContainerBevelView, let auContainerBevelBackgroundImage = auContainerBevelView.image {
            auContainerBevelView.image = auContainerBevelBackgroundImage.resizableImage(withCapInsets: UIEdgeInsetsMake(8, 8, 8, 8), resizingMode: UIImageResizingMode.stretch);
        }
        
        if let auBackgroundImageView = auBackgroundImageView, let auBackgroundImageViewImage = auBackgroundImageView.image {
            auBackgroundImageView.image = auBackgroundImageViewImage.resizableImage(withCapInsets: .zero, resizingMode: .tile)
        }
        
        embedPlugin()
        
        let appDelegate = UIApplication.shared.delegate as! AppDelegate
        if let iaaWrapper = appDelegate.iaaWrapper {
            
            // Create the iaaWrapper and publish it for IAA
            iaaWrapper.delegate = self
            iaaWrapper.createAndPublish()
            
            if let transportView = transportView {
                // Link transport view to the iaaWrapper
                transportView.delegate = iaaWrapper
            }
        }
        
        // Add gesture for taps on user guide
        userGuideView?.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(onUserGuideTapped)))
        userGuideView?.isUserInteractionEnabled = true
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.

    }

    private func embedPlugin() {

        // Locate the app extension bundle.
        guard let builtInPluginsURL = Bundle.main.builtInPlugInsURL else {
            return
        }
        
        let pluginURL = builtInPluginsURL.appendingPathComponent(appextensionBundleId)
        guard let appExtensionBundle = Bundle(url: pluginURL) else {
            return
        }
        
        // Locate the app extension storyboard
        let storyboard = UIStoryboard(name: "MainInterface", bundle: appExtensionBundle)
        
        // Present the view
        guard let pluginViewController = storyboard.instantiateInitialViewController() as? ManiViewController else {
            return
        }
        
        guard let view = pluginViewController.view else {
                return
        }
        
        guard let auContainerView = auContainerView else {
            return
        }
        
        addChildViewController(pluginViewController)
        view.frame = auContainerView.bounds
        view.backgroundColor = UIColor.clear
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        
        auContainerView.addSubview(view)
        pluginViewController.didMove(toParentViewController: self)
        
        self.pluginViewController = pluginViewController
    }
    
    override var preferredStatusBarStyle: UIStatusBarStyle {
        return .lightContent
    }
    
    @objc func onUserGuideTapped(_ uigr: UIGestureRecognizer) {
        // Toggle userguide zoom
        userGuideZoomed = !userGuideZoomed
    }
    
}

extension ViewController : IAAWrapperDelegate {
    func audioUnitDidConnect(_ iaaWrapper: IAAWrapper, audioUnit : AUAudioUnit?) {
        if let pluginViewController = pluginViewController, let audioUnit = audioUnit  {
            pluginViewController.audioUnit = (audioUnit as? Mani)
        }
    }
}

