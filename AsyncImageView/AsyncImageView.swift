//
//  AsyncImageView.swift
//
//  Version 0.0.1
//
//  Created by Anas AIT ALI on 16/02/2015.
//  Copyright (c) 2015 aitali.co
//
//  Distributed under the permissive zlib License
//  Get the latest version from here:
//
//  https://github.com/anas10/AsyncImageView-Swift
//  based on AsyncImageView by nicklockwood
//
//  This software is provided 'as-is', without any express or implied
//  warranty.  In no event will the authors be held liable for any damages
//  arising from the use of this software.
//
//  Permission is granted to anyone to use this software for any purpose,
//  including commercial applications, and to alter it and redistribute it
//  freely, subject to the following restrictions:
//
//  1. The origin of this software must not be misrepresented; you must not
//  claim that you wrote the original software. If you use this software
//  in a product, an acknowledgment in the product documentation would be
//  appreciated but is not required.
//
//  2. Altered source versions must be plainly marked as such, and must not be
//  misrepresented as being the original software.
//
//  3. This notice may not be removed or altered from any source distribution.
//


import UIKit

// MARK: Global variables
let AsyncImageLoadDidFinish = "AsyncImageLoadDidFinish"
let AsyncImageLoadDidFail = "AsyncImageLoadDidFail"

let AsyncImageImageKey = "image"
let AsyncImageURLKey = "URL"
let AsyncImageCacheKey = "cache"
let AsyncImageErrorKey = "error"


// MARK: AsyncImageConnection
class AsyncImageConnection: NSObject {
    var connection: NSURLConnection?
    var data: NSMutableData?
    var URL: NSURL?
    var cache: NSCache?
    var target: AnyObject?
    var success: Selector?
    var failure: Selector?
    var loading : Bool = false
    var cancelled : Bool = false
 
    init(URL: NSURL?, cache: NSCache?, target: AnyObject?, success: Selector?, failure: Selector?) {
        super.init()
        
        self.URL = URL
        self.cache = cache
        self.target = target
        self.success = success
        self.failure = failure
    }
    
    func cachedImage() -> UIImage? {
        if (self.URL?.fileURL != nil) {
            if let path : NSString = self.URL!.absoluteURL?.path {
                if let resourcePath : NSString = NSBundle.mainBundle().resourcePath {
                    if path.hasPrefix(resourcePath) {
                        return UIImage(named: path.substringFromIndex(resourcePath.length))!
                    }
                }
            }
        }
        return self.cache?.objectForKey(self.URL!) as UIImage?
    }
    
    func isInCache() -> Bool {
        return self.cachedImage() != nil
    }
    
    func loadFailedWithError(error: NSError) {
        self.loading = false
        self.cancelled = false
        NSNotificationCenter.defaultCenter().postNotificationName(AsyncImageLoadDidFail,
            object: self.target, userInfo: [AsyncImageURLKey: self.URL!,
                AsyncImageErrorKey: error])
    }
    
    func cacheImage(image:UIImage?) {
        if (!self.cancelled) {
            if ((image != nil) && (self.URL != nil)) {
                var storeInCache = true
                if (self.URL?.fileURL != nil) {
                    if (self.URL!.absoluteURL?.path?.hasPrefix(NSBundle.mainBundle().resourcePath!) != nil) {
                       storeInCache = false
                    }
                }
                if storeInCache {
                    self.cache?.setObject(image!, forKey: self.URL!)
                }
            }
            var userInfo = Dictionary<String, AnyObject>()
            userInfo[AsyncImageImageKey] = image!
            userInfo[AsyncImageURLKey] = self.URL
            
            if (self.cache != nil) {
                userInfo[AsyncImageCacheKey] = self.cache
            }
            self.loading = false
            NSNotificationCenter.defaultCenter().postNotificationName(AsyncImageLoadDidFinish, object: self.target, userInfo: userInfo)
        } else {
            self.loading = false
            self.cancelled = false
        }
    }
    
    func processDataInBackground(data: NSData) {
        let lockQueue = dispatch_queue_create("co.aitali.AsyncImageView-swift", nil)
        dispatch_sync(lockQueue, { () -> Void in
            if !self.cancelled {
                var image = UIImage(data: data)
                if (image != nil) {
                    UIGraphicsBeginImageContextWithOptions(image!.size, false, image!.scale)
                    image!.drawAtPoint(CGPointZero)
                    image = UIGraphicsGetImageFromCurrentImageContext()
                    UIGraphicsEndImageContext()
                    self.cacheImage(image)
                } else {
                    autoreleasepool({ () -> () in
                        let error = NSError(domain: "AsyncImageLoader", code: 0, userInfo: [NSLocalizedDescriptionKey : "Invalid image data"])
                        self.loadFailedWithError(error)
                    })
                }
            } else {
                self.cacheImage(nil)
            }
        })
    }
    
    func connectionDidReceiveResponse(connection: NSURLConnection, response: NSURLResponse) {
        self.data = NSMutableData()
    }
    
    func connectionDidReceiveData(connection: NSURLConnection, data: NSData) {
        self.data?.appendData(data)
    }
    
    func connectionDidFinishLoading(connection: NSURLConnection) {
        if (self.data != nil) {
            self.processDataInBackground(self.data!)
        }
        self.connection = nil
        self.data = nil
    }
    
    func connectionDidFailWithError(connection: NSURLConnection, error: NSError) {
        self.connection = nil
        self.data = nil
        self.loadFailedWithError(error)
    }
    
    func start() {
        if self.loading && !self.cancelled {
            return
        }
        
        self.loading = true
        self.cancelled = false
        
        if self.URL == nil {
            self.cacheImage(nil)
            return
        }
        
        let image = self.cachedImage()
        if image != nil {
            dispatch_async(dispatch_get_main_queue(), { () -> Void in
                self.cacheImage(image)
            })
            return
        }
        
        let request : NSURLRequest = NSURLRequest(URL: self.URL!,
            cachePolicy: NSURLRequestCachePolicy.ReloadIgnoringLocalCacheData,
            timeoutInterval: AsyncImageLoader.sharedLoader.loadingTimeout)
        self.connection = NSURLConnection(request: request, delegate: self, startImmediately: false)
        self.connection?.scheduleInRunLoop(NSRunLoop.mainRunLoop(), forMode: NSRunLoopCommonModes)
        self.connection?.start()
    }
    
    func cancel() {
        self.cancelled = true
        self.connection?.cancel()
        self.connection = nil
        self.data = nil
    }
    
    func isLoading() -> Bool { return self.loading }
    func isCancelled() -> Bool { return self.cancelled }
}

// MARK: AsyncImageLoader
class AsyncImageLoader: NSObject {
    var cache: NSCache!
    let concurrentLoads: UInt = 2
    let loadingTimeout: NSTimeInterval = 60.0
    
    private var connections = [AsyncImageConnection]()
    
    class var sharedLoader : AsyncImageLoader {
        struct Static {
            static let instance : AsyncImageLoader = AsyncImageLoader()
        }
        return Static.instance
    }
    
    class var defaultCache : NSCache {
        struct Static {
            static let instance : NSCache = NSCache()
        }
        NSNotificationCenter.defaultCenter().addObserverForName(UIApplicationDidReceiveMemoryWarningNotification, object: nil, queue: NSOperationQueue.mainQueue()) { (note: NSNotification!) -> Void in
            Static.instance.removeAllObjects()
        }
        return Static.instance
    }
    
    override init() {
        super.init()
        
        self.cache = AsyncImageLoader.defaultCache
        NSNotificationCenter.defaultCenter().addObserver(self, selector: "imageLoaded:",
            name: AsyncImageLoadDidFinish, object: nil)
        NSNotificationCenter.defaultCenter().addObserver(self, selector: "imageFailed:",
            name: AsyncImageLoadDidFail, object: nil)
    }
    
    func updateQueue() {
        var count: UInt = 0
        for connection in self.connections {
            if !connection.isLoading() {
                if connection.isInCache() {
                    connection.start()
                } else if count < self.concurrentLoads {
                    count++
                    connection.start()
                }
            }
        }
    }
    
    func imageLoaded(notification: NSNotification) {
        let userInfo : Dictionary<String, AnyObject> = notification.userInfo as Dictionary<String, AnyObject>
        let URL: NSURL = userInfo[AsyncImageURLKey] as NSURL
        for var i = self.connections.count - 1; i >= 0 ; i-- {
            let connection : AsyncImageConnection = self.connections[i]
            if (connection.URL == URL || connection.URL?.isEqual(URL) != nil) {
//                TODO : Find a way to compare target. Not possible to compare two AnyObject
                
//                for var j = i - 1; j >= 0; j-- {
//                    let earlier : AsyncImageConnection = self.connections[j]
//                    if earlier.target == connection.target && earlier.success == connection.success {
//                        earlier.cancel()
//                        self.connections.removeAtIndex(j)
//                        i--
//                    }
//                }
                
                connection.cancel()
                
                let image : UIImage = userInfo[AsyncImageImageKey] as UIImage
//                ((void (*)(id, SEL, id, id))objc_msgSend)(connection.target, connection.success, image, connection.URL)
                
                self.connections.removeAtIndex(i)
            }
        }
        self.updateQueue()
    }
    
    func imageFailed(notification: NSNotification) {
        let userInfo : Dictionary<String, AnyObject> = notification.userInfo as Dictionary<String, AnyObject>
        let URL: NSURL = userInfo[AsyncImageURLKey] as NSURL
        for var i = self.connections.count - 1 ; i >= 0 ; i-- {
            let connection : AsyncImageConnection = self.connections[i]
            if (connection.URL?.isEqual(URL) != nil) {
                connection.cancel()
                if (connection.failure != nil) {
                    let error : NSError = userInfo[AsyncImageErrorKey] as NSError
//                    ((void (*)(id, SEL, id, id))objc_msgSend)(connection.target, connection.failure, error, URL)
                }
                
                self.connections.removeAtIndex(i)
            }
        }
        self.updateQueue()
    }
    
    func loadImageWithURL(URL: NSURL, target: AnyObject? = nil, success: Selector? = nil, failure: Selector? = nil) {
        let image : UIImage? = self.cache.objectForKey(URL) as? UIImage
        if (image != nil) {
            self.cancelLoadingImages(target, action: success)
            if (success != nil) {
                dispatch_async(dispatch_get_main_queue(), { () -> Void in
//                    ((void (*)(id, SEL, id, id))objc_msgSend)(target, success, image, URL)
                })
            }
            return
        }
        
        let connection : AsyncImageConnection = AsyncImageConnection(URL: URL, cache: cache,
            target: target, success: success, failure: failure)
        
        var added: Bool = false
        for var i = 0; i < self.connections.count; i++ {
            let existingConnection : AsyncImageConnection = self.connections[i]
            if !existingConnection.loading {
                self.connections.insert(connection, atIndex: i)
                added = true
                break
            }
        }
        if !added {
            self.connections.append(connection)
        }
        self.updateQueue()
    }
    
    func cancelLoadingURL(URL: NSURL, target: AnyObject?, action: Selector?) {
        for var i = self.connections.count - 1; i >= 0; i-- {
            let connection : AsyncImageConnection = self.connections[i]
            if connection.URL?.isEqual(URL) && connection.target == target && connection.success == action {
                connection.cancel()
                self.connections.removeAtIndex(i)
            }
        }
    }
    
    func cancelLoadingURL(URL: NSURL, target: AnyObject?) {
        for var i = self.connections.count - 1; i >= 0; i-- {
            let connection : AsyncImageConnection = self.connections[i]
            if connection.URL?.isEqual(URL) && connection.target == target {
                connection.cancel()
                self.connections.removeAtIndex(i)
            }
        }
    }
    
    func cancelLoadingURL(URL: NSURL) {
        for var i = self.connections.count - 1; i >= 0; i-- {
            let connection : AsyncImageConnection = self.connections[i]
            if (connection.URL?.isEqual(URL) != nil) {
                connection.cancel()
                self.connections.removeAtIndex(i)
            }
        }
    }

    func cancelLoadingImages(target: AnyObject?, action: Selector?) {
        for var i = self.connections.count - 1; i >= 0; i--
        {
            let connection : AsyncImageConnection = self.connections[i]
            if (connection.target == target && connection.success == action)
            {
                connection.cancel()
            }
        }
    }

    func cancelLoadingImages(target: AnyObject?) {
        for var i = self.connections.count - 1; i >= 0; i--
        {
            let connection : AsyncImageConnection = self.connections[i]
            if (connection.target == target)
            {
                connection.cancel()
            }
        }
    }

    func URLForTarget(target: AnyObject?, action: Selector?) -> NSURL? {
        for var i = self.connections.count - 1; i >= 0; i-- {
            let connection : AsyncImageConnection = self.connections[i]
            if connection.target == target && connection.success == action {
                return connection.URL
            }
        }
        return nil
    }
    
    func URLForTarget(target: AnyObject?) -> NSURL? {
        for var i = self.connections.count - 1; i >= 0; i-- {
            let connection : AsyncImageConnection = self.connections[i]
            if connection.target == target {
                return connection.URL
            }
        }
        return nil
    }

    deinit {
        NSNotificationCenter.defaultCenter().removeObserver(self)
    }
}

extension UIImageView {
    func setImageURL(imageURL: NSURL) {
        AsyncImageLoader.sharedLoader.loadImageWithURL(imageURL, target: self, success: "setImage:")
    }
    
    func imageURL() -> NSURL? {
        return AsyncImageLoader.sharedLoader.URLForTarget(self, action: "setImage:")
    }
}

// MARK: AsyncImageView
class AsyncImageView: UIImageView {
    var imageURL : NSURL?
    var showActivityIndicator : Bool = false
    var activityIndicatorStyle: UIActivityIndicatorViewStyle = UIActivityIndicatorViewStyle.Gray
    var crossfadeDuration: NSTimeInterval!
    var activityView : UIActivityIndicatorView?
    
    func setUp() {
        self.showActivityIndicator = (self.image == nil)
        self.activityIndicatorStyle = UIActivityIndicatorViewStyle.Gray
        self.crossfadeDuration = 0.4
    }
 
    override init(frame: CGRect) {
        super.init(frame: frame)
        setUp()
    }
    
    required init(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        setUp()
    }

    override func setImageURL(imageURL: NSURL) {
        let image : UIImage? = AsyncImageLoader.sharedLoader.cache.objectForKey(imageURL) as UIImage?
        if (image != nil) {
            self.image = image
            return
        }
        self.imageURL = imageURL
        if self.showActivityIndicator && !self.image && imageURL {
            if self.activityView == nil {
                self.activityView = UIActivityIndicatorView(activityIndicatorStyle: self.activityIndicatorStyle)
                self.activityView?.hidesWhenStopped = true
                self.activityView?.center = CGPointMake(self.bounds.size.width / 2.0, self.bounds.size.height / 2.0)
                self.activityView?.autoresizingMask = UIViewAutoresizing.FlexibleLeftMargin | UIViewAutoresizing.FlexibleTopMargin | UIViewAutoresizing.FlexibleRightMargin | UIViewAutoresizing.FlexibleBottomMargin
                self.addSubview(self.activityView)
            }
            self.activityView?.startAnimating()
        }
    }
    
    func setActivityIndicatorStyle(style: UIActivityIndicatorViewStyle) {
        activityIndicatorStyle = style
        self.activityView?.removeFromSuperview()
        self.activityView = nil
    }
    
    func setImage(image: UIImage?) {
        if (image != self.image && self.crossfadeDuration != nil) {
            // TODO
        }
        super.image = image
        self.activityView?.stopAnimating()
    }
    
    deinit {
        if self.imageURL != nil {
            AsyncImageLoader.sharedLoader.cancelLoadingURL(self.imageURL!, target: self)
        }
    }
}


